import { TouchMotion } from '../common/TouchMotion';
import { MotionPage } from '../common/components/MotionPage';
import { promptAction } from '@kit.ArkUI';
import { picker, fileIo } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';
import { LearningTheme as AppTheme } from '../common/LearningTheme';
import { MobileLayout } from '../common/MobileLayout';
import { MobileTabs } from '../common/components/MobileTabs';
import { MarkdownView } from '../common/components/MarkdownView';
import { CourseSession, Outline, SessionNoteSummary, SessionResource, TranscriptSegment } from '../model/Models';
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
  @StorageLink('reduceMotion') reduceMotion: boolean = false;
  initialSessionId: number = -1;
  initialPane: string = 'transcript';
  initialResourceId: number = -1;
  onExitDetail: () => void = () => {};
  @State sessions: CourseSession[] = [];
  @State selectedIndex: number = 0;
  @State compact: boolean = false;
  @State compactOutline: boolean = false;
  @State compactPane: string = 'transcript';
  @State detailOpen: boolean = false;
  @State transcript: TranscriptSegment[] = [];
  @State outlineData: Outline | null = null;
  @State outlineText: string = '';
  @State outlineDirty: boolean = false;
  @State outlineEditing: boolean = false;
  @State resources: SessionResource[] = [];
  @State selectedResource: SessionResource | null = null;
  @State resourceLoading: boolean = false;
  @State resourceUploading: boolean = false;
  @State editingResource: boolean = false;
  @State resourceText: string = '';
  @State resourceSaving: boolean = false;
  @State savingOutline: boolean = false;
  @State publishingOutline: boolean = false;
  @State pageReady: boolean = false;
  @State pulse: boolean = false;
  @State pressedIndex: number = -1;
  private introTimer: number = -1;
  private pulseTimer: number = -1;
  private active: boolean = true;

  aboutToAppear(): void {
    this.active = true;
    GlobalState.beforeLeaveClass = (done: () => void) => { this.confirmLeave(done); };
    this.loadSessions();
    this.pageReady = true;
  }

  aboutToDisappear(): void {
    this.active = false;
    GlobalState.closeClassDetail = null;
    GlobalState.beforeLeaveClass = null;
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
      if (!this.active) { return; }
      this.sessions = visible;
      if (visible.length > 0) {
        this.selectedIndex = 0;
      }
      GlobalState.currentSessionId = -1;
      if (this.initialSessionId > 0) {
        const index = this.indexForSession(this.initialSessionId);
        if (index >= 0) {
          this.compactPane = this.initialPane;
          this.compactOutline = this.initialPane === 'outline';
          await this.selectSession(index);
          if (this.initialResourceId > 0) {
            const resource = this.resources.find((item: SessionResource) => item.id === this.initialResourceId);
            if (resource !== undefined) { await this.openResource(resource); }
            else { this.toast('资料已被删除或不可访问'); }
          }
        } else { this.toast('课次不存在或不可访问'); this.onExitDetail(); }
      }
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
    if (GlobalState.canManageCurrentCourse()) { return true; }
    if (!GlobalState.canManageCurrentCourse() && s.outline_kind === 'official' && s.outline_status !== 'published') {
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
      if (!GlobalState.canManageCurrentCourse() && s.outline_kind !== 'personal' && this.outlineData.status !== 'published') {
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
    try {
      this.resources = JSON.parse(await Api.get(`/sessions/${s.id}/resources`)) as SessionResource[];
    } catch (e) {
      this.resources = [];
    }
    if (!this.active) { return; }
    this.selectedResource = null;
    this.editingResource = false;
    this.detailOpen = true;
    GlobalState.currentSessionId = s.id;
    GlobalState.closeClassDetail = (): void => { this.closeDetail(); };
  }

  private confirmLeave(done: () => void): void {
    if (this.resourceSaving || this.savingOutline || this.publishingOutline || this.resourceUploading) { return; }
    if (!this.outlineDirty && (!this.editingResource || this.resourceText === this.selectedResource?.content)) {
      done(); return;
    }
    AlertDialog.show({ title: '放弃未保存的修改？', message: '尚未保存的提纲或资料修改将丢失。',
      primaryButton: { value: '继续编辑', action: () => {} },
      secondaryButton: { value: '放弃修改', action: () => {
        this.outlineDirty = false; this.editingResource = false;
        this.outlineText = this.outlineData?.markdown ?? '';
        this.resourceText = this.selectedResource?.content ?? '';
        done();
      } } });
  }

  private closeDetail(): void {
    this.confirmLeave(() => { this.finishCloseDetail(); });
  }

  private finishCloseDetail(): void {
    this.detailOpen = false;
    this.selectedResource = null;
    GlobalState.currentSessionId = -1;
    GlobalState.closeClassDetail = null;
    if (this.initialSessionId > 0) { this.onExitDetail(); }
  }

  private async saveResource(): Promise<void> {
    if (this.selectedResource === null || this.resourceSaving || !this.resourceText.trim()) { return; }
    const resource = this.selectedResource;
    this.resourceSaving = true;
    interface ResourceBody { content: string; }
    const body: ResourceBody = { content: this.resourceText };
    try {
      this.selectedResource = JSON.parse(await Api.put(`/sessions/${resource.session_id}/resources/${resource.id}`, body)) as SessionResource;
      this.editingResource = false;
      this.resources = JSON.parse(await Api.get(`/sessions/${resource.session_id}/resources`)) as SessionResource[];
      this.toast('资料已保存');
    } catch (e) { this.toast(`保存失败：${(e as Error).message}`); }
    finally { this.resourceSaving = false; }
  }

  private sessionTitle(s: CourseSession): string {
    return (s.ai_title ?? '').trim() !== '' ? s.ai_title! : s.title;
  }

  private personalNotes(s: CourseSession): SessionNoteSummary[] {
    return s.personal_notes ?? [];
  }

  private indexForSession(sessionId: number): number {
    for (let i = 0; i < this.sessions.length; i++) {
      if (this.sessions[i].id === sessionId) { return i; }
    }
    return 0;
  }

  private async openResource(resource: SessionResource): Promise<void> {
    const s: CourseSession | null = this.currentSession();
    if (s === null || this.resourceLoading) { return; }
    this.resourceLoading = true;
    try {
      this.selectedResource = JSON.parse(
        await Api.get(`/sessions/${s.id}/resources/${resource.id}`)) as SessionResource;
    } catch (e) {
      this.toast(`打开资料失败：${(e as Error).message}`);
    } finally {
      this.resourceLoading = false;
    }
  }

  private openSessionNotes(): void {
    const s: CourseSession | null = this.currentSession();
    if (s === null) { return; }
    GlobalState.pendingNoteSessionId = s.id;
    GlobalState.closeClassDetail = null;
    AppStorage.setOrCreate<string>('noteSubPage', 'personal');
    AppStorage.setOrCreate<string>('currentTab', 'notes');
    GlobalState.updateSnapshot('notes');
  }

  private openSessionNote(note: SessionNoteSummary): void {
    GlobalState.pendingOpenNoteId = note.id;
    GlobalState.pendingNoteSessionId = -1;
    GlobalState.closeClassDetail = null;
    AppStorage.setOrCreate<string>('noteSubPage', note.kind === 'handwriting' ? 'handwriting' : 'ai');
    AppStorage.setOrCreate<string>('currentTab', 'notes');
    GlobalState.updateSnapshot('notes');
  }

  private async uploadResource(): Promise<void> {
    const s: CourseSession | null = this.currentSession();
    if (s === null || this.resourceUploading || !GlobalState.canManageCurrentCourse()) { return; }
    this.resourceUploading = true;
    try {
      const files = await new picker.DocumentViewPicker(getContext(this) as common.UIAbilityContext)
        .select({ maxSelectNumber: 1 });
      if (files.length === 0) { return; }
      const file = await fileIo.open(files[0], fileIo.OpenMode.READ_ONLY);
      try {
        const info = await fileIo.stat(file.fd);
        if (info.size > 50 * 1024 * 1024) { throw new Error('文件不能超过 50 MiB'); }
        const data = new ArrayBuffer(info.size);
        const read = await fileIo.read(file.fd, data);
        if (read !== info.size) { throw new Error('文件读取不完整'); }
        const filename = decodeURIComponent(files[0].substring(files[0].lastIndexOf('/') + 1));
        await Api.upload(`/sessions/${s.id}/resources`, filename, data);
      } finally { await fileIo.close(file); }
      this.resources = JSON.parse(await Api.get(`/sessions/${s.id}/resources`)) as SessionResource[];
      this.toast('课程资料已上传');
    } catch (e) {
      this.toast(`上传失败：${(e as Error).message}`);
    } finally {
      this.resourceUploading = false;
    }
  }

  private canEditOfficialOutline(): boolean {
    return GlobalState.canManageCurrentCourse() && this.outlineData !== null &&
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

  private async publishDetailOutline(action: string = 'publish'): Promise<void> {
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

    const body: ReviewBody = { user_id: GlobalState.userId(), action: action };
    this.publishingOutline = true;
    try {
      this.outlineData = JSON.parse(
        await Api.post(`/sessions/${s.id}/outline/review`, body)) as Outline;
      this.outlineText = this.outlineData.markdown;
      this.outlineDirty = false;
      this.toast(action === 'publish' ? '已发布并写入本课程知识库' : '已撤回官方提纲');
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
          Text(GlobalState.isTeacher() ? '课堂' : '课程')
            .fontSize(48)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.INK)
          Text(GlobalState.isTeacher() ? '从录音、转写到 AI 提纲，沿着课时轨迹回看每一次课堂发生的知识。' :
            '沿着时间线回看每节课的转写、提纲、课程资料与个人笔记。')
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
  timelineNode(s: CourseSession, index: number) {
    Stack({ alignContent: Alignment.TopStart }) {
      Column().width('100%').height(3).backgroundColor('rgba(18,24,24,0.16)').position({ x: 0, y: 61 })
      Column()
        .width(this.selectedIndex === index ? 30 : 22)
        .height(this.selectedIndex === index ? 30 : 22)
        .borderRadius(this.selectedIndex === index ? 15 : 11)
        .backgroundColor(this.sessionTagColor(s))
        .border({ width: 4, color: '#FFFFFF' })
        .shadow({ radius: 12, color: this.sessionTagColor(s), offsetX: 0, offsetY: 4 })
        .position({ x: 85, y: this.selectedIndex === index ? 47 : 51 })
      Column({ space: 5 }) {
        Text(s.created_at.substring(0, 10)).fontSize(11).fontColor(AppTheme.TEXT_TERTIARY)
        Text(this.sessionTitle(s)).fontSize(15).fontWeight(FontWeight.Bold).fontColor(AppTheme.INK)
          .maxLines(2).textAlign(TextAlign.Center).textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(this.sessionTagLabel(s)).fontSize(11).fontColor(this.sessionTagColor(s))
      }
      .width(180).alignItems(HorizontalAlign.Center).position({ x: 10, y: 78 })
    }
    .width(200).height(170)
    .onClick(() => {
      this.selectedIndex = index;
    })
  }

  @Builder
  listView() {
    Column({ space: AppTheme.SPACE_L }) {
      if (GlobalState.isTeacher()) {
        this.classHero()
      } else {
        Column({ space: 8 }) {
          Text('课程').fontSize(30).fontWeight(FontWeight.Bold).fontColor(AppTheme.TEXT_PRIMARY)
          Text(`${GlobalState.course?.name ?? ''} · ${this.sessions.length} 次课堂记录`)
            .fontSize(15).fontColor(AppTheme.TEXT_SECONDARY)
        }.width('100%').alignItems(HorizontalAlign.Start).padding({ bottom: 8 })
      }

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
          Text(GlobalState.canManageCurrentCourse() ? '完成自己的录音后会显示在这里' : '老师发布课程提纲后，对应课次会显示在这里')
            .fontSize(AppTheme.FONT_BODY)
            .fontColor(AppTheme.TEXT_SECONDARY)
        }
        .layoutWeight(1)
        .width('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Center)
      } else {
        Column({ space: AppTheme.SPACE_L }) {
          Scroll() {
            Row() {
              ForEach(this.sessions.slice().reverse(), (s: CourseSession) => {
                this.timelineNode(s, this.indexForSession(s.id))
              }, (s: CourseSession) => `${s.id}`)
            }.height(170)
          }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%').height(180)

          Column({ space: AppTheme.SPACE_M }) {
            Row() {
              Column({ space: 6 }) {
                Text(this.currentSession() === null ? '' : this.sessionTitle(this.currentSession()!))
                  .fontSize(24).fontWeight(FontWeight.Bold).fontColor(AppTheme.INK)
                Text(this.currentSession()?.title ?? '').fontSize(13).fontColor(AppTheme.TEXT_TERTIARY)
              }.alignItems(HorizontalAlign.Start).layoutWeight(1)
              Button('进入课次').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).backgroundColor(AppTheme.PRIMARY).enabled(this.currentSession() !== null)
                .onClick(() => { this.selectSession(this.selectedIndex); })
            }.width('100%')
            Row({ space: 12 }) {
              Text(this.currentSession()?.outline_status === 'published' ? '已发布课程提纲' : '暂无已发布提纲')
                .fontSize(13).fontColor(AppTheme.TEXT_SECONDARY)
              Text(`${this.currentSession()?.resource_count ?? 0} 份教师资料`)
                .fontSize(13).fontColor(AppTheme.TEXT_SECONDARY)
              Text(GlobalState.isTeacher() ? '' : `${this.personalNotes(this.currentSession()!).length} 篇我的笔记`)
                .fontSize(13).fontColor(AppTheme.TEXT_SECONDARY)
            }.width('100%')
            if (!GlobalState.isTeacher() && this.personalNotes(this.currentSession()!).length > 0) {
              Row({ space: 8 }) {
                Text('我的笔记').fontSize(13).fontColor(AppTheme.TEXT_SECONDARY)
                ForEach(this.personalNotes(this.currentSession()!), (note: SessionNoteSummary) => {
                  Button(note.title).stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).fontSize(12).fontColor(AppTheme.PRIMARY_DEEP).backgroundColor(AppTheme.PRIMARY_LIGHT)
                    .onClick(() => { this.openSessionNote(note); })
                }, (note: SessionNoteSummary) => `${note.id}`)
              }.width('100%')
            }
          }.width('100%').padding(22).borderRadius(8).backgroundColor(CLASS_GLASS)
            .border({ width: 1, color: CLASS_BORDER })
          Blank()
        }.layoutWeight(1).width('100%')
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: AppTheme.SPACE_XXL, right: AppTheme.SPACE_XXL, top: 28, bottom: AppTheme.SPACE_XXL })
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
      .align(Alignment.Top)
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

      if (GlobalState.canManageCurrentCourse() && this.outlineData?.status === 'published') {
        Button('撤回发布').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).enabled(!this.publishingOutline).fontColor(AppTheme.DANGER)
          .backgroundColor(Color.Transparent).onClick(() => { this.publishDetailOutline('reject'); })
      }
      if (this.canEditOfficialOutline()) {
        Button(this.outlineEditing ? '预览提纲与公式' : '编辑提纲源码')
          .height(36).fontColor(AppTheme.PRIMARY).backgroundColor(AppTheme.PRIMARY_LIGHT)
          .onClick(() => { this.outlineEditing = !this.outlineEditing; })
      }
      if (this.canEditOfficialOutline() && this.outlineEditing) {
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
          Button(this.savingOutline ? '保存中…' : '保存草稿').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          })
            .layoutWeight(1)
            .enabled(!this.savingOutline && !this.publishingOutline)
            .backgroundColor(CLASS_GLASS)
            .fontColor(AppTheme.TEXT_SECONDARY)
            .borderRadius(AppTheme.RADIUS_BTN)
            .onClick(() => {
              this.saveDetailOutline();
            })
          Button(this.publishingOutline ? '发布中…' : '审核发布').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          })
            .layoutWeight(1)
            .enabled(!this.publishingOutline && !this.savingOutline)
            .backgroundColor(AppTheme.SUCCESS)
            .borderRadius(999)
            .onClick(() => {
              this.publishDetailOutline();
            })
        }
        .width('100%')
        Button('退回提纲').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).height(36).fontColor(AppTheme.DANGER).backgroundColor(Color.Transparent)
          .enabled(!this.publishingOutline && !this.savingOutline).onClick(() => { this.publishDetailOutline('reject'); })
      } else {
        Column() {
          MarkdownView({ content: this.outlineData === null ? '暂无提纲，请先生成或等待教师发布。' : this.outlineText })
        }
        .layoutWeight(1)
        .width('100%')
        .padding(AppTheme.SPACE_L)
        .borderRadius(24)
        .backgroundColor(CLASS_GLASS)
        .border({ width: 1.2, color: CLASS_BORDER })
        .shadow({ radius: 22, color: 'rgba(31,62,68,0.10)', offsetX: 0, offsetY: 10 })
        .align(Alignment.Top)
      }
    }
    .layoutWeight(1)
    .height('100%')
  }

  @Builder
  resourcePane() {
    Column({ space: AppTheme.SPACE_M }) {
      Row({ space: 8 }) {
        Text('教师课程资料').fontSize(14).fontColor(AppTheme.TEXT_SECONDARY).layoutWeight(1)
        if (GlobalState.canManageCurrentCourse() && this.selectedResource === null) {
          Button(this.resourceUploading ? '上传中…' : '上传资料').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          })
            .enabled(!this.resourceUploading).fontColor('#FFFFFF').backgroundColor(AppTheme.PRIMARY)
            .onClick(() => { this.uploadResource(); })
        }
        if (this.selectedResource !== null) {
          Button('返回目录').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).fontColor(AppTheme.PRIMARY_DEEP).backgroundColor(AppTheme.PRIMARY_LIGHT)
            .onClick(() => { this.confirmLeave(() => { this.editingResource = false; this.selectedResource = null; }); })
        }
      }.width('100%')
      if (this.selectedResource !== null && GlobalState.canManageCurrentCourse()) {
        Row({ space: 8 }) {
          if (this.editingResource) {
            Button(this.resourceSaving ? '保存中…' : '保存资料').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).layoutWeight(1).height(40).borderRadius(8)
              .enabled(!this.resourceSaving && this.resourceText.trim() !== '').backgroundColor(AppTheme.PRIMARY)
              .onClick(() => { this.saveResource(); })
            Button('取消').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).height(40).borderRadius(8).backgroundColor(AppTheme.PRIMARY_LIGHT).fontColor(AppTheme.PRIMARY_DEEP)
              .enabled(!this.resourceSaving).onClick(() => { this.confirmLeave(() => { this.editingResource = false; }); })
          } else {
            Button('编辑文本').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).height(40).borderRadius(8).backgroundColor(AppTheme.PRIMARY_LIGHT).fontColor(AppTheme.PRIMARY_DEEP)
              .onClick(() => { this.resourceText = this.selectedResource?.content ?? ''; this.editingResource = true; })
          }
        }.width('100%')
      }
      if (this.editingResource) {
        TextArea({ text: this.resourceText }).layoutWeight(1).width('100%').fontSize(15).borderRadius(8)
          .enabled(!this.resourceSaving).onChange((value: string) => { this.resourceText = value; })
      } else {
      Scroll() {
        Column({ space: 10 }) {
          if (this.selectedResource !== null) {
            Text(this.selectedResource!.filename).fontSize(18).fontWeight(FontWeight.Bold).width('100%')
            Text(this.selectedResource!.content ?? '').fontSize(14).lineHeight(23).width('100%')
              .copyOption(CopyOptions.InApp)
          } else if (this.resources.length === 0) {
            Text('教师暂未上传本节课资料').fontColor(AppTheme.TEXT_TERTIARY).width('100%')
          } else {
            ForEach(this.resources, (resource: SessionResource) => {
              Row({ space: 10 }) {
                Text('文').fontSize(13).fontWeight(FontWeight.Bold).fontColor('#FFFFFF')
                  .width(30).height(30).textAlign(TextAlign.Center).borderRadius(6).backgroundColor(CLASS_BLUE)
                Column({ space: 3 }) {
                  Text(resource.filename).fontSize(14).fontWeight(FontWeight.Medium).maxLines(1)
                  Text(`${resource.chars} 字 · 点击查看`).fontSize(11).fontColor(AppTheme.TEXT_TERTIARY)
                }.alignItems(HorizontalAlign.Start).layoutWeight(1)
                Text('›').fontSize(22).fontColor(AppTheme.TEXT_TERTIARY)
              }.width('100%').padding(14).borderRadius(8).backgroundColor('#FFFFFF')
                .onClick(() => { this.openResource(resource); })
            }, (resource: SessionResource) => `${resource.id}`)
          }
        }.width('100%').alignItems(HorizontalAlign.Start)
      }.layoutWeight(1).width('100%').align(Alignment.Top).padding(AppTheme.SPACE_L).borderRadius(24)
        .backgroundColor(CLASS_GLASS).scrollBar(BarState.Auto)
      }
    }.layoutWeight(1).height('100%')
  }

  @Builder
  studentSessionCard(s: CourseSession) {
    Column({ space: 16 }) {
      Row({ space: 10 }) {
        Stack() { SymbolGlyph($r('sys.symbol.doc_text')).fontSize(23).fontColor([AppTheme.PRIMARY]) }
          .width(48).height(48).borderRadius(16).backgroundColor(AppTheme.PRIMARY_LIGHT)
        Text(s.created_at.substring(0, 10)).fontSize(12).fontColor(AppTheme.TEXT_SECONDARY).layoutWeight(1)
        SymbolGlyph($r('sys.symbol.arrow_up_right')).fontSize(14).fontColor([AppTheme.PRIMARY])
      }.width('100%')
      Text(this.sessionTitle(s)).fontSize(21).fontWeight(FontWeight.Bold).fontColor(AppTheme.INK)
        .width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(this.sessionTagLabel(s)).fontSize(12).fontColor(AppTheme.PRIMARY).width('100%')
      Text(GlobalState.isTeacher() ? `${s.resource_count ?? 0} 份资料 · 编辑与发布提纲` :
        `${s.resource_count ?? 0} 份资料 · ${this.personalNotes(s).length} 篇我的笔记`)
        .fontSize(12).fontColor(AppTheme.TEXT_SECONDARY).width('100%')
    }.width('100%').padding(this.compact ? 20 : 24).constraintSize({ minHeight: this.compact ? 180 : 224 })
      .borderRadius(24).backgroundColor(AppTheme.BG_CARD).border({ width: 1, color: '#EDFFFFFF' })
      .shadow({ radius: 18, color: '#12436F9D', offsetY: 6 })
      .stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'card'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'card')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          })
      .onClick(() => { this.compactPane = 'outline'; this.compactOutline = true; this.selectSession(this.indexForSession(s.id)); })
      .accessibilityText(`打开${this.sessionTitle(s)}`)
  }

  @Builder
  studentSessions() {
    Column({ space: 20 }) {
      Column({ space: 8 }) {
        Text(GlobalState.isTeacher() ? '课堂' : '课程').fontSize(this.compact ? 24 : 30).fontWeight(FontWeight.Bold).fontColor(AppTheme.INK)
        Text(`${GlobalState.course?.name ?? ''} · ${this.sessions.length} 次课堂记录`)
          .fontSize(14).fontColor(AppTheme.TEXT_SECONDARY)
      }.width('100%').alignItems(HorizontalAlign.Start)
      if (this.sessions.length === 0) {
        Column({ space: 16 }) {
          SymbolGlyph($r('sys.symbol.folder')).fontSize(44).fontColor([AppTheme.PRIMARY])
          Text(GlobalState.isTeacher() ? '完成课堂录音后，可在这里编辑提纲、审核发布和添加资料。' :
            '老师发布课程提纲后，会显示在这里').fontSize(15).fontColor(AppTheme.TEXT_SECONDARY)
        }.width('100%').padding(40).borderRadius(24).backgroundColor(AppTheme.BG_CARD)
      } else {
        Grid() {
          ForEach(this.sessions, (s: CourseSession) => {
            GridItem() { this.studentSessionCard(s) }
          }, (s: CourseSession) => `${s.id}`)
        }.width('100%').layoutWeight(1).columnsTemplate(this.compact ? '1fr' : '1fr 1fr 1fr')
          .rowsGap(20).columnsGap(20).align(Alignment.Top).scrollBar(BarState.Auto)
      }
    }.width('100%').height('100%').padding(this.compact ? 16 : 28)
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
            this.closeDetail();
          })
        Text(this.currentSession() === null ? '课堂详情' : this.currentSession()!.title)
          .fontSize(AppTheme.FONT_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.INK)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Blank()
        if (!GlobalState.isTeacher()) {
          Button('本节笔记').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).fontColor(AppTheme.PRIMARY_DEEP).backgroundColor(AppTheme.PRIMARY_LIGHT)
            .onClick(() => { this.openSessionNotes(); })
        }
      }
      .width('100%')
      .height(44)

      Row({ space: AppTheme.SPACE_L }) {
          Column() { this.outlinePane() }.layoutWeight(1.3).height('100%')
          Column({ space: 14 }) {
            MobileTabs({ labels: ['课堂转写', '教师资料'], keys: ['transcript', 'resources'], selected: this.compactPane === 'resources' ? 'resources' : 'transcript',
              onSelect: (key: string) => { this.compactPane = key; } })
            Row() {
              if (this.compactPane === 'resources') { this.resourcePane() } else { this.transcriptPane() }
            }.width('100%').layoutWeight(1)
          }.layoutWeight(1).height('100%')
      }
      .layoutWeight(1)
      .width('100%')
      .alignItems(VerticalAlign.Top)
    }
    .width('100%')
    .height('100%')
    .padding({ left: AppTheme.SPACE_XXL, right: AppTheme.SPACE_XXL, top: 28, bottom: AppTheme.SPACE_XXL })
  }

  build() {
    MotionPage({ navigationKey: `${this.detailOpen ? 1 : 0}|${this.detailOpen ? this.currentSession()?.id : 'list'}|${this.compactPane}` }) {
    Stack() {
      if (!this.detailOpen) {
        this.studentSessions()
      } else if (this.compact) {
        Column({ space: 12 }) {
          Row({ space: 8 }) {
            if (this.detailOpen) {
              Button('返回').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).fontSize(14).height(40).borderRadius(AppTheme.RADIUS_BTN)
                .fontColor(AppTheme.PRIMARY_DEEP).backgroundColor(AppTheme.PRIMARY_LIGHT)
                .onClick(() => { this.closeDetail(); })
            }
            Text(this.detailOpen ? this.currentSession()?.title ?? '课堂详情' :
              (GlobalState.isTeacher() ? '课堂' : '课程')).fontSize(20).fontWeight(FontWeight.Bold).layoutWeight(1)
              .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            if (this.detailOpen && !GlobalState.isTeacher()) {
              Button('本节笔记').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).fontColor(AppTheme.PRIMARY_DEEP).backgroundColor(AppTheme.PRIMARY_LIGHT)
                .onClick(() => { this.openSessionNotes(); })
            }
            if (!this.detailOpen && GlobalState.isTeacher()) { Button('录音').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).backgroundColor(AppTheme.PRIMARY).onClick(() => { AppStorage.setOrCreate<string>('classSubPage', 'record'); }) }
          }.width('100%')
          if (this.detailOpen) {
            if (this.compact) {
              MobileTabs({ labels: ['转写', '提纲', '资料'], keys: ['transcript', 'outline', 'resources'],
                selected: this.compactPane, onSelect: (key: string) => {
                  this.compactPane = key; this.compactOutline = key === 'outline';
                } })
            } else {
            Row({ space: 8 }) {
              Button('转写').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).layoutWeight(1).onClick(() => { this.compactPane = 'transcript'; this.compactOutline = false; })
              Button('提纲').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).layoutWeight(1).onClick(() => { this.compactPane = 'outline'; this.compactOutline = true; })
              Button('资料').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).layoutWeight(1).onClick(() => { this.compactPane = 'resources'; this.compactOutline = false; })
            }.width('100%')
            }
            Row() {
              if (this.compactPane === 'resources') { this.resourcePane() }
              else if (this.compactOutline) { this.outlinePane() } else { this.transcriptPane() }
            }.layoutWeight(1).width('100%')
          } else {
            if (this.sessions.length === 0) {
              Text('暂无可见课次').fontColor(AppTheme.TEXT_TERTIARY).layoutWeight(1)
            } else {
              Column({ space: 12 }) {
                Scroll() {
                  Row() {
                    ForEach(this.sessions.slice().reverse(), (session: CourseSession) => {
                      this.timelineNode(session, this.indexForSession(session.id))
                    }, (session: CourseSession) => `${session.id}`)
                  }
                }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off).width('100%').height(180)
                Text(this.sessionTitle(this.currentSession()!)).fontSize(20).fontWeight(FontWeight.Bold).width('100%')
                Text(GlobalState.isTeacher() ? `${this.currentSession()?.resource_count ?? 0} 份教师资料` :
                  `${this.currentSession()?.resource_count ?? 0} 份教师资料 · ${this.personalNotes(this.currentSession()!).length} 篇我的笔记`)
                  .fontSize(13).fontColor(AppTheme.TEXT_SECONDARY).width('100%')
                Button('进入课次').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).width('100%').backgroundColor(AppTheme.PRIMARY)
                  .onClick(() => { this.selectSession(this.selectedIndex); })
                Blank()
              }.layoutWeight(1).width('100%')
            }
          }
        }.width('100%').height('100%').padding(16)
      } else {
      if (this.detailOpen) {
        this.detailView()
      } else {
        this.listView()
      }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.BG_PAGE)
    .onAreaChange((oldArea: Area, newArea: Area) => { this.compact = Number(newArea.width) < 900 || Number(newArea.height) < 550; })
    }
  }
}
