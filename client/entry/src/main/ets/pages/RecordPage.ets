import { TouchMotion } from '../common/TouchMotion';
import { audio } from '@kit.AudioKit';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { LearningTheme as AppTheme } from '../common/LearningTheme';
import { Outline, TranscriptSegment } from '../model/Models';
import { Api } from '../service/Api';
import { RecordingStore, RecordingDraft } from '../service/RecordingStore';
import { closeRecordingCapture } from '../service/RecordingCapture';
import { RealtimeRecording } from '../service/RealtimeRecording';
import { GlobalState } from '../service/GlobalState';
import { CrystalIcon } from '../common/components/CrystalIcon';
import { StudyMaterial } from '../common/StudyMaterial';

interface PendingChunk { seq: number; }

type RecordState = 'idle' | 'recording' | 'paused' | 'finished';

const CHUNK_INTERVAL_MS: number = 4000;
const RECORD_BG: string = '#00ECF4FC';
const RECORD_PANEL: string = '#FFFFFF';
const RECORD_SOFT: string = '#F2F7FE';
const RECORD_CYAN: string = '#12BFE8';
const RECORD_BLUE: string = '#155AA5';
const RECORD_VIOLET: string = '#7A63F3';
const RECORD_AMBER: string = '#FFB84D';
const RECORD_GLASS: string = 'rgba(255,255,255,0.90)';
const RECORD_BORDER: string = 'rgba(255,255,255,0.92)';

/**
 * 课堂录音（Notein 风）：左侧居中大计时 + 圆形录制按钮，右侧转写浮岛。
 * AudioCapturer 采集 → 分片上传 → 云端 ASR 转写实时回显；
 * 麦克风初始化失败明确报错，未上传分片保存到应用私有目录。
 */
@Component
export struct RecordPage {
  startOnAppear: boolean = false;
  onStartRequestConsumed: () => void = () => {};
  private startRequestHandled: boolean = false;
  @StorageLink('reduceMotion') reduceMotion: boolean = false;
  @StorageLink('crystalSoftMaterial') softMaterial: boolean = false;
  @StorageLink('classSubPage') classSubPage: string = 'record';
  @StorageLink('recordingActive') recordingActive: boolean = false;
  @State controlling: boolean = false;
  private uploadQueue: PendingChunk[] = [];
  private recordingStore: RecordingStore | null = null;
  private uploadPromise: Promise<void> | null = null;
  private realtime: boolean = false;
  private realtimeBytes: number = 0;
  private realtimeSocket: RealtimeRecording | null = null;
  private realtimeRetries: number = 0;
  private realtimeBlocked: boolean = false;
  private leaving: boolean = false;
  @State interimText: string = '';
  @State recordState: RecordState = 'idle';
  @State title: string = '';
  @State elapsedSec: number = 0;
  @State segments: TranscriptSegment[] = [];
  @State outlineData: Outline | null = null;
  @State outlineText: string = '';
  @State outlineDirty: boolean = false;
  @State generatingOutline: boolean = false;
  @State savingOutline: boolean = false;
  @State publishingOutline: boolean = false;
  @State simulated: boolean = false;
  @State compact: boolean = false;
  @State compactTab: string = 'transcript';
  @State uploadFailures: number = 0;
  @State waveFrame: number = 0;
  private sessionId: number = -1;
  private seq: number = 0;
  private capturer: audio.AudioCapturer | null = null;
  private pendingBuffers: ArrayBuffer[] = [];
  private chunkTimer: number = -1;
  private clockTimer: number = -1;
  private waveTimer: number = -1;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.leaving = false;
    try {
      const context = getContext(this) as common.UIAbilityContext;
      this.recordingStore = new RecordingStore(context.filesDir, Api.BASE_URL, GlobalState.userId(), GlobalState.courseId());
      const draft = this.recordingStore.load();
      if (draft !== null) {
        this.sessionId = draft.sessionId;
        this.title = draft.title;
        this.realtime = draft.realtime ?? false;
        const pending = this.recordingStore.pending();
        this.seq = Math.max(draft.nextSeq, pending.length > 0 ? pending[pending.length - 1] + 1 : 0);
        this.uploadQueue = pending.map((seq: number): PendingChunk => { return { seq: seq }; });
        this.recordState = 'paused';
        this.recordingActive = true;
        this.toast('已恢复未完成录音，点击结束继续保存');
      }
    } catch (e) { this.toast(`录音缓存不可用：${(e as Error).message}`); }
    if (this.title === '') {
      this.title = this.defaultTitle();
    }
    this.consumeStartRequest();
  }

  /** One user tap, consumed once. Never overwrite or auto-resume a recovered recording. */
  private consumeStartRequest(): void {
    if (!this.startOnAppear || this.startRequestHandled) { return; }
    this.startRequestHandled = true;
    this.onStartRequestConsumed();
    if (!GlobalState.isTeacher() || GlobalState.course === null || this.recordState !== 'idle') { return; }
    if (this.recordingStore === null) { return; }
    this.start();
  }

  aboutToDisappear(): void {
    this.stopTimers();
    this.releaseCapturer();
    if (this.recordState === 'recording' || this.recordState === 'paused') {
      try { this.cacheBuffers(); } catch (e) { this.toast((e as Error).message); }
    }
    this.leaving = true;
    this.realtimeSocket?.close();
    this.recordingActive = false;
  }

  private toast(msg: string): void {
    promptAction.showToast({ message: msg });
  }

  private backToClass(): void {
    if (this.recordState === 'recording' || this.recordState === 'paused') {
      this.toast('请先结束录音，再返回课堂');
      return;
    }
    this.classSubPage = 'list';
  }

  private defaultTitle(): string {
    const now: Date = new Date();
    return `${now.getMonth() + 1}月${now.getDate()}日课堂`;
  }

  private fmtDuration(): string {
    const m: number = Math.floor(this.elapsedSec / 60);
    const s: number = this.elapsedSec % 60;
    return `${m < 10 ? '0' : ''}${m}:${s < 10 ? '0' : ''}${s}`;
  }

  // ---------- 录音控制（与后端联动） ----------
  private async start(): Promise<void> {
    if (this.controlling || this.recordingActive) { return; }
    this.controlling = true;
    this.recordingActive = true;
    if (GlobalState.course === null) {
      this.toast('请先选择课程');
      this.controlling = false;
      this.recordingActive = false;
      return;
    }
    interface CreateBody {
      class_course_id: number;
      title: string;
      creator_id: number;
    }

    const body: CreateBody = {
      class_course_id: GlobalState.courseId(),
      title: this.title.trim() === '' ? '未命名课时' : this.title.trim(),
      creator_id: GlobalState.userId()
    };
    try {
      interface RecordingConfig { realtime: boolean; }
      const config = JSON.parse(await Api.get('/sessions/recording-config')) as RecordingConfig;
      this.realtime = config.realtime;
      interface SessionResp {
        id: number;
      }

      const resp: SessionResp = JSON.parse(await Api.post('/sessions', body)) as SessionResp;
      this.sessionId = resp.id;
      if (this.recordingStore === null) { throw new Error('录音缓存不可用'); }
      const draft: RecordingDraft = { sessionId: this.sessionId, title: this.title, nextSeq: 0, realtime: this.realtime };
      this.recordingStore.save(draft);
    } catch (e) {
      this.toast(`创建课时失败：${(e as Error).message}`);
      this.controlling = false;
      this.recordingActive = false;
      return;
    }

    try {
      await this.initCapturer();
      this.recordState = 'recording';
      this.startTimers();
    } catch (e) {
      this.releaseCapturer();
      try { await Api.remove(`/sessions/${this.sessionId}`); } catch (cleanup) {}
      try { this.recordingStore?.finish(); } catch (cleanup) {}
      this.sessionId = -1;
      this.recordingActive = false;
      this.toast((e as Error).message);
    } finally { this.controlling = false; }
  }

  private async initCapturer(): Promise<void> {
    try {
      const perms: Permissions[] = ['ohos.permission.MICROPHONE'];
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      const result = await atManager.requestPermissionsFromUser(ctx, perms);
      const granted: boolean = result.authResults.length > 0 && result.authResults[0] === 0;
      if (!granted) {
        throw new Error('未授予麦克风权限');
      }
      const options: audio.AudioCapturerOptions = {
        streamInfo: {
          samplingRate: audio.AudioSamplingRate.SAMPLE_RATE_16000,
          channels: audio.AudioChannel.CHANNEL_1,
          sampleFormat: audio.AudioSampleFormat.SAMPLE_FORMAT_S16LE,
          encodingType: audio.AudioEncodingType.ENCODING_TYPE_RAW
        },
        capturerInfo: {
          source: audio.SourceType.SOURCE_TYPE_MIC,
          capturerFlags: 0
        }
      };
      this.capturer = await audio.createAudioCapturer(options);
      this.capturer.on('readData', (buf: ArrayBuffer) => {
        this.pendingBuffers.push(buf.slice(0));
      });
      await this.capturer.start();
      this.simulated = false;
    } catch (e) {
      this.releaseCapturer();
      throw new Error(`麦克风初始化失败：${(e as Error).message}`);
    }
  }

  private startTimers(): void {
    this.clockTimer = setInterval(() => {
      this.elapsedSec += 1;
    }, 1000);
    this.chunkTimer = setInterval(() => {
      this.flushChunk();
    }, this.realtime ? 200 : CHUNK_INTERVAL_MS);
    this.startWaveMotion();
  }

  private stopTimers(): void {
    if (this.clockTimer >= 0) {
      clearInterval(this.clockTimer);
      this.clockTimer = -1;
    }
    if (this.chunkTimer >= 0) {
      clearInterval(this.chunkTimer);
      this.chunkTimer = -1;
    }
    this.stopWaveMotion();
  }

  private startWaveMotion(): void {
    if (this.waveTimer >= 0) {
      return;
    }
    this.waveTimer = setInterval(() => {
      this.waveFrame = (this.waveFrame + 1) % 12;
    }, 160);
  }

  private stopWaveMotion(): void {
    if (this.waveTimer >= 0) {
      clearInterval(this.waveTimer);
      this.waveTimer = -1;
    }
    this.waveFrame = 0;
  }

  private releaseCapturer(): void {
    if (this.capturer !== null) {
      const c: audio.AudioCapturer = this.capturer;
      this.capturer = null;
      c.release().catch(() => {});
    }
  }

  private mergeBuffers(): ArrayBuffer {
    const list: ArrayBuffer[] = this.pendingBuffers;
    this.pendingBuffers = [];
    let total: number = 0;
    for (const b of list) {
      total += b.byteLength;
    }
    if (total === 0) {
      return new ArrayBuffer(0);
    }
    const out: Uint8Array = new Uint8Array(total);
    let offset: number = 0;
    for (const b of list) {
      out.set(new Uint8Array(b), offset);
      offset += b.byteLength;
    }
    return out.buffer;
  }

  private cacheBuffers(): void {
    if (this.sessionId < 0) { return; }
    if (this.recordingStore === null) { throw new Error('录音缓存不可用'); }
    if (this.realtime) { this.cacheRealtimeBuffers(); return; }
    const data = this.mergeBuffers();
    const maxBytes: number = 128000;
    for (let offset = 0; offset < data.byteLength; offset += maxBytes) {
      try {
        this.recordingStore.append(this.seq, data.slice(offset, Math.min(offset + maxBytes, data.byteLength)));
        this.uploadQueue.push({ seq: this.seq++ });
      } catch (e) { this.pendingBuffers.unshift(data.slice(offset)); throw new Error((e as Error).message); }
    }
    const draft: RecordingDraft = { sessionId: this.sessionId, title: this.title, nextSeq: this.seq };
    this.recordingStore.save(draft);
  }

  private async flushChunk(requireSave: boolean = false): Promise<void> {
    try {
      this.cacheBuffers();
      if (this.realtime && requireSave && this.realtimeBytes > 0) {
        this.seq++;
        this.realtimeBytes = 0;
      }
      if (this.realtime && requireSave) { this.realtimeBlocked = false; this.realtimeRetries = 0; }
    }
    catch (e) {
      if (requireSave) { throw new Error('录音缓存保存失败，请再次点击结束重试'); }
      this.toast(`录音缓存保存失败：${(e as Error).message}`);
      return;
    }
    if (this.uploadPromise !== null) { return this.uploadPromise; }
    this.uploadPromise = this.realtime ? this.drainRealtime() : this.drainUploads();
    try { await this.uploadPromise; }
    finally { this.uploadPromise = null; }
  }

  private cacheRealtimeBuffers(): void {
    if (this.recordingStore === null) { throw new Error('录音缓存不可用'); }
    const data = this.mergeBuffers();
    let offset = 0;
    while (offset < data.byteLength) {
      const take = Math.min(1920000 - this.realtimeBytes, data.byteLength - offset);
      try {
        this.recordingStore.appendRealtime(this.seq, data.slice(offset, offset + take));
        if (this.realtimeBytes === 0) { this.uploadQueue.push({ seq: this.seq }); }
        this.realtimeBytes += take;
        offset += take;
        if (this.realtimeBytes === 1920000) { this.seq++; this.realtimeBytes = 0; }
      } catch (e) { this.pendingBuffers.unshift(data.slice(offset)); throw new Error((e as Error).message); }
    }
    const draft: RecordingDraft = { sessionId: this.sessionId, title: this.title,
      nextSeq: this.seq + (this.realtimeBytes > 0 ? 1 : 0), realtime: true };
    this.recordingStore.save(draft);
  }

  private async drainRealtime(): Promise<void> {
    while (this.uploadQueue.length > 0 && !this.leaving && !this.realtimeBlocked) {
      const chunk = this.uploadQueue[0];
      const stream = new RealtimeRecording((text: string) => { this.interimText = text; });
      this.realtimeSocket = stream;
      try {
        await stream.open(this.sessionId, chunk.seq);
        let sent = 0;
        let committed = stream.committed();
        while (committed === null && !this.leaving) {
          if (this.recordingStore === null) { throw new Error('录音缓存不可用'); }
          const data = this.recordingStore.readFrame(chunk.seq, sent);
          if (data.byteLength > 0) {
            await stream.send(data);
            sent += data.byteLength;
            // At most twice realtime when replaying cached audio; 200 ms frames when live.
            await RealtimeRecording.delay(100);
          } else if (chunk.seq < this.seq) {
            committed = await stream.finish();
          } else {
            stream.committed(); // Detect a connection that failed while waiting for microphone data.
            await RealtimeRecording.delay(50);
          }
        }
        if (committed === null || this.leaving) { return; }
        const saved: TranscriptSegment = committed;
        this.segments = this.segments.filter((segment: TranscriptSegment) => segment.seq !== saved.seq).concat([saved]);
        this.interimText = '';
        this.recordingStore?.remove(chunk.seq);
        this.uploadQueue.shift();
        this.uploadFailures = 0;
        this.realtimeRetries = 0;
      } catch (e) {
        this.interimText = '';
        this.uploadFailures = this.uploadQueue.length;
        if (this.leaving) { return; }
        if (++this.realtimeRetries > 3 || Api.token === '') {
          this.realtimeBlocked = true;
          this.toast(`实时识别失败，录音已保留，暂停或结束可重试：${(e as Error).message}`);
          return;
        }
        stream.close();
        await RealtimeRecording.delay(1000 * this.realtimeRetries);
      } finally {
        stream.close();
        if (this.realtimeSocket === stream) { this.realtimeSocket = null; }
      }
    }
  }

  private async drainUploads(): Promise<void> {
    const token = Api.token;
    while (this.uploadQueue.length > 0) {
      if (Api.token !== token || token === '') { return; }
      const chunk = this.uploadQueue[0];
      try {
        if (this.recordingStore === null) { throw new Error('录音缓存不可用'); }
        const segment = JSON.parse(await Api.uploadChunk(this.sessionId, chunk.seq, this.recordingStore.read(chunk.seq))) as TranscriptSegment;
        this.recordingStore.remove(chunk.seq);
        this.uploadQueue.shift();
        this.segments = this.segments.concat([segment]);
        this.uploadFailures = 0;
      } catch (e) {
        this.uploadFailures = this.uploadQueue.length;
        this.toast(`分片上传失败，已保留待重试：${(e as Error).message}`);
        return;
      }
    }
  }

  private async stopCapture(): Promise<void> {
    this.stopTimers();
    if (this.capturer !== null) {
      try {
        await closeRecordingCapture(this.capturer, this.recordState === 'recording');
      } catch (e) {
        // Keep caching if release also fails, so retrying cannot discard incoming audio.
        if (this.recordState === 'recording') { this.startTimers(); }
        throw new Error((e as Error).message);
      }
      this.capturer = null;
    }
    this.recordState = 'paused';
  }

  private async pauseOrResume(): Promise<void> {
    if (this.controlling) { return; }
    this.controlling = true;
    try {
      if (this.recordState === 'recording') {
        await this.stopCapture();
        await this.flushChunk(true);
      } else if (this.recordState === 'paused') {
        await this.initCapturer();
        this.recordState = 'recording';
        this.startTimers();
      }
    } catch (e) { this.toast((e as Error).message); }
    finally { this.controlling = false; }
  }

  private async finish(): Promise<void> {
    if (this.controlling || this.sessionId < 0 || this.recordState === 'finished') { return; }
    this.controlling = true;
    try {
      await this.stopCapture();
      await this.flushChunk(true);
      if (this.uploadQueue.length > 0 || this.pendingBuffers.length > 0) { throw new Error('仍有未上传的分片，请再次点击结束以重试'); }
      await Api.post(`/sessions/${this.sessionId}/finish`);
      this.recordState = 'finished';
      this.recordingActive = false;
      GlobalState.currentSessionId = this.sessionId;
      try { this.recordingStore?.finish(); }
      catch (e) { this.toast('录音已保存，设备缓存暂未清理'); }
      try {
        this.segments = JSON.parse(await Api.get(`/sessions/${this.sessionId}/transcript`)) as TranscriptSegment[];
      } catch (e) { this.toast('录音已保存，转写列表暂未刷新'); }
      this.toast('录音及转写已保存');
    } catch (e) { this.toast(`录音尚未保存完成：${(e as Error).message}`); }
    finally { this.controlling = false; }
  }

  private prepareNextRecording(): void {
    if (this.recordingActive || this.controlling) { return; }
    this.stopTimers();
    this.releaseCapturer();
    this.recordState = 'idle';
    this.title = this.defaultTitle();
    this.elapsedSec = 0;
    this.segments = [];
    this.outlineData = null;
    this.outlineText = '';
    this.outlineDirty = false;
    this.generatingOutline = false;
    this.savingOutline = false;
    this.publishingOutline = false;
    this.simulated = false;
    this.uploadFailures = 0;
    this.sessionId = -1;
    this.seq = 0;
    this.pendingBuffers = [];
    this.uploadQueue = [];
    this.uploadPromise = null;
    this.realtimeBytes = 0;
    this.realtimeBlocked = false;
    this.realtimeRetries = 0;
    this.interimText = '';
  }

  private async generateOutline(): Promise<void> {
    if (this.sessionId < 0 || this.segments.length === 0) {
      this.toast('请先完成有转写文本的录音');
      return;
    }
    this.generatingOutline = true;
    try {
      this.outlineData = JSON.parse(await Api.post(
        `/sessions/${this.sessionId}/outline/generate?user_id=${GlobalState.userId()}`)) as Outline;
      this.outlineText = this.outlineData.markdown;
      this.outlineDirty = true;
      this.toast('提纲已生成，请校准后保存');
    } catch (e) {
      this.toast(`生成失败：${(e as Error).message}`);
    } finally {
      this.generatingOutline = false;
    }
  }

  private async saveOutline(): Promise<boolean> {
    if (this.sessionId < 0 || this.outlineText.trim() === '') {
      this.toast('暂无可保存的提纲');
      return false;
    }
    interface OutlineUpdate {
      markdown: string;
    }

    const body: OutlineUpdate = { markdown: this.outlineText };
    this.savingOutline = true;
    try {
      this.outlineData = JSON.parse(await Api.put(
        `/sessions/${this.sessionId}/outline?user_id=${GlobalState.userId()}`, body)) as Outline;
      this.outlineText = this.outlineData.markdown;
      this.outlineDirty = false;
      this.toast(GlobalState.canManageCurrentCourse() ? '官方草稿已保存' : '已保存到我的课堂');
      return true;
    } catch (e) {
      this.toast(`保存失败：${(e as Error).message}`);
      return false;
    } finally {
      this.savingOutline = false;
    }
  }

  private async publishOutline(): Promise<void> {
    if (this.sessionId < 0 || this.outlineText.trim() === '') {
      this.toast('暂无可发布的提纲');
      return;
    }
    if (this.outlineDirty) {
      const saved: boolean = await this.saveOutline();
      if (!saved) {
        return;
      }
    }
    interface ReviewBody {
      user_id: number;
      action: string;
    }

    const body: ReviewBody = { user_id: GlobalState.userId(), action: 'publish' };
    this.publishingOutline = true;
    try {
      this.outlineData = JSON.parse(
        await Api.post(`/sessions/${this.sessionId}/outline/review`, body)) as Outline;
      this.outlineText = this.outlineData.markdown;
      this.outlineDirty = false;
      this.toast('已发布，班级可见并写入课程知识库');
    } catch (e) {
      this.toast(`发布失败：${(e as Error).message}`);
    } finally {
      this.publishingOutline = false;
    }
  }

  // ---------- UI ----------
  @Builder
  recordAtmosphere() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 34,
          colors: [
            ['#F8FCFA', 0],
            [RECORD_BG, 0.54],
            ['#EEF3FF', 1]
          ]
        })
      Column()
        .width(560)
        .height(560)
        .borderRadius(72)
        .rotate({ angle: -18 })
        .backgroundColor('rgba(21,90,165,0.11)')
        .position({ x: -190, y: -120 })
      Column()
        .width(620)
        .height(360)
        .borderRadius(60)
        .rotate({ angle: 12 })
        .backgroundColor('rgba(63,125,255,0.08)')
        .position({ x: 980, y: 310 })
      Column()
        .width('100%')
        .height(1)
        .backgroundColor('rgba(255,255,255,0.72)')
        .position({ x: 0, y: 238 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  statusPill() {
    Row({ space: 8 }) {
      Column()
        .width(8)
        .height(8)
        .borderRadius(4)
        .backgroundColor(this.recordState === 'recording' ? AppTheme.PRIMARY :
          (this.recordState === 'paused' ? RECORD_AMBER : RECORD_BLUE))
      Text(this.recordState === 'idle' ? '待开始' :
        (this.recordState === 'paused' ? '暂停中' :
          (this.recordState === 'finished' ? '已完成' : '录音中')))
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(AppTheme.TEXT_SECONDARY)
    }
    .height(34)
    .padding({ left: 13, right: 13 })
    .borderRadius(999)
    .backgroundColor('rgba(18,24,24,0.06)')
    .border({ width: 1, color: 'rgba(18,24,24,0.08)' })
  }

  @Builder
  waveBar(base: number, index: number) {
    Column()
      .width(this.recordState === 'recording' ? 6 : 5)
      .height(this.waveHeight(base, index))
      .borderRadius(999)
      .linearGradient({
        angle: 180,
        colors: [
          [this.waveColor(index), 0],
          ['rgba(255,255,255,0.86)', 1]
        ]
      })
      .opacity(this.waveOpacity(index))
      .margin({ left: 4, right: 4 })
      .shadow({
        radius: this.recordState === 'recording' ? 12 : 0,
        color: this.waveColor(index),
        offsetX: 0,
        offsetY: 4
      })
      .animation({ duration: 150, curve: Curve.EaseOut })
  }

  private waveHeight(base: number, index: number): number {
    if (this.recordState === 'paused') {
      return 14;
    }
    if (this.recordState !== 'recording') {
      return 9;
    }
    const phase: number = (this.waveFrame + index) % 8;
    let boost: number = 2;
    if (phase === 0) {
      boost = 20;
    } else if (phase === 1) {
      boost = 12;
    } else if (phase === 2) {
      boost = 4;
    } else if (phase === 3) {
      boost = -8;
    } else if (phase === 4) {
      boost = 16;
    } else if (phase === 5) {
      boost = 7;
    } else if (phase === 6) {
      boost = -4;
    }
    const value: number = base + boost;
    if (value < 12) {
      return 12;
    }
    if (value > 68) {
      return 68;
    }
    return value;
  }

  private waveOpacity(index: number): number {
    if (this.recordState !== 'recording') {
      return 0.34;
    }
    const phase: number = (this.waveFrame + index) % 6;
    return phase === 0 || phase === 1 ? 1 : (phase === 2 || phase === 5 ? 0.78 : 0.58);
  }

  private waveColor(index: number): string {
    if (this.recordState !== 'recording') {
      return 'rgba(18,24,24,0.22)';
    }
    const phase: number = (this.waveFrame + index) % 4;
    if (phase === 0) {
      return AppTheme.PRIMARY;
    }
    if (phase === 1) {
      return RECORD_CYAN;
    }
    if (phase === 2) {
      return RECORD_BLUE;
    }
    return RECORD_VIOLET;
  }

  @Builder
  waveform() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width(340)
        .height(94)
        .borderRadius(47)
        .backgroundColor(this.recordState === 'recording' ? 'rgba(21,90,165,0.08)' : 'rgba(18,24,24,0.04)')
        .border({
          width: 1.2,
          color: this.recordState === 'recording' ? 'rgba(21,90,165,0.18)' : 'rgba(18,24,24,0.06)'
        })
      Column()
        .width(this.recordState === 'recording' ? 286 : 210)
        .height(2)
        .borderRadius(1)
        .backgroundColor(this.recordState === 'recording' ? 'rgba(18,191,232,0.28)' : 'rgba(18,24,24,0.10)')
        .animation({ duration: 180, curve: Curve.EaseOut })
      Row() {
        this.waveBar(18, 0)
        this.waveBar(34, 1)
        this.waveBar(48, 2)
        this.waveBar(28, 3)
        this.waveBar(58, 4)
        this.waveBar(40, 5)
        this.waveBar(22, 6)
        this.waveBar(52, 7)
        this.waveBar(64, 8)
        this.waveBar(42, 9)
        this.waveBar(26, 10)
        this.waveBar(56, 11)
        this.waveBar(36, 12)
        this.waveBar(50, 13)
        this.waveBar(30, 14)
        this.waveBar(44, 15)
      }
      .height(82)
      .alignItems(VerticalAlign.Center)
    }
    .width(360)
    .height(104)
  }

  /** Native, cancellable press feedback; recording actions retain their controller guards. */
  @Builder
  circleButton(label: string, size: number, bg: string, fg: string, onTap: () => void) {
    Button({ type: ButtonType.Normal }) {
      if (label === '■') {
        Column().width(size * 0.3).height(size * 0.3).borderRadius(4).backgroundColor(fg)
      } else {
        SymbolGlyph(label === '🎙' ? $r('sys.symbol.mic') : label === '⏸' ? $r('sys.symbol.pause') :
          label === '▶' ? $r('sys.symbol.play') : $r('sys.symbol.plus'))
          .fontSize(size * 0.36).fontColor([fg])
      }
    }
      .width(size)
      .height(size)
      .borderRadius(size * 0.34)
      .backgroundColor(bg)
      .border({ width: 1, color: '#8FFFFFFF' })
      .shadow({ radius: 14, color: '#28436F9D', offsetX: 0, offsetY: 5 })
      .visualEffect(StudyMaterial.light(this.softMaterial, true)).enabled(!this.controlling)
      .stateStyles({
        normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
        pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'icon'))
          .translate(TouchMotion.pressedOffset(this.reduceMotion, 'icon')).animation(TouchMotion.press(this.reduceMotion)) },
        disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
      })
      .accessibilityText(label === '🎙' ? '开始课堂录音' : label === '⏸' ? '暂停录音' :
        label === '▶' ? '继续录音' : label === '■' ? '结束录音' : '准备新的课堂录音')
      .onClick(() => {
        onTap();
      })
  }

  @Builder
  backButton() {
    Row({ space: AppTheme.SPACE_S }) {
      Text('‹')
        .fontSize(28)
        .fontColor(AppTheme.INK)
        .width(34)
        .height(34)
        .textAlign(TextAlign.Center)
        .borderRadius(17)
        .backgroundColor(AppTheme.BG_SUNKEN)
      Text('返回课堂')
        .fontSize(AppTheme.FONT_BODY)
        .fontWeight(FontWeight.Medium)
        .fontColor(AppTheme.INK)
    }
    .height(44)
    .padding({ left: 8, right: 16 })
    .borderRadius(22)
    .backgroundColor(AppTheme.BG_CARD)
    .border({ width: 1, color: AppTheme.DIVIDER })
    .shadow({ radius: 14, color: 'rgba(17,17,17,0.05)', offsetX: 0, offsetY: 4 })
    .onClick(() => {
      this.backToClass();
    })
  }

  @Builder
  outlinePanel() {
    Column({ space: AppTheme.SPACE_M }) {
      Row({ space: AppTheme.SPACE_S }) {
        Text('AI 提纲')
          .fontSize(AppTheme.FONT_SUBTITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.INK)
        if (this.outlineData !== null && this.outlineData.status === 'published') {
          Text('官方发布')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor('#FFFFFF')
            .padding({ left: 10, right: 10, top: 3, bottom: 3 })
            .borderRadius(999)
            .backgroundColor(AppTheme.SUCCESS)
        } else if (this.outlineDirty) {
          Text('待保存')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.WARNING)
            .padding({ left: 10, right: 10, top: 3, bottom: 3 })
            .borderRadius(999)
            .backgroundColor(AppTheme.tagBg(AppTheme.WARNING))
        }
        Blank()
      }
      .width('100%')

      TextArea({ text: this.outlineText, placeholder: '录音结束后点击「生成提纲」，校准后保存。' })
      .layoutWeight(1)
      .width('100%')
      .fontSize(AppTheme.FONT_BODY)
      .backgroundColor('rgba(255,255,255,0.76)')
      .borderRadius(22)
      .enabled(this.outlineData !== null && this.outlineData.status !== 'published')
      .onChange((v: string) => {
        this.outlineText = v;
          this.outlineDirty = true;
        })

      Row({ space: AppTheme.SPACE_M }) {
        Button(this.generatingOutline ? '生成中…' : '生成提纲').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          })
          .layoutWeight(1)
          .enabled(!this.generatingOutline && this.segments.length > 0)
          .backgroundColor(AppTheme.PRIMARY)
          .borderRadius(999)
          .onClick(() => {
            this.generateOutline();
          })
        Button(this.savingOutline ? '保存中…' : '保存').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          })
          .layoutWeight(1)
          .enabled(!this.savingOutline && this.outlineText.trim() !== '' &&
            (this.outlineData === null || this.outlineData.status !== 'published'))
          .backgroundColor(AppTheme.BG_CARD)
          .fontColor(AppTheme.TEXT_SECONDARY)
          .borderRadius(AppTheme.RADIUS_BTN)
          .onClick(() => {
            this.saveOutline();
          })
        if (GlobalState.canManageCurrentCourse()) {
          Button(this.publishingOutline ? '发布中…' : '发布').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          })
            .layoutWeight(1)
            .enabled(!this.publishingOutline && this.outlineText.trim() !== '' &&
              (this.outlineData === null || this.outlineData.status !== 'published'))
            .backgroundColor(AppTheme.SUCCESS)
            .borderRadius(999)
            .onClick(() => {
              this.publishOutline();
            })
        }
      }
      .width('100%')
    }
    .layoutWeight(1)
    .width('100%')
    .padding(AppTheme.SPACE_L)
    .borderRadius(26)
    .backgroundColor('rgba(255,255,255,0.68)')
    .border({ width: 1.2, color: RECORD_BORDER })
  }

  @Builder
  compactWorkspace() {
    Column({ space: 16 }) {
      Row() {
        this.backButton()
        Blank()
        this.statusPill()
      }.width('100%')
      Row({ space: 12 }) {
        CrystalIcon({ icon: $r('sys.symbol.mic'), edge: 40 })
        Column({ space: 4 }) {
          Text('课堂录音').fontSize(24).fontWeight(FontWeight.Bold).fontColor(AppTheme.INK)
          Text('记录课堂内容，整理课程提纲').fontSize(12).fontColor(AppTheme.TEXT_SECONDARY)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      }.width('100%')
      TextInput({ text: this.title, placeholder: '课时标题' }).enabled(this.recordState === 'idle')
        .height(48).borderRadius(16).backgroundColor(AppTheme.BG_CARD).fontColor(AppTheme.INK)
        .onChange((value: string) => { this.title = value; })
      Row({ space: 16 }) {
        Text(this.fmtDuration()).fontSize(28).fontWeight(FontWeight.Bold).fontColor(AppTheme.INK).layoutWeight(1)
        if (this.recordState === 'idle') {
          Button('开始录音').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).backgroundColor(AppTheme.PRIMARY).enabled(!this.controlling).onClick(() => { this.start(); })
        } else if (this.recordState === 'recording' || this.recordState === 'paused') {
          Button(this.recordState === 'recording' ? '暂停' : '继续').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).enabled(!this.controlling).onClick(() => { this.pauseOrResume(); })
          Button('结束').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).backgroundColor(AppTheme.DANGER).enabled(!this.controlling).onClick(() => { this.finish(); })
        } else {
          Button('新录音').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).backgroundColor(AppTheme.PRIMARY).onClick(() => { this.prepareNextRecording(); })
        }
      }.width('100%')
      if (this.uploadFailures > 0) { Text(`${this.uploadFailures} 个分片待上传`).fontColor(AppTheme.DANGER).fontSize(13) }
      Row({ space: 8 }) {
        Button('转写').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).layoutWeight(1).backgroundColor(this.compactTab === 'transcript' ? AppTheme.PRIMARY : AppTheme.PRIMARY_LIGHT)
          .fontColor(this.compactTab === 'transcript' ? '#FFFFFF' : AppTheme.PRIMARY)
          .onClick(() => { this.compactTab = 'transcript'; })
        if (this.recordState === 'finished') {
          Button('提纲').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).layoutWeight(1).backgroundColor(this.compactTab === 'outline' ? AppTheme.PRIMARY : AppTheme.PRIMARY_LIGHT)
            .fontColor(this.compactTab === 'outline' ? '#FFFFFF' : AppTheme.PRIMARY)
            .onClick(() => { this.compactTab = 'outline'; })
        }
      }.width('100%')
      if (this.compactTab === 'outline' && this.recordState === 'finished') {
        this.outlinePanel()
      } else {
        List({ space: 12 }) {
          if (this.segments.length === 0 && this.interimText === '') {
            ListItem() {
              Column({ space: 12 }) {
                SymbolGlyph($r('sys.symbol.waveform')).fontSize(32).fontColor([AppTheme.PRIMARY])
                Text(this.recordState === 'idle' ? '准备好后，开始记录这一堂课' : '正在等待课堂转写')
                  .fontSize(16).fontColor(AppTheme.INK).textAlign(TextAlign.Center)
                Text('语音转写会按时间顺序显示在这里').fontSize(13).fontColor(AppTheme.TEXT_SECONDARY)
              }.padding(28).width('100%').borderRadius(24).backgroundColor(AppTheme.BG_CARD)
            }
          }
          ForEach(this.segments, (segment: TranscriptSegment) => {
            ListItem() { Text(segment.text).width('100%').fontSize(15).lineHeight(25).fontColor(AppTheme.INK)
              .padding(20).borderRadius(20).backgroundColor(AppTheme.BG_CARD) }
          }, (segment: TranscriptSegment) => `${segment.seq}`)
          if (this.interimText !== '') {
            ListItem() {
              Column({ space: 6 }) {
                Text('正在识别…').fontSize(12).fontColor(AppTheme.PRIMARY)
                Text(this.interimText).fontSize(15).lineHeight(25).fontColor(AppTheme.INK)
              }.width('100%').alignItems(HorizontalAlign.Start).padding(20)
                .borderRadius(20).backgroundColor(AppTheme.BG_CARD)
            }
          }
        }.width('100%').layoutWeight(1)
      }
    }.width('100%').height('100%').padding(16).backgroundColor(RECORD_BG)
  }

  build() {
    Stack() {
      if (this.compact) { this.compactWorkspace() } else {

      Column({ space: AppTheme.SPACE_L }) {
        Row() {
          this.backButton()
          Blank()
          Row({ space: 8 }) {
            Text('课堂记录')
              .fontSize(11)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.PRIMARY)
              .padding({ left: 12, right: 12, top: 5, bottom: 5 })
              .borderRadius(999)
              .backgroundColor(AppTheme.PRIMARY_LIGHT)
            Text('课堂录音')
              .fontSize(11)
              .fontColor(AppTheme.TEXT_SECONDARY)
              .padding({ left: 12, right: 12, top: 5, bottom: 5 })
              .borderRadius(999)
              .backgroundColor(RECORD_GLASS)
          }
        }
        .width('100%')
        .height(44)

        Row({ space: AppTheme.SPACE_XL }) {
          // 左：录音控制台
          Stack({ alignContent: Alignment.TopStart }) {
            Column()
              .width('100%')
              .height('100%')
              .borderRadius(34)
              .linearGradient({
                angle: 128,
                colors: [
                  [RECORD_PANEL, 0],
                  [RECORD_SOFT, 0.58],
                  ['#EEF3FF', 1]
                ]
              })
            Row() {
              Text('录音仪表盘')
                .fontSize(AppTheme.FONT_BODY)
                .fontWeight(FontWeight.Medium)
                .fontColor(AppTheme.INK)
              Blank()
              this.statusPill()
            }
            .width('100%')
            .padding({ left: 24, right: 24, top: 22 })

            Column({ space: AppTheme.SPACE_XL }) {
              Blank().layoutWeight(1)

        TextInput({ text: this.title, placeholder: '本次课时标题' })
          .fontSize(AppTheme.FONT_SUBTITLE)
          .textAlign(TextAlign.Center)
          .backgroundColor('transparent')
          .fontColor(AppTheme.INK)
          .placeholderColor(AppTheme.TEXT_TERTIARY)
          .enabled(this.recordState === 'idle')
          .onChange((v: string) => {
            this.title = v;
          })

        Text(this.fmtDuration())
          .fontSize(64)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.recordState === 'recording' ? AppTheme.INK : AppTheme.TEXT_TERTIARY)

        this.waveform()

        // 主控按钮
        Row({ space: AppTheme.SPACE_XL }) {
          if (this.recordState === 'idle') {
            this.circleButton('🎙', 84, AppTheme.PRIMARY, '#FFFFFF', (): void => {
              this.start();
            })
          } else if (this.recordState === 'recording' || this.recordState === 'paused') {
            this.circleButton(this.recordState === 'recording' ? '⏸' : '▶', 60,
              AppTheme.BG_CARD, AppTheme.INK, (): void => {
                this.pauseOrResume();
              })
            this.circleButton('■', 84, AppTheme.DANGER, '#FFFFFF', (): void => {
              this.finish();
            })
          } else {
            this.circleButton('＋', 84, AppTheme.PRIMARY, '#FFFFFF', (): void => {
              this.prepareNextRecording();
            })
          }
        }

        Text(this.recordState === 'idle' ? '点击开始录音' :
          (this.recordState === 'paused' ? '已暂停' :
            (this.recordState === 'finished' ? '录音已结束，可生成提纲或继续录音' : '录音中')))
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.TEXT_SECONDARY)

        if (this.simulated && this.recordState !== 'idle') {
          Text('模拟模式：无真实音频，定时上传占位分片')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.WARNING)
            .padding({ left: 12, right: 12, top: 4, bottom: 4 })
            .borderRadius(999)
            .backgroundColor(AppTheme.tagBg(AppTheme.WARNING))
        }
        if (this.uploadFailures > 0) {
          Text(`${this.uploadFailures} 个分片上传失败`)
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.DANGER)
        }
              Blank().layoutWeight(1)
            }
            .width('100%')
            .height('100%')
            .padding({ left: 22, right: 22, top: 76, bottom: 22 })
            .alignItems(HorizontalAlign.Center)
          }
          .width(420)
          .height('100%')
          .clip(true)
          .borderRadius(34)
          .border({ width: 1.2, color: RECORD_BORDER })
          .shadow({ radius: 30, color: 'rgba(31,62,68,0.12)', offsetX: 0, offsetY: 14 })

      // 右：实时转写浮岛
      Column({ space: AppTheme.SPACE_M }) {
        Row() {
          Column({ space: 4 }) {
            Text('实时转写')
              .fontSize(AppTheme.FONT_SUBTITLE)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.INK)
            Text(`${this.segments.length} 条分片 · ${this.uploadFailures} 个上传失败`)
              .fontSize(AppTheme.FONT_CAPTION)
              .fontColor(AppTheme.TEXT_TERTIARY)
          }
          .alignItems(HorizontalAlign.Start)
          Blank()
          Text(this.simulated ? '模拟模式' : '语音识别')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(this.simulated ? AppTheme.WARNING : AppTheme.PRIMARY)
            .padding({ left: 12, right: 12, top: 5, bottom: 5 })
            .borderRadius(999)
            .backgroundColor(AppTheme.tagBg(this.simulated ? AppTheme.WARNING : AppTheme.PRIMARY))
        }
        .width('100%')

        Column() {
          if (this.segments.length === 0 && this.interimText === '') {
            Column({ space: AppTheme.SPACE_M }) {
              CrystalIcon({ icon: $r('sys.symbol.waveform'), edge: 72 })
              Text(this.recordState === 'idle' ?
                '开始录音后，转写文字将在此显示' : '等待首个分片转写…')
                .fontSize(AppTheme.FONT_BODY)
                .fontColor(AppTheme.TEXT_TERTIARY)
            }
            .width('100%')
            .height('100%')
            .justifyContent(FlexAlign.Center)
          } else {
            List({ space: AppTheme.SPACE_L, scroller: this.scroller }) {
              ForEach(this.segments, (seg: TranscriptSegment) => {
                ListItem() {
                  Column({ space: AppTheme.SPACE_XS }) {
                    Text(`${Math.floor(seg.start_ms / 60000)}:${
                      ((seg.start_ms % 60000) / 1000).toFixed(0).padStart(2, '0')}`)
                      .fontSize(AppTheme.FONT_CAPTION)
                      .fontColor(AppTheme.PRIMARY)
                    Text(seg.text)
                      .fontSize(AppTheme.FONT_BODY)
                      .fontColor(AppTheme.TEXT_PRIMARY)
                      .lineHeight(24)
                  }
                  .width('100%')
                  .alignItems(HorizontalAlign.Start)
                }
              }, (seg: TranscriptSegment) => `${seg.seq}`)
              if (this.interimText !== '') {
                ListItem() {
                  Column({ space: AppTheme.SPACE_XS }) {
                    Text('正在识别…').fontSize(AppTheme.FONT_CAPTION).fontColor(AppTheme.PRIMARY)
                    Text(this.interimText).fontSize(AppTheme.FONT_BODY)
                      .fontColor(AppTheme.TEXT_PRIMARY).lineHeight(24)
                  }.width('100%').alignItems(HorizontalAlign.Start)
                }
              }
            }
            .width('100%')
            .height('100%')
            .scrollBar(BarState.Auto)
          }
        }
        .layoutWeight(1)
        .width('100%')
        .padding(AppTheme.SPACE_L)
        .borderRadius(26)
        .backgroundColor('rgba(255,255,255,0.72)')
        .border({ width: 1.2, color: RECORD_BORDER })
        .shadow({ radius: 24, color: 'rgba(31,62,68,0.10)', offsetX: 0, offsetY: 10 })

        if (this.recordState === 'finished') {
          this.outlinePanel()
        }
      }
        .layoutWeight(1)
        .height('100%')
        .padding(AppTheme.SPACE_L)
        .borderRadius(34)
        .backgroundColor(RECORD_GLASS)
        .border({ width: 1.2, color: RECORD_BORDER })
        .shadow({ radius: 30, color: 'rgba(31,62,68,0.12)', offsetX: 0, offsetY: 14 })
      }
      .layoutWeight(1)
      .width('100%')
      .alignItems(VerticalAlign.Top)
      }
      .width('100%')
      .height('100%')
      .padding({ left: AppTheme.SPACE_XXL, right: AppTheme.SPACE_XXL, top: 28, bottom: AppTheme.SPACE_XXL })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(RECORD_BG)
    .onAreaChange((oldArea: Area, newArea: Area) => { this.compact = Number(newArea.width) < 1000 || Number(newArea.height) < 560; })
  }
}
