import { TouchMotion } from '../common/TouchMotion';
import { MotionPage } from '../common/components/MotionPage';
import { MobileTabs } from '../common/components/MobileTabs';
import { FloatingRecordButton } from '../common/components/FloatingRecordButton';
import { AuthPage } from './AuthPage';
import { CrystalStudyPage } from './CrystalStudyPage';
import { StudyBackdrop } from '../common/components/StudyBackdrop';
import { inputMethod } from '@kit.IMEKit';
import { MaterialsPage } from './MaterialsPage';
import { MeetingPage } from './MeetingPage';
import { LearningTheme as AppTheme } from '../common/LearningTheme';
import { AuthResponse, ClassCourse, UserInfo } from '../model/Models';
import { Api } from '../service/Api';
import { SessionStore } from '../service/SessionStore';
import { GlobalState } from '../service/GlobalState';
import { CollabManager } from '../service/collab/CollabManager';
import { LibraryPage } from './LibraryPage';
import { OverviewPage } from './OverviewPage';
import { RecordPage } from './RecordPage';
import { ClassPage } from './ClassPage';
import { AiNotePage } from './AiNotePage';
import { NotePage } from './NotePage';
import { ClassNotesPage } from './ClassNotesPage';
import { PersonalNotePage } from './PersonalNotePage';
import { HandwritingNotePage } from './HandwritingNotePage';
import { SettingsPage } from './SettingsPage';
import { CourseAiPage } from './CourseAiPage';
import { PracticePage } from './PracticePage';
import { MobileLayout } from '../common/MobileLayout';

interface TabItem {
  key: string;
  label: string;
  teacherOnly: boolean;
  studentOnly: boolean;
}

const TABS: TabItem[] = [
  { key: 'class', label: '课程', teacherOnly: false, studentOnly: false },
  { key: 'course_ai', label: 'AI数据', teacherOnly: true, studentOnly: false },
  { key: 'ai_meeting', label: 'AI学习小组', teacherOnly: false, studentOnly: false },
  { key: 'practice', label: '刷题', teacherOnly: false, studentOnly: true },
  { key: 'notes', label: '笔记', teacherOnly: false, studentOnly: true },
  { key: 'materials', label: '资料', teacherOnly: true, studentOnly: false }
];

/**
 * 应用壳（Notein 活力风）：
 * 登录 → 课程库（彩色几何封面网格）→ 课程工作台（顶部标签栏 + 内容区）。
 * 协同能力（NFC/局域网互抓/跨端接续）收进设置页开关，默认开启。
 */
@Entry
@Component
struct Index {
  @StorageLink('reduceMotion') reduceMotion: boolean = false;
  @StorageLink('currentTab') currentTab: string = 'overview';
  @StorageLink('classSubPage') classSubPage: string = 'list'; // list | record
  @StorageLink('noteSubPage') noteSubPage: string = 'hub'; // hub | class | personal | ai | handwriting
  @StorageLink('continueRestoreTick') @Watch('onContinueRestore') restoreTick: number = 0;
  @State stage: string = 'login'; // login | library | workspace
  @State noteBackTarget: string = 'hub';
  @State selectedNoteId: number = -1;
  @State createNoteOnOpen: boolean = false;
  @State noteReadonly: boolean = false;
  @StorageLink('authExpiredTick') @Watch('onAuthExpired') authExpiredTick: number = 0;
  @StorageLink('recordingActive') recordingActive: boolean = false;
  @State showSettings: boolean = false;
  @State compactLayout: boolean = false;
  @State workspaceClosing: boolean = false;
  @State libraryReturnActive: boolean = true;
  @State loginPageActive: boolean = true;
  @State restoring: boolean = true;
  @State crystalDetailOpen: boolean = false;
  @State homeSessionId: number = -1;
  @State materialSessionId: number = -1;
  @State materialPane: string = 'outline';
  @State materialResourceId: number = -1;
  @State recordStartRequested: boolean = false;
  private stageTimer: number = -1;

  aboutToAppear(): void {
    if (this.currentTab === 'knowledge' || this.currentTab === 'course_outlines' || this.currentTab === 'review') {
      this.currentTab = 'materials';
    }
    if (this.currentTab === 'meetings') {
      this.currentTab = 'ai_meeting';
    }
    if (this.currentTab === 'record') {
      this.currentTab = 'class';
      this.classSubPage = 'record';
    }
    if (this.currentTab === 'sessions') {
      this.currentTab = 'class';
      this.classSubPage = 'list';
    }
    if (this.currentTab === 'ai') {
      this.currentTab = 'notes';
      this.noteSubPage = 'ai';
      this.noteBackTarget = 'hub';
      this.noteReadonly = false;
    }
    this.restoreAccount().finally(() => { this.restoring = false; });
  }

  private normalizeWorkspaceTab(tab: string): string {
    if (['knowledge', 'course_outlines', 'review', 'materials'].includes(tab)) {
      return GlobalState.isTeacher() && GlobalState.canManageCurrentCourse() ? 'materials' : 'overview';
    }
    if (GlobalState.isTeacher() && ['notes', 'ai', 'practice'].includes(tab)) { return 'overview'; }
    if (tab === 'ai') { return 'notes'; }
    if (tab === 'meetings' || tab === 'group_chat') { return 'ai_meeting'; }
    if (tab === 'sessions' || tab === 'record') { return 'class'; }
    return tab;
  }

  aboutToDisappear(): void {
    this.stopStageAnimation();
  }

  onBackPress(): boolean {
    if (this.crystalDetailOpen && !this.showSettings) {
      this.crystalDetailOpen = false;
      return true;
    }
    if (AppStorage.get<boolean>('accountInputFocused') === true) {
      AppStorage.setOrCreate<boolean>('accountInputFocused', false);
      inputMethod.getController().hideTextInput().catch(() => {});
      return true;
    }
    if ((AppStorage.get<number>('keyboardHeight') ?? 0) > 0) { return false; }
    if (this.recordingActive) { return true; }
    if (this.showSettings) { this.showSettings = false; return true; }
    if (GlobalState.beforeLeaveNote !== null) {
      GlobalState.beforeLeaveNote(() => { this.noteSubPage = this.noteBackTarget; });
      return true;
    }
    if (GlobalState.closeOutlineDetail !== null) {
      GlobalState.closeOutlineDetail();
      return true;
    }
    if (GlobalState.closeClassDetail !== null) {
      GlobalState.closeClassDetail();
      return true;
    }
    if (this.stage === 'workspace' && this.currentTab !== 'overview') {
      this.switchToOverviewPage();
      return true;
    }
    if (this.stage === 'workspace') { this.returnToLibrary(); return true; }
    return false;
  }

  private stopStageAnimation(): void {
    if (this.stageTimer >= 0) {
      clearTimeout(this.stageTimer);
      this.stageTimer = -1;
    }
  }

  private returnToLibrary(): void {
    if (GlobalState.closeOutlineDetail !== null) {
      GlobalState.closeOutlineDetail();
      return;
    }
    if (GlobalState.beforeLeaveNote !== null) {
      GlobalState.beforeLeaveNote(() => { this.finishReturnToLibrary(); });
    } else { this.finishReturnToLibrary(); }
  }

  private finishReturnToLibrary(): void {
    if (this.recordingActive) { return; }
    this.stopStageAnimation();
    this.crystalDetailOpen = false;
    this.homeSessionId = -1;
    CollabManager.stop();
    GlobalState.setCourse(null);
    this.stage = 'library';
    this.workspaceClosing = false;
    this.libraryReturnActive = true;
  }

  private rootMotionKey(): string {
    if (this.restoring) { return '0|restore'; }
    if (this.stage === 'login') { return '0|login'; }
    if (this.stage === 'library') { return '1|library'; }
    return this.currentTab === 'overview' ? '2|home' : '3|workspace';
  }

  private contentMotionKey(): string {
    const order = ['overview', 'class', 'course_ai', 'ai_meeting', 'practice', 'notes', 'materials'];
    let depth = Math.max(0, order.indexOf(this.currentTab)) * 10;
    if (this.currentTab === 'notes') {
      depth += this.noteSubPage === 'hub' ? 0 : ['class', 'personal'].includes(this.noteSubPage) ? 1 : 2;
    }
    if (this.currentTab === 'class' && this.classSubPage === 'record') { depth++; }
    if (this.currentTab === 'materials' && this.materialSessionId > 0) { depth++; }
    return `${depth}|${this.currentTab}|${this.noteSubPage}|${this.classSubPage}|${this.materialSessionId}`;
  }

  private logoutToLogin(): void {
    if (this.recordingActive) { return; }
    Api.post('/auth/logout').catch(() => {});
    this.onAuthExpired();
  }

  private onAuthExpired(): void {
    this.stopStageAnimation();
    CollabManager.stop();
    Api.setAccessToken('');
    SessionStore.save(Api.BASE_URL, '').catch(() => {});
    GlobalState.clearSession();
    this.stage = 'login';
    this.showSettings = false;
    this.crystalDetailOpen = false;
    this.homeSessionId = -1;
    this.workspaceClosing = false;
    this.loginPageActive = true;
    this.libraryReturnActive = true;
  }

  private completeAuth(response: AuthResponse): void {
    Api.setAccessToken(response.access_token);
    SessionStore.save(Api.BASE_URL, response.access_token).catch(() => {});
    GlobalState.accessToken = response.access_token;
    GlobalState.user = response.user;
    GlobalState.setCourse(null);
    this.stage = 'library';
    this.libraryReturnActive = true;
    this.loginPageActive = true;
  }

  private async restoreAccount(): Promise<void> {
    const initialToken = Api.token;
    const initialServer = Api.BASE_URL;
    const saved = await SessionStore.load();
    if (Api.token !== initialToken || Api.BASE_URL !== initialServer) { return; }
    if (Api.token === '' && saved !== null) {
      Api.BASE_URL = saved.server;
      Api.setAccessToken(saved.token);
    }
    if (Api.token === '') { return; }
    const token = Api.token;
    try {
      const user = JSON.parse(await Api.get('/auth/me')) as UserInfo;
      if (Api.token !== token) { return; }
      GlobalState.user = user;
      GlobalState.accessToken = token;
      this.stage = 'library';
      await this.onContinueRestore();
    } catch (e) { if (Api.token === token) { this.onAuthExpired(); } }
  }

  async onContinueRestore(): Promise<void> {
    if (this.recordingActive) { return; }
    const state = AppStorage.get<string>('continueRestoreState') ?? '';
    if (state === '' || GlobalState.user === null || Api.token === '') { return; }
    AppStorage.setOrCreate<string>('continueRestoreState', '');
    const token = Api.token;
    const tab = GlobalState.restoreFromJson(state);
    if (tab === '') { return; }
    const requested = GlobalState.courseId();
    try {
      const courses = JSON.parse(await Api.get(`/courses?user_id=${GlobalState.userId()}`)) as ClassCourse[];
      if (Api.token !== token) { return; }
      GlobalState.setCourse(courses.find((course: ClassCourse) => course.id === requested) ?? null);
      const candidate = this.normalizeWorkspaceTab(tab);
      this.currentTab = TABS.some((item: TabItem) => item.key === candidate &&
        (!item.teacherOnly || GlobalState.canManageCurrentCourse()) &&
        (!item.studentOnly || !GlobalState.isTeacher())) ? candidate : 'overview';
      this.classSubPage = 'list';
      this.noteSubPage = 'hub';
      this.stage = GlobalState.course === null ? 'library' : 'workspace';
    } catch (e) { this.onAuthExpired(); }
  }

  private shouldShowRecordEntry(): boolean {
    return !GlobalState.isTeacher() && this.currentTab !== 'course_ai';
  }

  private hasTeacherRecordEntry(): boolean {
    return !this.restoring && GlobalState.isTeacher() && this.stage === 'workspace' &&
      GlobalState.course !== null && !(this.currentTab === 'class' && this.classSubPage === 'record');
  }

  private openRecordPage(startImmediately: boolean = false): void {
    if (this.recordingActive) { return; }
    if (GlobalState.beforeLeaveClass !== null) {
      GlobalState.beforeLeaveClass(() => { this.performOpenRecordPage(startImmediately); });
    } else { this.performOpenRecordPage(startImmediately); }
  }

  private performOpenRecordPage(startImmediately: boolean = false): void {
    if (!GlobalState.isTeacher()) {
      this.switchToAiPage();
      return;
    }
    if (GlobalState.course === null || this.recordingActive ||
      (this.currentTab === 'class' && this.classSubPage === 'record')) { return; }
    this.crystalDetailOpen = false;
    this.recordStartRequested = startImmediately;
    this.currentTab = 'class';
    this.classSubPage = 'record';
    GlobalState.updateSnapshot('class');
  }

  private shouldShowWorkbenchSwitcher(): boolean {
    return this.currentTab !== 'overview';
  }

  private switchToOverviewPage(): void {
    if (this.recordingActive) { return; }
    GlobalState.currentSessionId = -1;
    this.homeSessionId = -1;
    this.currentTab = 'overview';
    this.classSubPage = 'list';
    this.noteSubPage = 'hub';
    this.noteReadonly = false;
    GlobalState.updateSnapshot('overview');
  }

  private switchToClassPage(): void {
    if (this.recordingActive) { return; }
    this.homeSessionId = -1;
    this.currentTab = 'class';
    this.classSubPage = 'list';
    GlobalState.updateSnapshot('class');
  }

  private switchToAiPage(): void {
    if (this.recordingActive) { return; }
    this.currentTab = 'course_ai';
    GlobalState.updateSnapshot('course_ai');
  }

  private switchToNotesPage(): void {
    if (this.recordingActive) { return; }
    this.currentTab = 'notes';
    this.noteSubPage = 'hub';
    this.noteReadonly = false;
    GlobalState.pendingNoteSessionId = -1;
    GlobalState.updateSnapshot('notes');
  }

  private switchToPracticePage(): void {
    if (this.recordingActive) { return; }
    this.currentTab = 'practice';
    GlobalState.updateSnapshot('practice');
  }

  private backFromWorkspace(): void {
    if (GlobalState.closeOutlineDetail !== null) {
      GlobalState.closeOutlineDetail();
      return;
    }
    if (GlobalState.beforeLeaveNote !== null) {
      GlobalState.beforeLeaveNote(() => { this.noteSubPage = this.noteBackTarget; });
      return;
    }
    if (GlobalState.closeClassDetail !== null) {
      GlobalState.closeClassDetail();
      return;
    }
    if (this.recordingActive) { return; }
    if (this.currentTab !== 'overview') {
      GlobalState.currentSessionId = -1;
      this.currentTab = 'overview';
      this.classSubPage = 'list';
      this.noteSubPage = 'hub';
      this.noteReadonly = false;
      GlobalState.updateSnapshot('overview');
      return;
    }
    this.returnToLibrary();
  }

  // ============ 顶部标签栏 ============
  @Builder
  topTab(item: TabItem) {
    Column({ space: 5 }) {
      Text(item.label)
        .fontSize(AppTheme.FONT_BODY)
        .fontWeight(this.currentTab === item.key ? FontWeight.Bold : FontWeight.Normal)
        .fontColor(this.currentTab === item.key ? AppTheme.INK : AppTheme.TEXT_TERTIARY)
      Column()
        .width(20)
        .height(3)
        .borderRadius(2)
        .backgroundColor(this.currentTab === item.key ? AppTheme.PRIMARY : 'transparent')
    }
    .onClick(() => {
      if (this.recordingActive) { return; }
      this.currentTab = item.key;
      if (item.key === 'class') {
        this.classSubPage = 'list';
      }
      if (item.key === 'notes') {
        this.noteSubPage = 'hub';
        this.noteBackTarget = 'hub';
        this.noteReadonly = false;
      }
      GlobalState.updateSnapshot(item.key);
    })
  }

  @Builder
  topBar() {
    Row({ space: AppTheme.SPACE_XL }) {
      Row({ space: AppTheme.SPACE_S }) {
        Text('‹')
          .fontSize(26)
          .fontColor(AppTheme.INK)
          .onClick(() => {
            this.returnToLibrary();
          })
        Column()
          .width(10)
          .height(10)
          .borderRadius(3)
          .backgroundColor(GlobalState.course === null ? AppTheme.PRIMARY : AppTheme.cover(GlobalState.courseId()))
        Text(GlobalState.course === null ? '智慧伴学' : GlobalState.course.name)
          .fontSize(AppTheme.FONT_SUBTITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.INK)
      }

      Blank()

      Row({ space: AppTheme.SPACE_XL }) {
        ForEach(TABS, (item: TabItem) => {
          if ((!item.teacherOnly || (GlobalState.isTeacher() && GlobalState.canManageCurrentCourse())) &&
            (!item.studentOnly || !GlobalState.isTeacher())) {
            this.topTab(item)
          }
        }, (item: TabItem) => item.key)
      }

      Blank()

      Row({ space: AppTheme.SPACE_M }) {
        Text('⚙')
          .fontSize(20)
          .fontColor(AppTheme.TEXT_SECONDARY)
          .onClick(() => {
            this.showSettings = true;
          })
        Text(GlobalState.user === null ? '' : GlobalState.user.name.substring(0, 1))
          .fontSize(AppTheme.FONT_BODY)
          .fontColor('#FFFFFF')
          .width(36)
          .height(36)
          .textAlign(TextAlign.Center)
          .borderRadius(18)
          .backgroundColor(GlobalState.isTeacher() ? AppTheme.INK : AppTheme.PRIMARY)
      }
    }
    .width('100%')
    .height(AppTheme.TOPBAR_HEIGHT)
    .padding({ left: AppTheme.SPACE_XL, right: AppTheme.SPACE_XL })
    .backgroundColor(AppTheme.BG_CARD)
    .border({ width: { bottom: 1 }, color: AppTheme.DIVIDER })
  }

  @Builder
  workspaceTopControls() {
    Row() {
      Button('‹').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          })
        .fontSize(28)
        .fontColor(AppTheme.INK)
        .width(44)
        .height(44)
        .borderRadius(22)
        .backgroundColor(AppTheme.BG_CARD)
        .shadow({ radius: 14, color: 'rgba(17,17,17,0.06)', offsetX: 0, offsetY: 4 })
        .onClick(() => {
          this.backFromWorkspace();
        })
      Blank()
      if (this.compactLayout) {
        Text(GlobalState.course?.name ?? '').fontSize(14).fontWeight(FontWeight.Medium)
          .fontColor(AppTheme.TEXT_SECONDARY).layoutWeight(1).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        Blank()
      }
      Button(GlobalState.user === null ? '' : GlobalState.user.name.substring(0, 1)).stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          })
        .fontSize(AppTheme.FONT_BODY)
        .fontColor('#FFFFFF')
        .width(44)
        .height(44)
        .borderRadius(22)
        .backgroundColor(AppTheme.PRIMARY)
        .shadow({ radius: 14, color: 'rgba(17,17,17,0.08)', offsetX: 0, offsetY: 4 })
        .onClick(() => {
          this.showSettings = true;
        })
    }
    .width('100%')
    .height(this.compactLayout ? 60 : 72)
    .padding({ left: this.compactLayout ? 12 : AppTheme.SPACE_XL,
      right: this.compactLayout ? 12 : AppTheme.SPACE_XL, top: this.compactLayout ? 6 : AppTheme.SPACE_M })
    .position({ x: 0, y: 0 })
    .zIndex(30)
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  islandButton(key: string, label: string, enabled: boolean, onTap: () => void) {
    Button(label).stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          })
      .fontSize(14)
      .padding({ left: 8, right: 8 })
      .fontWeight(this.currentTab === key ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.currentTab === key ? '#FFFFFF' : AppTheme.TEXT_SECONDARY)
      .width(label.length >= 5 ? 92 : label.length >= 4 ? 82 : 70)
      .height(38)
      .borderRadius(19)
      .backgroundColor(this.currentTab === key ? AppTheme.PRIMARY : 'transparent')
      .enabled(enabled && !this.recordingActive)
      .onClick(() => {
        onTap();
      })
  }

  private navigateWorkbench(key: string): void {
    if (this.recordingActive) { return; }
    if (GlobalState.beforeLeaveClass !== null) {
      GlobalState.beforeLeaveClass(() => { this.performNavigateWorkbench(key); });
    } else { this.performNavigateWorkbench(key); }
  }

  private performNavigateWorkbench(key: string): void {
    if (key === 'class') { this.switchToClassPage(); }
    else if (key === 'course_ai') { this.switchToAiPage(); }
    else if (key === 'practice') { this.switchToPracticePage(); }
    else if (key === 'notes') { this.switchToNotesPage(); }
    else { this.currentTab = key; GlobalState.updateSnapshot(key); }
    this.materialSessionId = -1;
  }

  @Builder
  workbenchSwitcher() {
    if (this.compactLayout) {
      Column() { this.workbenchTabs() }.width('100%').margin({ top: 60, bottom: 8 })
    } else {
      Row() {
        Blank()
        Column() { this.workbenchTabs() }.width(400)
        Blank()
      }.width('100%').height(78).padding({ top: AppTheme.SPACE_M }).zIndex(40)
    }
  }

  @Builder
  workbenchTabs() {
    MobileTabs({
      labels: GlobalState.isTeacher() ? ['课堂', 'AI数据', 'AI学习小组', '资料'] : ['课程', 'AI学习小组', '刷题', '笔记'],
      keys: GlobalState.isTeacher() ? ['class', 'course_ai', 'ai_meeting', 'materials'] : ['class', 'ai_meeting', 'practice', 'notes'],
      selected: this.currentTab, interactive: !this.recordingActive, solid: true,
      disabledKeys: GlobalState.canManageCurrentCourse() ? [] : ['materials'],
      onSelect: (key: string) => { this.navigateWorkbench(key); }
    })
  }

  @Builder
  workspaceView() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      StudyBackdrop()
      Column() {
        if (this.shouldShowWorkbenchSwitcher()) {
          this.workbenchSwitcher()
        } else {
          Blank()
            .height(this.compactLayout ? 60 : 78)
        }
        Column() {
        MotionPage({ navigationKey: this.contentMotionKey(), tabNavigation: true }) {
          if (this.currentTab === 'overview') {
            OverviewPage({
              courseId: GlobalState.courseId(),
              userId: GlobalState.userId()
            })
          } else if (this.currentTab === 'class') {
            if (this.classSubPage === 'record') {
              RecordPage({ startOnAppear: this.recordStartRequested,
                onStartRequestConsumed: () => { this.recordStartRequested = false; } })
            } else {
              ClassPage({ initialSessionId: this.homeSessionId, initialPane: this.homeSessionId > 0 ? 'outline' : 'transcript',
                onExitDetail: () => { this.switchToOverviewPage(); } })
            }
          } else if (this.currentTab === 'course_ai') {
            CourseAiPage()
          } else if (this.currentTab === 'practice' && !GlobalState.isTeacher()) {
            PracticePage()
          } else if (this.currentTab === 'notes' && !GlobalState.isTeacher()) {
            if (this.noteSubPage === 'class') {
              ClassNotesPage({
                onBack: () => {
                  this.noteSubPage = 'hub';
                },
                onOpenAiNote: (noteId: number) => {
                  this.noteBackTarget = 'class';
                  this.selectedNoteId = noteId;
                  this.createNoteOnOpen = false;
                  this.noteReadonly = true;
                  this.noteSubPage = 'ai';
                },
                onOpenHandwritingNote: (noteId: number) => {
                  this.noteBackTarget = 'class';
                  this.selectedNoteId = noteId;
                  this.createNoteOnOpen = false;
                  this.noteReadonly = true;
                  this.noteSubPage = 'handwriting';
                }
              })
            } else if (this.noteSubPage === 'personal') {
              PersonalNotePage({
                onBack: () => {
                  this.noteSubPage = 'hub';
                },
                onCreateAiNote: () => {
                  this.noteBackTarget = 'personal';
                  this.selectedNoteId = -1;
                  this.createNoteOnOpen = true;
                  this.noteReadonly = false;
                  this.noteSubPage = 'ai';
                },
                onCreateHandwritingNote: () => {
                  this.noteBackTarget = 'personal';
                  this.selectedNoteId = -1;
                  this.createNoteOnOpen = true;
                  this.noteReadonly = false;
                  this.noteSubPage = 'handwriting';
                },
                onOpenAiNote: (noteId: number) => {
                  this.noteBackTarget = 'personal';
                  this.selectedNoteId = noteId;
                  this.createNoteOnOpen = false;
                  this.noteReadonly = false;
                  this.noteSubPage = 'ai';
                },
                onOpenHandwritingNote: (noteId: number) => {
                  this.noteBackTarget = 'personal';
                  this.selectedNoteId = noteId;
                  this.createNoteOnOpen = false;
                  this.noteReadonly = false;
                  this.noteSubPage = 'handwriting';
                }
              })
            } else if (this.noteSubPage === 'ai') {
              AiNotePage({
                initialNoteId: this.selectedNoteId,
                createOnAppear: this.createNoteOnOpen,
                readOnly: this.noteReadonly,
                onBack: () => {
                  this.createNoteOnOpen = false;
                  this.noteReadonly = false;
                  this.noteSubPage = this.noteBackTarget;
                }
              })
            } else if (this.noteSubPage === 'handwriting') {
              HandwritingNotePage({
                initialNoteId: this.selectedNoteId,
                createOnAppear: this.createNoteOnOpen,
                readOnly: this.noteReadonly,
                onBack: () => {
                  this.createNoteOnOpen = false;
                  this.noteReadonly = false;
                  this.noteSubPage = this.noteBackTarget;
                }
              })
            } else {
              NotePage({
                onOpenClassNotes: () => {
                  this.noteReadonly = false;
                  this.noteSubPage = 'class';
                },
                onOpenPersonalNote: () => {
                  this.noteReadonly = false;
                  this.noteSubPage = 'personal';
                }
              })
            }
          } else if (this.currentTab === 'materials' && GlobalState.isTeacher() && GlobalState.canManageCurrentCourse()) {
            if (this.materialSessionId > 0) {
              ClassPage({ initialSessionId: this.materialSessionId, initialPane: this.materialPane,
                initialResourceId: this.materialResourceId, onExitDetail: () => { this.materialSessionId = -1; } })
            } else {
              MaterialsPage({ onOpen: (sessionId: number, pane: string, resourceId: number) => {
                this.materialPane = pane; this.materialResourceId = resourceId; this.materialSessionId = sessionId;
              } })
            }
          } else if (this.currentTab === 'ai_meeting') {
            MeetingPage({ roomType: 'ai_meeting' })
          }
        }
        }.layoutWeight(1)
        .width('100%')
        if (this.compactLayout && this.shouldShowRecordEntry()) {
          Row() {
            Text(GlobalState.course?.name ?? '').fontSize(12).fontColor(AppTheme.TEXT_SECONDARY)
              .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).layoutWeight(1)
            Button('AI').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).width(64).height(40).fontSize(16).fontWeight(FontWeight.Bold).borderRadius(AppTheme.RADIUS_BTN)
              .padding(0)
              .fontColor('#FFFFFF').backgroundColor(AppTheme.PRIMARY)
              .accessibilityText('课程 AI 助手').onClick(() => { this.openRecordPage(); })
          }.width('100%').height(52).padding({ left: 16, right: 12 }).backgroundColor('#FFFFFF')
        }
      }
      .width('100%')
      .height('100%')
      .padding({ bottom: this.hasTeacherRecordEntry() ? 80 : 0 })

      this.workspaceTopControls()

      if (this.shouldShowRecordEntry() && !this.compactLayout) {
          Button('AI 助手').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).fontSize(16).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
            .height(48).padding({ left: 22, right: 22 }).borderRadius(16)
            .backgroundColor(AppTheme.PRIMARY).margin({ right: 24, bottom: 24 })
            .shadow({ radius: 12, color: 'rgba(21,90,165,0.16)', offsetY: 4 })
            .accessibilityText('课程 AI 助手')
            .onClick(() => { this.openRecordPage(); })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.BG_SUNKEN)
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      MotionPage({ navigationKey: this.rootMotionKey() }) {
      if (this.restoring) {
        LoadingProgress().width(40).height(40)
      } else if (this.stage === 'login') {
        Stack() {
          AuthPage({ onAuthenticated: (response: AuthResponse) => { this.completeAuth(response); } })
        }
        .width('100%')
        .height('100%')
      } else if (this.stage === 'library') {
        Stack() {
          StudyBackdrop()
          LibraryPage({
            onEnterCourse: () => {
              this.crystalDetailOpen = false;
              this.homeSessionId = -1;
              this.currentTab = 'overview';
              this.classSubPage = 'list';
              this.noteSubPage = 'hub';
              this.noteBackTarget = 'hub';
              this.noteReadonly = false;
              this.workspaceClosing = false;
              this.libraryReturnActive = false;
              this.stage = 'workspace';
              GlobalState.updateSnapshot('overview');
              CollabManager.start(); // 协同能力默认开启：进课程自动待命
            },
            onLogout: () => {
              this.logoutToLogin();
            },
            onOpenSettings: () => {
              this.showSettings = true;
            }
          })
        }
        .width('100%')
        .height('100%')
      } else {
        if (this.currentTab === 'overview') {
          CrystalStudyPage({ detailOpen: $crystalDetailOpen,
            onRecord: () => { this.openRecordPage(); },
            onClose: () => { this.returnToLibrary(); },
            onSettings: () => { this.showSettings = true; },
            onNavigate: (key: string) => {
              this.crystalDetailOpen = false;
              this.navigateWorkbench(key);
            },
            onOpenLesson: (id: number) => {
              this.switchToClassPage();
              this.homeSessionId = id;
            } })
        } else { this.workspaceView() }
      }
      }
      if (this.hasTeacherRecordEntry() && !this.showSettings && !this.crystalDetailOpen && !this.recordingActive) {
        FloatingRecordButton({ onRecord: () => { this.openRecordPage(true); } })
          .margin({ right: 18, bottom: 16 })
      }
      if (this.showSettings) {
        SettingsPage({
          onClose: () => {
            this.showSettings = false;
          },
          onLogout: () => {
            this.logoutToLogin();
          }
        }).transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ x: 32 }))
          .animation({ duration: this.reduceMotion ? 0 : 240, curve: TouchMotion.enter() }))
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.BG_PAGE)
    .onAreaChange((oldArea: Area, newArea: Area) => { this.compactLayout = Number(newArea.width) < 760; })
  }
}
