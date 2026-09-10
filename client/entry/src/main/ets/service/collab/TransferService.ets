import { harmonyShare, systemShare } from '@kit.ShareKit';
import { common } from '@kit.AbilityKit';
import { fileUri } from '@kit.CoreFileKit';
import { promptAction } from '@kit.ArkUI';
import { deviceInfo } from '@kit.BasicServicesKit';
import { Api } from '../Api';
import { GlobalState } from '../GlobalState';

export interface TransferNote { title: string; kind: string; content: string; }
interface TransferEnvelope { format: string; note?: TransferNote; state?: string; }
interface ReceivedNoteRequest { class_course_id: number; owner_id: number; title: string; kind: string; content: string; }

class TransferService {
  onLog: (message: string) => void = () => {};
  private registered: boolean = false;
  private context: common.UIAbilityContext | null = null;
  private windowId: number = -1;
  private provider: (() => TransferNote | null) | null = null;

  configure(context: common.UIAbilityContext, windowId: number): void {
    this.context = context;
    this.windowId = windowId;
  }

  setNoteProvider(provider: (() => TransferNote | null) | null): void { this.provider = provider; }

  private onShare = (target: harmonyShare.SharableTarget): void => {
    if (!GlobalState.lanGrabEnabled || GlobalState.user === null) {
      target.reject(harmonyShare.SharableErrorCode.NO_CONTENT_ERROR).catch(() => {});
      return;
    }
    const note = this.provider === null ? null : this.provider();
    const state = AppStorage.get<string>('continueSnapshot') ?? '';
    if (note === null && state === '') {
      target.reject(harmonyShare.SharableErrorCode.NO_CONTENT_ERROR).catch(() => {});
      return;
    }
    const envelope: TransferEnvelope = note === null ? { format: 'zhiban/1', state: state } :
      { format: 'zhiban/1', note: note };
    const data = new systemShare.SharedData({ utd: 'general.plain-text',
      title: note === null ? '智伴学习进度' : note.title, content: JSON.stringify(envelope) });
    target.share(data).catch((error: Error) => { this.onLog(error.message); });
  };

  private onReceive = (target: harmonyShare.ReceivableTarget): void => {
    if (this.context === null || !GlobalState.lanGrabEnabled || GlobalState.user === null) {
      target.reject(harmonyShare.ReceivableErrorCode.NO_RECEIVABLE_ERROR).catch(() => {});
      return;
    }
    target.receive(fileUri.getUriFromPath(this.context.cacheDir), {
      onDataReceived: (data: systemShare.SharedData): void => { this.receive(data); }
    }).catch((error: Error) => { this.onLog(error.message); });
  };

  private async receive(data: systemShare.SharedData): Promise<void> {
    const courseId = GlobalState.courseId();
    const userId = GlobalState.userId();
    const token = Api.token;
    try {
      for (const record of data.getRecords()) {
        if (record.utd !== 'general.plain-text' || record.content === undefined || record.content.length > 2100000) { continue; }
        const envelope = JSON.parse(record.content) as TransferEnvelope;
        if (envelope.format !== 'zhiban/1') { continue; }
        if (envelope.note !== undefined) {
          const note = envelope.note;
          if (typeof note.title !== 'string' || typeof note.content !== 'string' ||
            (note.kind !== 'md' && note.kind !== 'handwriting') || courseId < 0) { throw new Error('请先进入目标课程'); }
          if (Api.token !== token || userId !== GlobalState.userId()) { return; }
          const body: ReceivedNoteRequest = { class_course_id: courseId, owner_id: userId,
            title: note.title.substring(0, 190) + '（隔空接收）', kind: note.kind, content: note.content };
          await Api.post('/notes', body);
          promptAction.showToast({ message: '已保存隔空接收的笔记' });
        } else if (typeof envelope.state === 'string') {
          AppStorage.setOrCreate<string>('continueRestoreState', envelope.state);
          AppStorage.setOrCreate<number>('continueRestoreTick', (AppStorage.get<number>('continueRestoreTick') ?? 0) + 1);
        }
      }
    } catch (e) { this.onLog((e as Error).message); promptAction.showToast({ message: (e as Error).message }); }
  }

  startSharing(): void {
    if (this.registered || this.context === null || this.windowId < 0 || !GlobalState.lanGrabEnabled) { return; }
    if (deviceInfo.sdkApiVersion < 20 || !canIUse('SystemCapability.Collaboration.HarmonyShare')) {
      this.onLog('当前设备不支持系统隔空传送'); return;
    }
    try {
      harmonyShare.on('gesturesShare', { windowId: this.windowId }, this.onShare);
      harmonyShare.on('dataReceive', { windowId: this.windowId,
        capabilities: [{ utd: 'general.plain-text', maxSupportedCount: 1 }] }, this.onReceive);
      this.registered = true;
      this.onLog('系统隔空传送已就绪');
    } catch (e) { this.stopSharing(); this.onLog('此系统版本暂不支持隔空传送'); }
  }

  stopSharing(): void {
    if (deviceInfo.sdkApiVersion < 20 || this.windowId < 0) { return; }
    try { harmonyShare.off('gesturesShare', { windowId: this.windowId }, this.onShare); } catch (e) {}
    try { harmonyShare.off('dataReceive', { windowId: this.windowId,
      capabilities: [{ utd: 'general.plain-text', maxSupportedCount: 1 }] }, this.onReceive); } catch (e) {}
    this.registered = false;
  }
}

export const transferService: TransferService = new TransferService();
