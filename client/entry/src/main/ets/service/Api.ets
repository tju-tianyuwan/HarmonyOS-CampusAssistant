import { http } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { AiAgentInfo } from '../model/Models';

/** SSE 流式回调 */
export interface StreamCallbacks {
  onSources: (sources: string[]) => void;
  onWarning: (msg: string) => void;
  onDelta: (delta: string) => void;
  onAgent?: (agent: AiAgentInfo) => void;
  onAgentDone?: (agentId: string) => void;
  onMetadata?: (metadata: string) => void;
  onDone: () => void;
  onError: (msg: string) => void;
}

/** 网络版固定连接智伴云服务；ohosTest 独立测试包使用隔离服务。 */
export class Api {
  static BASE_URL: string = 'http://47.114.55.34:8000/api/v1';
  private static readonly TIMEOUT_MS: number = 30000;

  static token: string = '';
  private static generation: number = 0;

  static setAccessToken(token: string): void {
    Api.token = token;
    Api.generation++;
  }

  private static headers(contentType: string): Record<string, string> {
    const result: Record<string, string> = { 'Content-Type': contentType };
    if (Api.token !== '') { result['Authorization'] = `Bearer ${Api.token}`; }
    return result;
  }

  private static checkSession(code: number, generation: number): void {
    if (code === 401 && generation === Api.generation && Api.token !== '') {
      Api.setAccessToken('');
      AppStorage.setOrCreate<number>('authExpiredTick', (AppStorage.get<number>('authExpiredTick') ?? 0) + 1);
    }
  }

  static errorText(raw: string, code: number): string {
    interface Issue { msg: string; }
    interface Failure { detail?: string | Issue[]; }
    try {
      const failure = JSON.parse(raw) as Failure;
      if (typeof failure.detail === 'string') { return failure.detail; }
      if (Array.isArray(failure.detail)) { return failure.detail.map((item: Issue) => item.msg).join('；'); }
      const message = JSON.parse(raw) as string;
      if (typeof message === 'string') { return message; }
    } catch (e) {}
    return `请求失败（${code}）`;
  }

  static async get(path: string): Promise<string> {
    return Api.request(path, http.RequestMethod.GET, undefined);
  }

  static async post(path: string, body?: object): Promise<string> {
    return Api.request(path, http.RequestMethod.POST,
      body === undefined ? undefined : JSON.stringify(body));
  }

  static async postLong(path: string, body: object): Promise<string> {
    return Api.request(path, http.RequestMethod.POST, JSON.stringify(body), 120000);
  }

  static async put(path: string, body: object): Promise<string> {
    return Api.request(path, http.RequestMethod.PUT, JSON.stringify(body));
  }

  static async remove(path: string): Promise<string> {
    return Api.request(path, http.RequestMethod.DELETE, undefined);
  }

  private static async request(path: string, method: http.RequestMethod,
    body: string | undefined, readTimeout: number = Api.TIMEOUT_MS): Promise<string> {
    const client: http.HttpRequest = http.createHttp();
    const generation: number = Api.generation;
    try {
      const options: http.HttpRequestOptions = {
        method: method,
        header: Api.headers('application/json'),
        connectTimeout: Api.TIMEOUT_MS,
        readTimeout: readTimeout,
        expectDataType: http.HttpDataType.STRING,
        extraData: body
      };
      const resp: http.HttpResponse = await client.request(Api.BASE_URL + path, options);
      Api.checkSession(resp.responseCode, generation);
      if (resp.responseCode >= 200 && resp.responseCode < 300) {
        return resp.result as string;
      }
      throw new Error(Api.errorText(resp.result as string, resp.responseCode));
    } finally {
      client.destroy();
    }
  }

  /** 音频分片 multipart 上传 */
  static async uploadChunk(sessionId: number, seq: number, data: ArrayBuffer): Promise<string> {
    return Api.upload(`/sessions/${sessionId}/chunks/${seq}`, `chunk_${seq}.pcm`, data, 120000);
  }

  static async upload(path: string, filename: string, data: ArrayBuffer, timeout: number = 300000): Promise<string> {
    const client: http.HttpRequest = http.createHttp();
    const generation: number = Api.generation;
    try {
      const form: http.MultiFormData = {
        name: 'file',
        contentType: 'application/octet-stream',
        remoteFileName: filename,
        data: data
      };
      const options: http.HttpRequestOptions = {
        method: http.RequestMethod.POST,
        header: Api.headers('multipart/form-data'),
        connectTimeout: Api.TIMEOUT_MS,
        readTimeout: timeout,
        expectDataType: http.HttpDataType.STRING,
        multiFormDataList: [form]
      };
      const resp: http.HttpResponse = await client.request(
        Api.BASE_URL + path, options);
      Api.checkSession(resp.responseCode, generation);
      if (resp.responseCode >= 200 && resp.responseCode < 300) {
        return resp.result as string;
      }
      throw new Error(Api.errorText(resp.result as string, resp.responseCode));
    } finally {
      client.destroy();
    }
  }

  /**
   * SSE 流式问答。服务端事件序列：sources → data*N → done。
   * 基于 requestInStream 增量接收，utf-8 流式解码防止多字节字符截断。
   */
  static streamAsk(chatSessionId: number, question: string, contextNote: string,
    cb: StreamCallbacks, mode: string = 'single'): () => void {
    const client: http.HttpRequest = http.createHttp();
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
    let buffer: string = '';
    let currentEvent: string = 'message';
    let finished: boolean = false;
    const generation: number = Api.generation;
    let responseCode: number = 0;
    let ended: boolean = false;

    const finish = (err: string | null): void => {
      if (finished) {
        return;
      }
      finished = true;
      if (generation !== Api.generation) { client.destroy(); return; }
      if (err !== null) {
        cb.onError(err);
      } else {
        cb.onDone();
      }
      client.destroy();
    };

    const handleBlock = (block: string): void => {
      if (finished || generation !== Api.generation) { return; }
      currentEvent = 'message';
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
      } else if (currentEvent === 'error') {
        try {
          finish(JSON.parse(data) as string);
        } catch (e) {
          finish(data);
        }
      } else if (currentEvent === 'warning') {
        try {
          cb.onWarning(JSON.parse(data) as string);
        } catch (e) {
          cb.onWarning(data);
        }
      } else if (currentEvent === 'agent') {
        if (cb.onAgent !== undefined) {
          try {
            cb.onAgent(JSON.parse(data) as AiAgentInfo);
          } catch (e) {
            // 无效角色事件忽略，后续 delta 仍可按普通助手消息展示
          }
        }
      } else if (currentEvent === 'agent_done') {
        if (cb.onAgentDone !== undefined) {
          try {
            cb.onAgentDone(JSON.parse(data) as string);
          } catch (e) {
            cb.onAgentDone(data);
          }
        }
      } else if (currentEvent === 'done') {
        if (cb.onMetadata !== undefined) { cb.onMetadata(data); }
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
      if (finished || generation !== Api.generation) { return; }
      buffer += decoder.decodeWithStream(new Uint8Array(chunk), { stream: true });
      buffer = buffer.replace(/\r\n/g, '\n');
      let idx: number = buffer.indexOf('\n\n');
      while (idx >= 0) {
        const block: string = buffer.substring(0, idx);
        buffer = buffer.substring(idx + 2);
        handleBlock(block);
        idx = buffer.indexOf('\n\n');
      }
    });
    client.on('dataEnd', () => {
      ended = true;
      if (responseCode !== 0) {
        finish(responseCode >= 400 ? Api.errorText(buffer, responseCode) : '响应流意外中断');
      }
    });

    interface AskBody {
      chat_session_id: number;
      question: string;
      context_note: string;
      mode: string;
    }

    const body: AskBody = {
      chat_session_id: chatSessionId,
      question: question,
      context_note: contextNote,
      mode: mode
    };
    const options: http.HttpRequestOptions = {
      method: http.RequestMethod.POST,
      header: Api.headers('application/json'),
      connectTimeout: Api.TIMEOUT_MS,
      readTimeout: 120000,
      extraData: JSON.stringify(body)
    };
    client.requestInStream(Api.BASE_URL + '/chat/ask', options)
      .then((code: number) => {
        responseCode = code;
        Api.checkSession(code, generation);
        if (ended && !finished) {
          finish(code >= 400 ? Api.errorText(buffer, code) : '响应流意外中断');
        }
      })
      .catch((err: Error) => {
        finish(err.message);
      });
    return (): void => { finished = true; client.destroy(); };
  }
}
