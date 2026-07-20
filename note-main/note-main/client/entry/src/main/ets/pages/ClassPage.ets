import { promptAction } from '@kit.ArkUI';
import { AppTheme } from '../common/AppTheme';
import { CourseSession, Outline, TranscriptSegment } from '../model/Models';
import { Api } from '../service/Api';
import { GlobalState } from '../service/GlobalState';

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

  aboutToAppear(): void {
    this.loadSessions();
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
  sessionCard(s: CourseSession, index: number) {
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
        .maxLines(2)
      Blank()
      Text('打开课堂')
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(this.sessionTagColor(s))
    }
    .width(286)
    .height(188)
    .padding(AppTheme.SPACE_L)
    .borderRadius(18)
    .backgroundColor(s.outline_kind === 'official' && s.outline_status === 'published' ?
      'rgba(229,248,239,0.96)' : AppTheme.BG_CARD)
    .border({
      width: s.outline_kind === 'official' && s.outline_status === 'published' ? 1.5 : 0,
      color: s.outline_kind === 'official' && s.outline_status === 'published' ? AppTheme.SUCCESS : 'transparent'
    })
    .shadow({
      radius: s.outline_kind === 'official' && s.outline_status === 'published' ? 24 : 18,
      color: s.outline_kind === 'official' && s.outline_status === 'published' ?
        'rgba(14,173,105,0.18)' : 'rgba(0,0,0,0.06)',
      offsetX: 0,
      offsetY: 6
    })
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      this.selectSession(index);
    })
  }

  @Builder
  listView() {
    Column({ space: AppTheme.SPACE_L }) {
      Row() {
        Text('课堂')
          .fontSize(AppTheme.FONT_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.INK)
        Blank()
        Text(`${this.sessions.length} 条课堂记录`)
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.TEXT_SECONDARY)
          .padding({ left: 12, right: 12, top: 5, bottom: 5 })
          .borderRadius(999)
          .backgroundColor(AppTheme.BG_CARD)
      }
      .width('100%')
      .height(44)

      if (this.sessions.length === 0) {
        Column({ space: AppTheme.SPACE_S }) {
          Text('暂无可见课堂记录')
            .fontSize(AppTheme.FONT_SUBTITLE)
            .fontColor(AppTheme.TEXT_SECONDARY)
          Text(GlobalState.isTeacher() ? '完成自己的录音后会显示在这里' : '完成自己的录音，或老师发布官方课时后会显示在这里')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.TEXT_TERTIARY)
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Scroll() {
          Flex({ wrap: FlexWrap.Wrap }) {
            ForEach(this.sessions, (s: CourseSession, index: number) => {
              Column() {
                this.sessionCard(s, index)
              }
              .margin({ right: AppTheme.SPACE_L, bottom: AppTheme.SPACE_L })
            }, (s: CourseSession) => `${s.id}`)
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
      }
    }
    .width('100%')
    .height('100%')
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
      .borderRadius(AppTheme.RADIUS_CARD)
      .backgroundColor(AppTheme.BG_CARD)
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
          .backgroundColor(AppTheme.BG_CARD)
          .borderRadius(AppTheme.RADIUS_CARD)
          .onChange((v: string) => {
            this.outlineText = v;
            this.outlineDirty = true;
          })
        Row({ space: AppTheme.SPACE_M }) {
          Button(this.savingOutline ? '保存中…' : '保存草稿')
            .layoutWeight(1)
            .enabled(!this.savingOutline)
            .backgroundColor(AppTheme.BG_CARD)
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
        .borderRadius(AppTheme.RADIUS_CARD)
        .backgroundColor(AppTheme.BG_CARD)
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
          .backgroundColor(AppTheme.BG_CARD)
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
  }

  build() {
    Stack() {
      if (this.detailOpen) {
        this.detailView()
      } else {
        this.listView()
      }
    }
    .width('100%')
    .height('100%')
    .padding(AppTheme.SPACE_XL)
    .backgroundColor(AppTheme.BG_PAGE)
  }
}
