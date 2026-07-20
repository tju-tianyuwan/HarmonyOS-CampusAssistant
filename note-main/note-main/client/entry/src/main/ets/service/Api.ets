import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';

/** SSE 流式回调 */
export interface StreamCallbacks {
  onSources: (sources: string[]) => void;
  onDelta: (delta: string) => void;
  onDone: () => void;
  onError: (msg: string) => void;
}

/**
 * 网络层。
 * 模拟器访问宿主机：QEMU NAT 下宿主机回环地址为 10.0.2.2；
 * 若不通，改为电脑局域网 IP，并用 --host 0.0.0.0 启动服务端。
 */
export class Api {
  static BASE_URL: string = 'http://10.0.2.2:8000/api/v1';
  private static readonly TIMEOUT_MS: number = 30000;

  static async get(path: string): Promise<string> {
    return Api.request(path, http.RequestMethod.GET, undefined);
  }

  static async post(path: string, body?: object): Promise<string> {
    return Api.request(path, http.RequestMethod.POST,
      body === undefined ? undefined : JSON.stringify(body));
  }

  static async put(path: string, body: object): Promise<string> {
    return Api.request(path, http.RequestMethod.PUT, JSON.stringify(body));
  }

  private static async request(path: string, method: http.RequestMethod,
    body: string | undefined): Promise<string> {
    const client: http.HttpRequest = http.createHttp();
    try {
      const options: http.HttpRequestOptions = {
        method: method,
        header: { 'Content-Type': 'application/json' } as Record<string, string>,
        connectTimeout: Api.TIMEOUT_MS,
        readTimeout: Api.TIMEOUT_MS,
        expectDataType: http.HttpDataType.STRING,
        extraData: body
      };
      const resp: http.HttpResponse = await client.request(Api.BASE_URL + path, options);
      if (resp.responseCode >= 200 && resp.responseCode < 300) {
        return resp.result as string;
      }
      throw new Error(`HTTP ${resp.responseCode}: ${resp.result as string}`);
    } finally {
      client.destroy();
    }
  }

  /** 音频分片 multipart 上传 */
  static async uploadChunk(sessionId: number, seq: number, data: ArrayBuffer): Promise<string> {
    const client: http.HttpRequest = http.createHttp();
    try {
      const form: http.MultiFormData = {
        name: 'file',
        contentType: 'application/octet-stream',
        remoteFileName: `chunk_${seq}.pcm`,
        data: data
      };
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: { 'Content-Type': 'multipart/form-data' } as Record<string, string>,
        connectTimeout: Api.TIMEOUT_MS,
        readTimeout: Api.TIMEOUT_MS,
        expectDataType: http.HttpDataType.STRING,
        multiFormDataList: [form]
      };
      const resp: http.HttpResponse = await client.request(
        `${Api.BASE_URL}/sessions/${sessionId}/chunks/${seq}`, options);
      if (resp.responseCode >= 200 && resp.responseCode < 300) {
        return resp.result as string;
      }
      throw new Error(`HTTP ${resp.responseCode}`);
    } finally {
      client.destroy();
    }
  }

  /**
   * SSE 流式问答。服务端事件序列：sources → data*N → done。
   * 基于 requestInStream 增量接收，utf-8 流式解码防止多字节字符截断。
   */
  static streamAsk(chatSessionId: number, question: string, contextNote: string,
    cb: StreamCallbacks): void {
    const client: http.HttpRequest = http.createHttp();
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
    let buffer: string = '';
    let currentEvent: string = 'message';
    let finished: boolean = false;

    const finish = (err: string | null): void => {
      if (finished) {
        return;
      }
      finished = true;
      if (err !== null) {
        cb.onError(err);
      } else {
        cb.onDone();
      }
      client.destroy();
    };

    const handleBlock = (block: string): void => {
      const lines: string[] = block.split('\n');
      const datas: string[] = [];
      for (const line of lines) {
        if (line.startsWith('event:')) {
          currentEvent = line.substring(6).trim();
        } else if (line.startsWith('data:')) {
          datas.push(line.substring(5).trim());
        }
      }
      if (datas.length === 0) {
        return;
      }
      const data: string = datas.join('\n');
      if (currentEvent === 'sources') {
        try {
          cb.onSources(JSON.parse(data) as string[]);
        } catch (e) {
          cb.onSources([]);
        }
      } else if (currentEvent === 'done') {
        finish(null);
      } else {
        try {
          cb.onDelta(JSON.parse(data) as string);
        } catch (e) {
          // 非 JSON 数据块忽略
        }
      }
      currentEvent = 'message';
    };

    client.on('dataReceive', (chunk: ArrayBuffer) => {
      buffer += decoder.decodeWithStream(new Uint8Array(chunk), { stream: true });
      let idx: number = buffer.indexOf('\n\n');
      while (idx >= 0) {
        const block: string = buffer.substring(0, idx);
        buffer = buffer.substring(idx + 2);
        handleBlock(block);
        idx = buffer.indexOf('\n\n');
      }
    });
    client.on('dataEnd', () => {
      finish(null);
    });

    interface AskBody {
      chat_session_id: number;
      question: string;
      context_note: string;
    }

    const body: AskBody = {
      chat_session_id: chatSessionId,
      question: question,
      context_note: contextNote
    };
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: { 'Content-Type': 'application/json' } as Record<string, string>,
      connectTimeout: Api.TIMEOUT_MS,
      readTimeout: 120000,
      extraData: JSON.stringify(body)
    };
    client.requestInStream(Api.BASE_URL + '/chat/ask', options)
      .then((code: number) => {
        if (code < 200 || code >= 300) {
          finish(`HTTP ${code}`);
        }
      })
      .catch((err: Error) => {
        finish(err.message);
      });
  }
}
