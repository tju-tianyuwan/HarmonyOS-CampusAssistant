import { promptAction } from '@kit.ArkUI';
import { AppTheme } from '../common/AppTheme';
import { CourseSession, Outline, TranscriptSegment } from '../model/Models';
import { Api } from '../service/Api';
import { GlobalState } from '../service/GlobalState';

const CLASS_BG: string = '#F2F7F6';
const CLASS_PANEL: string = '#FFFFFF';
const CLASS_SOFT: string = '#F5FFFB';
const CLASS_CYAN: string = '#12BFE8';
const CLASS_BLUE: string = '#3F7DFF';
const CLASS_AMBER: string = '#FFB84D';
const CLASS_VIOLET: string = '#7A63F3';
const CLASS_GLASS: string = 'rgba(255,255,255,0.90)';
const CLASS_BORDER: string = 'rgba(255,255,255,0.92)';

/**
 * 课堂：卡片列表 | 课堂详情（转写文本 + AI 提纲）。
 */
@Component
export struct ClassPage {
  @State sessions: CourseSession[] = [];
  @State selectedIndex: number = 0;
  @State detailOpen: boolean = false;
  @State transcript: TranscriptSegment[] = [];
  @State outlineData: Outline | null = null;
  @State outlineText: string = '';
  @State outlineDirty: boolean = false;
  @State savingOutline: boolean = false;
  @State publishingOutline: boolean = false;
  @State pageReady: boolean = false;
  @State pulse: boolean = false;
  @State pressedIndex: number = -1;
  private introTimer: number = -1;
  private pulseTimer: number = -1;

  aboutToAppear(): void {
    this.loadSessions();
    this.pageReady = false;
    this.introTimer = setTimeout(() => {
      this.pageReady = true;
      this.introTimer = -1;
    }, 24);
    if (this.pulseTimer < 0) {
      this.pulseTimer = setInterval(() => {
        this.pulse = !this.pulse;
      }, 1500);
    }
  }

  aboutToDisappear(): void {
    if (this.introTimer >= 0) {
      clearTimeout(this.introTimer);
      this.introTimer = -1;
    }
    if (this.pulseTimer >= 0) {
      clearInterval(this.pulseTimer);
      this.pulseTimer = -1;
    }
  }

  private toast(msg: string): void {
    promptAction.showToast({ message: msg });
  }

  private currentSession(): CourseSession | null {
    return this.sessions.length === 0 ? null : this.sessions[this.selectedIndex];
  }

  private async loadSessions(): Promise<void> {
    try {
      const all: CourseSession[] = JSON.parse(
        await Api.get(`/sessions?class_course_id=${GlobalState.courseId()}&user_id=${GlobalState.userId()}`)) as CourseSession[];
      const visible: CourseSession[] = [];
      for (let i = 0; i < all.length; i++) {
        const s: CourseSession = all[i];
        if (this.canSeeSessionCard(s)) {
          visible.push(s);
        } else if (s.creator_id !== GlobalState.userId()) {
          const published: boolean = await this.patchPublishedOfficialMeta(s);
          if (published) {
            visible.push(s);
          }
        }
      }
      this.sessions = visible;
      GlobalState.currentSessionId = -1;
    } catch (e) {
      this.toast(`加载课时失败：${(e as Error).message}`);
    }
  }

  private async patchPublishedOfficialMeta(s: CourseSession): Promise<boolean> {
    try {
      const outline: Outline = JSON.parse(
        await Api.get(`/sessions/${s.id}/outline?user_id=${GlobalState.userId()}`)) as Outline;
      if (outline.status === 'published') {
        s.outline_kind = 'official';
        s.outline_status = 'published';
        return true;
      }
    } catch (e) {
      return false;
    }
    return false;
  }

  private canSeeSessionCard(s: CourseSession): boolean {
    if (!GlobalState.isTeacher() && s.outline_kind === 'official' && s.outline_status !== 'published') {
      if (s.creator_id === GlobalState.userId()) {
        s.outline_kind = 'self';
        s.outline_status = s.status;
        return true;
      }
      return false;
    }
    if (s.creator_id === GlobalState.userId()) {
      return true;
    }
    return s.outline_kind === 'official' && s.outline_status === 'published';
  }

  private async selectSession(index: number): Promise<void> {
    this.selectedIndex = index;
    const s: CourseSession | null = this.currentSession();
    if (s === null) {
      return;
    }
    try {
      this.transcript = JSON.parse(
        await Api.get(`/sessions/${s.id}/transcript?user_id=${GlobalState.userId()}`)) as TranscriptSegment[];
    } catch (e) {
      this.transcript = [];
    }
    try {
      this.outlineData = JSON.parse(
        await Api.get(`/sessions/${s.id}/outline?user_id=${GlobalState.userId()}`)) as Outline;
      if (!GlobalState.isTeacher() && s.outline_kind !== 'personal' && this.outlineData.status !== 'published') {
        this.outlineData = null;
        this.outlineText = '';
        this.outlineDirty = false;
      } else {
        this.outlineText = this.outlineData.markdown;
        this.outlineDirty = false;
      }
    } catch (e) {
      this.outlineData = null; // 404：尚未生成
      this.outlineText = '';
      this.outlineDirty = false;
    }
    this.detailOpen = true;
  }

  private canEditOfficialOutline(): boolean {
    return GlobalState.isTeacher() && this.outlineData !== null &&
      this.outlineData.owner_id === -1 && this.outlineData.status !== 'published';
  }

  private async saveDetailOutline(): Promise<boolean> {
    const s: CourseSession | null = this.currentSession();
    if (s === null || this.outlineText.trim() === '') {
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
        `/sessions/${s.id}/outline?user_id=${GlobalState.userId()}`, body)) as Outline;
      this.outlineText = this.outlineData.markdown;
      this.outlineDirty = false;
      this.toast('官方草稿已保存');
      return true;
    } catch (e) {
      this.toast(`保存失败：${(e as Error).message}`);
      return false;
    } finally {
      this.savingOutline = false;
    }
  }

  private async publishDetailOutline(): Promise<void> {
    const s: CourseSession | null = this.currentSession();
    if (s === null || this.outlineData === null) {
      return;
    }
    if (this.outlineDirty) {
      const saved: boolean = await this.saveDetailOutline();
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
        await Api.post(`/sessions/${s.id}/outline/review`, body)) as Outline;
      this.outlineText = this.outlineData.markdown;
      this.outlineDirty = false;
      this.toast('已发布并写入本课程知识库');
    } catch (e) {
      this.toast(`操作失败：${(e as Error).message}`);
    } finally {
      this.publishingOutline = false;
    }
  }

  private statusLabel(): string {
    if (this.outlineData === null) {
      return '未生成';
    }
    const s: string = this.outlineData.status;
    if (s === 'draft') {
      return '草稿';
    }
    if (s === 'generated') {
      return '未保存';
    }
    if (s === 'pending') {
      return '待审核';
    }
    if (s === 'published') {
      return '已发布';
    }
    return '已退回';
  }

  private statusColor(): string {
    if (this.outlineData === null) {
      return AppTheme.TEXT_TERTIARY;
    }
    const s: string = this.outlineData.status;
    if (s === 'published') {
      return AppTheme.SUCCESS;
    }
    if (s === 'rejected') {
      return AppTheme.DANGER;
    }
    return AppTheme.WARNING;
  }

  private sessionCardDesc(s: CourseSession): string {
    if (s.outline_kind === 'official' && s.outline_status === 'published') {
      return '老师校准发布，班级可见，已写入课程知识库。';
    }
    if (s.outline_kind === 'personal') {
      return '仅自己可见，不进入课程 AI 知识库。';
    }
    if (s.outline_kind === 'self') {
      return '自己录音得到的转写课时，仅自己可见。';
    }
    if (s.outline_kind === 'official') {
      return '老师生成的官方草稿，发布后班级可见。';
    }
    return '尚未生成提纲，可在录音页面生成。';
  }

  private sessionTagLabel(s: CourseSession): string {
    if (s.outline_kind === 'official' && s.outline_status === 'published') {
      return '官方发布';
    }
    if (s.outline_kind === 'official') {
      return '官方草稿';
    }
    if (s.outline_kind === 'personal') {
      return '个人提纲';
    }
    if (s.outline_kind === 'self') {
      return '我的录音';
    }
    return '课时记录';
  }

  private sessionTagColor(s: CourseSession): string {
    if (s.outline_kind === 'official' && s.outline_status === 'published') {
      return AppTheme.SUCCESS;
    }
    if (s.outline_kind === 'personal') {
      return AppTheme.PRIMARY;
    }
    if (s.outline_kind === 'self') {
      return AppTheme.TEXT_SECONDARY;
    }
    return AppTheme.WARNING;
  }

  @Builder
  pageAtmosphere() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 34,
          colors: [
            ['#F8FCFA', 0],
            [CLASS_BG, 0.54],
            ['#EEF3FF', 1]
          ]
        })
      Column()
        .width(560)
        .height(560)
        .borderRadius(72)
        .rotate({ angle: -18 })
        .backgroundColor('rgba(5,206,145,0.11)')
        .position({ x: -190, y: -120 })
        .translate({ x: this.pulse ? 10 : 0, y: this.pulse ? 0 : 8 })
        .animation({ duration: 1200, curve: Curve.EaseOut })
      Column()
        .width(660)
        .height(360)
        .borderRadius(58)
        .rotate({ angle: 12 })
        .backgroundColor('rgba(63,125,255,0.08)')
        .position({ x: 980, y: 300 })
      Column()
        .width('100%')
        .height(1)
        .backgroundColor('rgba(255,255,255,0.72)')
        .position({ x: 0, y: 236 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  classHero() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .borderRadius(32)
        .linearGradient({
          angle: 118,
          colors: [
            [CLASS_PANEL, 0],
            [CLASS_SOFT, 0.58],
            ['#EEF3FF', 1]
          ]
        })
      Column()
        .width(520)
        .height(210)
        .borderRadius(46)
        .rotate({ angle: -10 })
        .linearGradient({
          angle: 80,
          colors: [
            ['rgba(255,184,77,0.20)', 0],
            ['rgba(5,206,145,0.12)', 0.60],
            ['rgba(255,255,255,0.02)', 1]
          ]
        })
        .position({ x: -80, y: -58 })
      Column()
        .width(380)
        .height(220)
        .borderRadius(44)
        .rotate({ angle: 11 })
        .backgroundColor('rgba(63,125,255,0.13)')
        .position({ x: 900, y: -46 })
        .translate({ x: this.pulse ? -10 : 0, y: this.pulse ? 7 : 0 })
        .animation({ duration: 1200, curve: Curve.EaseOut })
      Row() {
        Column({ space: AppTheme.SPACE_M }) {
          Row({ space: 8 }) {
            Text('CLASS TRACE')
              .fontSize(11)
              .fontWeight(FontWeight.Bold)
              .fontColor('#121818')
              .padding({ left: 12, right: 12, top: 5, bottom: 5 })
              .borderRadius(999)
              .backgroundColor(CLASS_AMBER)
            Text(`${this.sessions.length} 条课堂记录`)
              .fontSize(11)
              .fontColor('rgba(18,24,24,0.58)')
              .padding({ left: 12, right: 12, top: 5, bottom: 5 })
              .borderRadius(999)
              .backgroundColor('rgba(18,24,24,0.06)')
          }
          Text('课堂')
            .fontSize(48)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.INK)
          Text('从录音、转写到 AI 提纲，沿着课时轨迹回看每一次课堂发生的知识。')
            .fontSize(AppTheme.FONT_BODY)
            .fontColor('rgba(18,24,24,0.56)')
            .maxLines(1)
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width(160)
            .height(160)
            .borderRadius(80)
            .border({ width: 1.4, color: 'rgba(18,24,24,0.12)' })
          Column()
            .width(116)
            .height(3)
            .borderRadius(2)
            .rotate({ angle: 24 })
            .backgroundColor('rgba(18,191,232,0.38)')
          Column()
            .width(102)
            .height(3)
            .borderRadius(2)
            .rotate({ angle: -28 })
            .backgroundColor('rgba(5,206,145,0.36)')
          this.heroNode('录', CLASS_CYAN, 22, 68, 54)
          this.heroNode('转', CLASS_AMBER, 88, 98, 50)
          this.heroNode('思', AppTheme.PRIMARY, 150, 58, 58)
        }
        .width(230)
        .height(188)
        .scale({ x: this.pulse ? 1.025 : 1, y: this.pulse ? 1.025 : 1 })
        .animation({ duration: 1200, curve: Curve.EaseOut })
      }
      .width('100%')
      .height('100%')
      .padding({ left: 34, right: 32 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(190)
    .clip(true)
    .borderRadius(32)
    .border({ width: 1.2, color: CLASS_BORDER })
    .shadow({ radius: 30, color: 'rgba(31,62,68,0.12)', offsetX: 0, offsetY: 14 })
  }

  @Builder
  heroNode(label: string, color: string, x: number, y: number, size: number) {
    Text(label)
      .fontSize(16)
      .fontWeight(FontWeight.Bold)
      .fontColor('#FFFFFF')
      .width(size)
      .height(size)
      .textAlign(TextAlign.Center)
      .borderRadius(size / 2)
      .backgroundColor(color)
      .border({ width: 1.2, color: 'rgba(255,255,255,0.76)' })
      .shadow({ radius: 18, color: color, offsetX: 0, offsetY: 8 })
      .position({ x: x, y: y })
  }

  @Builder
  sessionCard(s: CourseSession, index: number) {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .borderRadius(24)
        .backgroundColor(s.outline_kind === 'official' && s.outline_status === 'published' ?
          'rgba(229,248,239,0.94)' : CLASS_GLASS)
      Column()
        .width(88)
        .height(88)
        .borderRadius(26)
        .rotate({ angle: -12 })
        .backgroundColor(AppTheme.tagBg(this.sessionTagColor(s)))
        .position({ x: 206, y: 114 })
      Column({ space: AppTheme.SPACE_M }) {
      Row() {
        Text(this.sessionTagLabel(s))
          .fontSize(AppTheme.FONT_CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor(s.outline_kind === 'official' && s.outline_status === 'published' ? '#FFFFFF' :
            this.sessionTagColor(s))
          .padding({ left: 10, right: 10, top: 4, bottom: 4 })
          .borderRadius(999)
          .backgroundColor(s.outline_kind === 'official' && s.outline_status === 'published' ?
            AppTheme.SUCCESS : AppTheme.tagBg(this.sessionTagColor(s)))
        Blank()
        Text(s.created_at.substring(0, 10))
          .fontSize(10)
          .fontColor(AppTheme.TEXT_TERTIARY)
      }
      .width('100%')

      Text(s.title)
        .fontSize(AppTheme.FONT_SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.TEXT_PRIMARY)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.sessionCardDesc(s))
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(AppTheme.TEXT_SECONDARY)
        .maxLines(3)
      Blank()
        Row({ space: 7 }) {
          Text('打开课堂')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor(this.sessionTagColor(s))
          Text('→')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.sessionTagColor(s))
        }
      }
      .width('100%')
      .height('100%')
      .padding(AppTheme.SPACE_L)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .height(210)
    .clip(true)
    .borderRadius(24)
    .border({
      width: 1.2,
      color: s.outline_kind === 'official' && s.outline_status === 'published' ? AppTheme.SUCCESS : CLASS_BORDER
    })
    .shadow({
      radius: this.pressedIndex === index ? 16 : (s.outline_kind === 'official' && s.outline_status === 'published' ? 26 : 22),
      color: this.pressedIndex === index ? 'rgba(31,62,68,0.08)' :
        (s.outline_kind === 'official' && s.outline_status === 'published' ?
          'rgba(14,173,105,0.18)' : 'rgba(31,62,68,0.12)'),
      offsetX: 0,
      offsetY: this.pressedIndex === index ? 6 : 10
    })
    .translate({ x: 0, y: this.pressedIndex === index ? 5 : 0 })
    .scale({
      x: this.pressedIndex === index ? 0.976 : 1,
      y: this.pressedIndex === index ? 0.976 : 1
    })
    .animation({ duration: this.pressedIndex === index ? 90 : 240, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressedIndex = index;
      } else if (event.type === TouchType.Up) {
        this.pressedIndex = -1;
      }
    })
    .onClick(() => {
      this.pressedIndex = -1;
      this.selectSession(index);
    })
  }

  @Builder
  listView() {
    Column({ space: AppTheme.SPACE_L }) {
      this.classHero()

      if (this.sessions.length === 0) {
        Column({ space: AppTheme.SPACE_S }) {
          Stack({ alignContent: Alignment.Center }) {
            Column()
              .width(96)
              .height(96)
              .borderRadius(32)
              .rotate({ angle: -10 })
              .backgroundColor(AppTheme.tagBg(CLASS_AMBER))
            Text('录')
              .fontSize(38)
              .fontWeight(FontWeight.Bold)
              .fontColor(CLASS_AMBER)
          }
          .width(120)
          .height(112)
          Text('暂无可见课堂记录')
            .fontSize(22)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.INK)
          Text(GlobalState.isTeacher() ? '完成自己的录音后会显示在这里' : '完成自己的录音，或老师发布官方课时后会显示在这里')
            .fontSize(AppTheme.FONT_BODY)
            .fontColor(AppTheme.TEXT_SECONDARY)
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Scroll() {
          Grid() {
            ForEach(this.sessions, (s: CourseSession, index: number) => {
              GridItem() {
                this.sessionCard(s, index)
              }
            }, (s: CourseSession) => `${s.id}`)
          }
          .columnsTemplate('1fr 1fr 1fr 1fr')
          .columnsGap(AppTheme.SPACE_L)
          .rowsGap(AppTheme.SPACE_L)
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: AppTheme.SPACE_XXL, right: AppTheme.SPACE_XXL, top: 28, bottom: AppTheme.SPACE_XXL })
    .opacity(this.pageReady ? 1 : 0)
    .translate({ x: 0, y: this.pageReady ? 0 : 24 })
    .scale({ x: this.pageReady ? 1 : 0.986, y: this.pageReady ? 1 : 0.986 })
    .animation({ duration: 360, curve: Curve.EaseOut })
  }

  @Builder
  transcriptPane() {
    Column({ space: AppTheme.SPACE_M }) {
      Text('转写文本')
        .fontSize(AppTheme.FONT_BODY)
        .fontColor(AppTheme.TEXT_SECONDARY)
        .width('100%')
      Scroll() {
        Column({ space: AppTheme.SPACE_L }) {
          if (this.transcript.length === 0) {
            Text('暂无转写内容')
              .fontSize(AppTheme.FONT_BODY)
              .fontColor(AppTheme.TEXT_TERTIARY)
          }
          ForEach(this.transcript, (seg: TranscriptSegment) => {
            Column({ space: AppTheme.SPACE_XS }) {
              Text(`${Math.floor(seg.start_ms / 60000)}:${
                ((seg.start_ms % 60000) / 1000).toFixed(0).padStart(2, '0')}`)
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(AppTheme.PRIMARY)
              Text(seg.text)
                .fontSize(AppTheme.FONT_BODY)
                .fontColor(AppTheme.TEXT_PRIMARY)
                .lineHeight(22)
            }
            .width('100%')
            .alignItems(HorizontalAlign.Start)
          }, (seg: TranscriptSegment) => `${seg.id}`)
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }
      .layoutWeight(1)
      .width('100%')
      .padding(AppTheme.SPACE_L)
      .borderRadius(24)
      .backgroundColor(CLASS_GLASS)
      .border({ width: 1.2, color: CLASS_BORDER })
      .shadow({ radius: 22, color: 'rgba(31,62,68,0.10)', offsetX: 0, offsetY: 10 })
      .scrollBar(BarState.Auto)
    }
    .layoutWeight(1)
    .height('100%')
  }

  @Builder
  outlinePane() {
    Column({ space: AppTheme.SPACE_M }) {
      Row({ space: AppTheme.SPACE_S }) {
        Text('AI 提纲')
          .fontSize(AppTheme.FONT_BODY)
          .fontColor(AppTheme.TEXT_SECONDARY)
        Text(this.statusLabel())
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(this.statusColor())
          .padding({ left: 10, right: 10, top: 3, bottom: 3 })
          .borderRadius(999)
          .backgroundColor(AppTheme.tagBg(this.statusColor()))
        if (this.outlineDirty) {
          Text('待保存')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.WARNING)
        }
        Blank()
      }
      .width('100%')

      if (this.canEditOfficialOutline()) {
        TextArea({ text: this.outlineText, placeholder: '校准官方提纲内容' })
          .layoutWeight(1)
          .width('100%')
          .fontSize(AppTheme.FONT_BODY)
          .backgroundColor(CLASS_GLASS)
          .borderRadius(24)
          .onChange((v: string) => {
            this.outlineText = v;
            this.outlineDirty = true;
          })
        Row({ space: AppTheme.SPACE_M }) {
          Button(this.savingOutline ? '保存中…' : '保存草稿')
            .layoutWeight(1)
            .enabled(!this.savingOutline)
            .backgroundColor(CLASS_GLASS)
            .fontColor(AppTheme.TEXT_SECONDARY)
            .borderRadius(AppTheme.RADIUS_BTN)
            .onClick(() => {
              this.saveDetailOutline();
            })
          Button(this.publishingOutline ? '发布中…' : '发布')
            .layoutWeight(1)
            .enabled(!this.publishingOutline)
            .backgroundColor(AppTheme.SUCCESS)
            .borderRadius(999)
            .onClick(() => {
              this.publishDetailOutline();
            })
        }
        .width('100%')
      } else {
        Scroll() {
          Column() {
            Text(this.outlineData === null ? '暂无提纲。请在录音页面生成。' : this.outlineText)
              .fontSize(AppTheme.FONT_BODY)
              .fontColor(this.outlineData === null ? AppTheme.TEXT_TERTIARY : AppTheme.TEXT_PRIMARY)
              .lineHeight(24)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .layoutWeight(1)
        .width('100%')
        .padding(AppTheme.SPACE_L)
        .borderRadius(24)
        .backgroundColor(CLASS_GLASS)
        .border({ width: 1.2, color: CLASS_BORDER })
        .shadow({ radius: 22, color: 'rgba(31,62,68,0.10)', offsetX: 0, offsetY: 10 })
        .scrollBar(BarState.Auto)
      }
    }
    .layoutWeight(1)
    .height('100%')
  }

  @Builder
  detailView() {
    Column({ space: AppTheme.SPACE_L }) {
      Row({ space: AppTheme.SPACE_M }) {
        Text('‹')
          .fontSize(28)
          .fontColor(AppTheme.INK)
          .width(36)
          .height(36)
          .textAlign(TextAlign.Center)
          .borderRadius(18)
          .backgroundColor(CLASS_GLASS)
          .shadow({ radius: 14, color: 'rgba(31,62,68,0.08)', offsetX: 0, offsetY: 5 })
          .onClick(() => {
            this.detailOpen = false;
          })
        Text(this.currentSession() === null ? '课堂详情' : this.currentSession()!.title)
          .fontSize(AppTheme.FONT_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.INK)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Blank()
      }
      .width('100%')
      .height(44)

      Row({ space: AppTheme.SPACE_L }) {
        this.transcriptPane()
        this.outlinePane()
      }
      .layoutWeight(1)
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    .height('100%')
    .padding({ left: AppTheme.SPACE_XXL, right: AppTheme.SPACE_XXL, top: 28, bottom: AppTheme.SPACE_XXL })
    .opacity(this.pageReady ? 1 : 0)
    .translate({ x: 0, y: this.pageReady ? 0 : 18 })
    .animation({ duration: 280, curve: Curve.EaseOut })
  }

  build() {
    Stack() {
      this.pageAtmosphere()
      if (this.detailOpen) {
        this.detailView()
      } else {
        this.listView()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(CLASS_BG)
  }
}
