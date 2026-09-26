import { webSocket } from '@kit.NetworkKit';
import { BusinessError } from '@kit.BasicServicesKit';
import { Api } from './Api';
import { TranscriptSegment } from '../model/Models';

interface RecordingEvent {
  type: string;
  text?: string;
  message?: string;
  status?: number;
  segment?: TranscriptSegment;
}

/** A continuous SIS window. Only a durable committed event permits deleting PCM. */
export class RealtimeRecording {
  private socket: webSocket.WebSocket = webSocket.createWebSocket();
  private token: string = Api.token;
  private failed: string = '';
  private closed: boolean = false;
  private ready: boolean = false;
  private result: TranscriptSegment | null = null;
  private deadline: number = 0;
  private onPartial: (text: string) => void;

  constructor(onPartial: (text: string) => void) { this.onPartial = onPartial; }

  static async delay(ms: number): Promise<void> {
    return new Promise<void>((resolve) => { setTimeout(resolve, ms); });
  }

  private check(): void {
    if (this.token === '' || Api.token !== this.token) { throw new Error('登录状态已改变，录音缓存已保留'); }
    if (this.failed !== '') { throw new Error(this.failed); }
    if (this.closed && this.result === null) { throw new Error('实时连接已断开，录音缓存已保留'); }
  }

  async open(sessionId: number, seq: number): Promise<void> {
    this.socket.on('message', (err: BusinessError, raw: string | ArrayBuffer) => {
      if (Api.token !== this.token || this.closed) { return; }
      if (err) { this.failed = '接收实时识别结果失败'; return; }
      if (typeof raw !== 'string') { this.failed = '实时识别响应格式错误'; return; }
      try {
        const event = JSON.parse(raw) as RecordingEvent;
        if (event.type === 'ready') { this.ready = true; }
        else if (event.type === 'partial') { this.onPartial(event.text ?? ''); }
        else if (event.type === 'committed' && event.segment !== undefined) {
          this.result = event.segment;
        } else if (event.type === 'error') {
          this.failed = event.message ?? '实时识别失败';
        }
      } catch (e) { this.failed = '实时识别响应格式错误'; }
    });
    this.socket.on('error', () => { if (this.failed === '') { this.failed = '实时识别连接失败，请检查服务地址和网络'; } });
    this.socket.on('close', () => { this.closed = true; });
    this.check();
    const url = Api.BASE_URL.replace(/^http/, 'ws') + `/sessions/${sessionId}/realtime/${seq}`;
    const headers: Record<string, string> = { 'Authorization': `Bearer ${this.token}` };
    this.deadline = Date.now() + 30000;
    const connected = await Promise.race<boolean>([
      this.socket.connect(url, { header: headers }),
      new Promise<boolean>((resolve) => { setTimeout(() => { resolve(false); }, 30000); })
    ]);
    if (!connected) { throw new Error('实时识别连接超时'); }
    while (!this.ready && this.result === null) {
      this.check();
      if (Date.now() > this.deadline) { throw new Error('等待云端开始识别超时'); }
      await RealtimeRecording.delay(50);
    }
    this.check();
  }

  committed(): TranscriptSegment | null { this.check(); return this.result; }

  async send(data: ArrayBuffer): Promise<void> {
    this.check();
    if (!await this.socket.send(data)) { throw new Error('音频发送失败'); }
  }

  async finish(): Promise<TranscriptSegment> {
    this.check();
    if (this.result !== null) { return this.result; }
    if (!await this.socket.send(JSON.stringify({ type: 'stop' }))) { throw new Error('录音结束消息发送失败'); }
    const deadline = Date.now() + 35000;
    while (this.result === null) {
      this.check();
      if (Date.now() > deadline) { throw new Error('等待转写保存超时，录音缓存已保留'); }
      await RealtimeRecording.delay(50);
    }
    return this.result;
  }

  close(): void {
    this.closed = true;
    this.socket.close().catch(() => {});
  }
}
