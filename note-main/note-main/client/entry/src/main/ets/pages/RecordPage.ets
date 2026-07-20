import { audio } from '@kit.AudioKit';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { promptAction } from '@kit.ArkUI';
import { AppTheme } from '../common/AppTheme';
import { Outline, TranscriptSegment } from '../model/Models';
import { Api } from '../service/Api';
import { GlobalState } from '../service/GlobalState';

type RecordState = 'idle' | 'recording' | 'paused' | 'finished';

const CHUNK_INTERVAL_MS: number = 4000;

/**
 * 课堂录音（Notein 风）：左侧居中大计时 + 圆形录制按钮，右侧转写浮岛。
 * AudioCapturer 采集 → 分片上传 → 云端 ASR 转写实时回显；
 * 无麦克风权限/初始化失败自动降级「模拟模式」。
 */
@Component
export struct RecordPage {
  @StorageLink('classSubPage') classSubPage: string = 'record';
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
  @State uploadFailures: number = 0;
  private sessionId: number = -1;
  private seq: number = 0;
  private capturer: audio.AudioCapturer | null = null;
  private pendingBuffers: ArrayBuffer[] = [];
  private chunkTimer: number = -1;
  private clockTimer: number = -1;
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    if (this.title === '') {
      this.title = this.defaultTitle();
    }
  }

  aboutToDisappear(): void {
    this.stopTimers();
    this.releaseCapturer();
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
    if (GlobalState.course === null) {
      this.toast('请先选择课程');
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
      interface SessionResp {
        id: number;
      }

      const resp: SessionResp = JSON.parse(await Api.post('/sessions', body)) as SessionResp;
      this.sessionId = resp.id;
    } catch (e) {
      this.toast(`创建课时失败：${(e as Error).message}`);
      return;
    }

    await this.initCapturer();
    this.recordState = 'recording';
    this.startTimers();
  }

  private async initCapturer(): Promise<void> {
    try {
      const perms: Permissions[] = ['ohos.permission.MICROPHONE'];
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      const result = await atManager.requestPermissionsFromUser(ctx, perms);
      const granted: boolean = result.authResults.length > 0 && result.authResults[0] === 0;
      if (!granted) {
        this.simulated = true;
        this.toast('未授予麦克风权限，进入模拟模式');
        return;
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
      this.simulated = true;
      this.toast('麦克风初始化失败，进入模拟模式');
    }
  }

  private startTimers(): void {
    this.clockTimer = setInterval(() => {
      this.elapsedSec += 1;
    }, 1000);
    this.chunkTimer = setInterval(() => {
      this.flushChunk();
    }, CHUNK_INTERVAL_MS);
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
  }

  private releaseCapturer(): void {
    if (this.capturer !== null) {
      const c: audio.AudioCapturer = this.capturer;
      this.capturer = null;
      c.release();
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
      return new Uint8Array([0, 0, 0, 0]).buffer;
    }
    const out: Uint8Array = new Uint8Array(total);
    let offset: number = 0;
    for (const b of list) {
      out.set(new Uint8Array(b), offset);
      offset += b.byteLength;
    }
    return out.buffer;
  }

  private async flushChunk(): Promise<void> {
    if (this.sessionId < 0) {
      return;
    }
    const data: ArrayBuffer = this.mergeBuffers();
    const currentSeq: number = this.seq;
    this.seq += 1;
    try {
      const seg: TranscriptSegment =
        JSON.parse(await Api.uploadChunk(this.sessionId, currentSeq, data)) as TranscriptSegment;
      this.segments.push(seg);
      this.scroller.scrollEdge(Edge.Bottom);
    } catch (e) {
      this.uploadFailures += 1;
    }
  }

  private async pauseOrResume(): Promise<void> {
    if (this.recordState === 'recording') {
      this.recordState = 'paused';
      this.stopTimers();
      if (this.capturer !== null) {
        await this.capturer.stop();
      }
    } else if (this.recordState === 'paused') {
      this.recordState = 'recording';
      this.startTimers();
      if (this.capturer !== null) {
        await this.capturer.start();
      }
    }
  }

  private async finish(): Promise<void> {
    this.stopTimers();
    await this.flushChunk();
    this.releaseCapturer();
    try {
      await Api.post(`/sessions/${this.sessionId}/finish`);
    } catch (e) {
      // 网络异常不阻塞收尾
    }
    this.recordState = 'finished';
    GlobalState.currentSessionId = this.sessionId;
    this.toast('录音结束，转写已保存，可在此生成提纲');
  }

  private prepareNextRecording(): void {
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
      this.toast(GlobalState.isTeacher() ? '官方草稿已保存' : '已保存到我的课堂');
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
  waveBar(h: number) {
    Column()
      .width(4)
      .height(this.recordState === 'recording' ? h : 8)
      .borderRadius(2)
      .backgroundColor(this.recordState === 'recording' ? AppTheme.PRIMARY : AppTheme.DIVIDER)
      .margin({ left: 3, right: 3 })
  }

  /** 圆形操作钮（Notein 悬浮圆钮风格） */
  @Builder
  circleButton(label: string, size: number, bg: string, fg: string, onTap: () => void) {
    Text(label)
      .fontSize(size * 0.36)
      .fontColor(fg)
      .width(size)
      .height(size)
      .textAlign(TextAlign.Center)
      .borderRadius(size / 2)
      .backgroundColor(bg)
      .shadow({ radius: 14, color: 'rgba(17,17,17,0.12)', offsetX: 0, offsetY: 4 })
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
        .backgroundColor(AppTheme.BG_CARD)
        .borderRadius(AppTheme.RADIUS_CARD)
        .enabled(this.outlineData !== null && this.outlineData.status !== 'published')
        .onChange((v: string) => {
          this.outlineText = v;
          this.outlineDirty = true;
        })

      Row({ space: AppTheme.SPACE_M }) {
        Button(this.generatingOutline ? '生成中…' : '生成提纲')
          .layoutWeight(1)
          .enabled(!this.generatingOutline && this.segments.length > 0)
          .backgroundColor(AppTheme.PRIMARY)
          .borderRadius(999)
          .onClick(() => {
            this.generateOutline();
          })
        Button(this.savingOutline ? '保存中…' : '保存')
          .layoutWeight(1)
          .enabled(!this.savingOutline && this.outlineText.trim() !== '' &&
            (this.outlineData === null || this.outlineData.status !== 'published'))
          .backgroundColor(AppTheme.BG_CARD)
          .fontColor(AppTheme.TEXT_SECONDARY)
          .borderRadius(AppTheme.RADIUS_BTN)
          .onClick(() => {
            this.saveOutline();
          })
        if (GlobalState.isTeacher()) {
          Button(this.publishingOutline ? '发布中…' : '发布')
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
  }

  build() {
    Column({ space: AppTheme.SPACE_L }) {
      Row() {
        this.backButton()
        Blank()
        Text('课堂录音')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.TEXT_TERTIARY)
          .padding({ left: 12, right: 12, top: 5, bottom: 5 })
          .borderRadius(999)
          .backgroundColor(AppTheme.BG_CARD)
      }
      .width('100%')
      .height(44)

      Row({ space: AppTheme.SPACE_XL }) {
        // 左：录音控制台
        Column({ space: AppTheme.SPACE_XL }) {
        Blank().layoutWeight(1)

        TextInput({ text: this.title, placeholder: '本次课时标题' })
          .fontSize(AppTheme.FONT_SUBTITLE)
          .textAlign(TextAlign.Center)
          .backgroundColor('transparent')
          .enabled(this.recordState === 'idle')
          .onChange((v: string) => {
            this.title = v;
          })

        Text(this.fmtDuration())
          .fontSize(64)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.recordState === 'recording' ? AppTheme.INK : AppTheme.TEXT_TERTIARY)

        Row() {
          this.waveBar(14)
          this.waveBar(28)
          this.waveBar(40)
          this.waveBar(24)
          this.waveBar(46)
          this.waveBar(32)
          this.waveBar(18)
          this.waveBar(36)
          this.waveBar(26)
          this.waveBar(14)
        }
        .height(56)
        .alignItems(VerticalAlign.Center)

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
          .fontColor(AppTheme.TEXT_TERTIARY)

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
      .width(360)
      .height('100%')

      // 右：实时转写浮岛
      Column({ space: AppTheme.SPACE_M }) {
        Text('实时转写')
          .fontSize(AppTheme.FONT_SUBTITLE)
          .fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.INK)
          .width('100%')

        Column() {
          if (this.segments.length === 0) {
            Column({ space: AppTheme.SPACE_M }) {
              Text('💬').fontSize(40)
              Text(this.recordState === 'idle' ?
                '开始录音后，云端转写文字将在此实时显示' : '等待首个分片转写…')
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
            }
            .width('100%')
            .height('100%')
            .scrollBar(BarState.Auto)
          }
        }
        .layoutWeight(1)
        .width('100%')
        .padding(AppTheme.SPACE_L)
        .borderRadius(AppTheme.RADIUS_CARD)
        .backgroundColor(AppTheme.BG_CARD)
        .shadow({ radius: 16, color: 'rgba(17,17,17,0.04)', offsetX: 0, offsetY: 4 })

        if (this.recordState === 'finished') {
          this.outlinePanel()
        }
      }
        .layoutWeight(1)
        .height('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    .height('100%')
    .padding(AppTheme.SPACE_XXL)
    .backgroundColor(AppTheme.BG_PAGE)
    .alignItems(HorizontalAlign.Start)
  }
}
