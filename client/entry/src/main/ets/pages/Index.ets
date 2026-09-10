import { AuthPage } from './AuthPage';
import { inputMethod } from '@kit.IMEKit';
import { KnowledgePage } from './KnowledgePage';
import { MeetingPage } from './MeetingPage';
import { AppTheme } from '../common/AppTheme';
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
import { ReviewPage } from './ReviewPage';
import { SettingsPage } from './SettingsPage';
import { CourseAiPage } from './CourseAiPage';
import { PracticePage } from './PracticePage';

interface TabItem {
  key: string;
  label: string;
  teacherOnly: boolean;
  studentOnly: boolean;
}

const TABS: TabItem[] = [
  { key: 'knowledge', label: '知识库', teacherOnly: false, studentOnly: false },
  { key: 'meetings', label: '聊天室', teacherOnly: false, studentOnly: false },
  { key: 'overview', label: '概览', teacherOnly: false, studentOnly: false },
  { key: 'class', label: '课堂', teacherOnly: false, studentOnly: false },
  { key: 'course_ai', label: 'AI', teacherOnly: false, studentOnly: false },
  { key: 'practice', label: '刷题', teacherOnly: false, studentOnly: true },
  { key: 'notes', label: '笔记', teacherOnly: false, studentOnly: false },
  { key: 'review', label: '审核', teacherOnly: true, studentOnly: false }
];

/**
 * 应用壳（Notein 活力风）：
 * 登录 → 课程库（彩色几何封面网格）→ 课程工作台（顶部标签栏 + 内容区）。
 * 协同能力（NFC/局域网互抓/跨端接续）收进设置页开关，默认开启。
 */
@Entry
@Component
struct Index {
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
  @State recordEntryPressed: boolean = false;
  @State restoring: boolean = true;
  private stageTimer: number = -1;

  aboutToAppear(): void {
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
    if (tab === 'practice' && GlobalState.isTeacher()) {
      return 'overview';
    }
    if (tab === 'ai') {
      return 'notes';
    }
    if (tab === 'sessions') {
      return 'class';
    }
    if (tab === 'record') {
      return 'class';
    }
    return tab;
  }

  aboutToDisappear(): void {
    this.stopStageAnimation();
  }

  onBackPress(): boolean {
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
    if (GlobalState.beforeLeaveNote !== null) {
      GlobalState.beforeLeaveNote(() => { this.finishReturnToLibrary(); });
    } else { this.finishReturnToLibrary(); }
  }

  private finishReturnToLibrary(): void {
    if (this.recordingActive) { return; }
    if (this.workspaceClosing) {
      return;
    }
    this.stopStageAnimation();
    this.workspaceClosing = true;
    this.stageTimer = setTimeout(() => {
      this.stageTimer = -1;
      CollabManager.stop();
      GlobalState.setCourse(null);
      this.stage = 'library';
      this.workspaceClosing = false;
      this.libraryReturnActive = false;
      this.stageTimer = setTimeout(() => {
        this.libraryReturnActive = true;
        this.stageTimer = -1;
      }, 24);
    }, 260);
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
    return this.currentTab === 'overview' || (this.currentTab === 'class' && this.classSubPage !== 'record');
  }

  private openRecordPage(): void {
    if (this.recordingActive) { return; }
    this.currentTab = 'class';
    this.classSubPage = 'record';
    GlobalState.updateSnapshot('class');
  }

  private shouldShowWorkbenchSwitcher(): boolean {
    if (this.currentTab === 'knowledge' || this.currentTab === 'meetings' || this.currentTab === 'review') { return true; }
    if (this.currentTab === 'overview' || this.currentTab === 'class' || this.currentTab === 'course_ai' ||
      this.currentTab === 'practice') {
      return true;
    }
    return this.currentTab === 'notes' && this.noteSubPage !== 'ai' && this.noteSubPage !== 'handwriting';
  }

  private switchToOverviewPage(): void {
    if (this.recordingActive) { return; }
    this.currentTab = 'overview';
    this.classSubPage = 'list';
    this.noteSubPage = 'hub';
    this.noteReadonly = false;
    GlobalState.updateSnapshot('overview');
  }

  private switchToClassPage(): void {
    if (this.recordingActive) { return; }
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
    GlobalState.updateSnapshot('notes');
  }

  private switchToPracticePage(): void {
    if (this.recordingActive) { return; }
    this.currentTab = 'practice';
    GlobalState.updateSnapshot('practice');
  }

  private backFromWorkspace(): void {
    if (GlobalState.beforeLeaveNote !== null) {
      GlobalState.beforeLeaveNote(() => { this.noteSubPage = this.noteBackTarget; });
      return;
    }
    if (this.recordingActive) { return; }
    if (this.currentTab === 'class' || this.currentTab === 'course_ai' || this.currentTab === 'practice' ||
      this.currentTab === 'notes') {
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
          if ((!item.teacherOnly || GlobalState.isTeacher()) && (!item.studentOnly || !GlobalState.isTeacher())) {
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
      Button('‹')
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
      Button(GlobalState.user === null ? '' : GlobalState.user.name.substring(0, 1))
        .fontSize(AppTheme.FONT_BODY)
        .fontColor('#FFFFFF')
        .width(44)
        .height(44)
        .borderRadius(22)
        .backgroundColor(GlobalState.isTeacher() ? AppTheme.INK : AppTheme.PRIMARY)
        .shadow({ radius: 14, color: 'rgba(17,17,17,0.08)', offsetX: 0, offsetY: 4 })
        .onClick(() => {
          this.showSettings = true;
        })
    }
    .width('100%')
    .height(72)
    .padding({ left: AppTheme.SPACE_XL, right: AppTheme.SPACE_XL, top: AppTheme.SPACE_M })
    .position({ x: 0, y: 0 })
    .zIndex(30)
    .hitTestBehavior(HitTestMode.Transparent)
  }

  @Builder
  islandButton(key: string, label: string, enabled: boolean, onTap: () => void) {
    Button(label)
      .fontSize(14)
      .padding({ left: 8, right: 8 })
      .fontWeight(this.currentTab === key ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.currentTab === key ? '#FFFFFF' : AppTheme.TEXT_SECONDARY)
      .width(70)
      .height(38)
      .borderRadius(19)
      .backgroundColor(this.currentTab === key ? AppTheme.PRIMARY : 'transparent')
      .enabled(enabled && !this.recordingActive)
      .onClick(() => {
        onTap();
      })
  }

  @Builder
  workbenchSwitcher() {
    Row() {
      Blank()
      Scroll() {
      Row({ space: 4 }) {
        this.islandButton('overview', '概览', true, (): void => {
          this.switchToOverviewPage();
        })
        this.islandButton('class', '课堂', true, (): void => {
          this.switchToClassPage();
        })
        this.islandButton('course_ai', 'AI', true, (): void => {
          this.switchToAiPage();
        })
        if (!GlobalState.isTeacher()) {
          this.islandButton('practice', '刷题', true, (): void => {
            this.switchToPracticePage();
          })
        }
        this.islandButton('notes', '笔记', true, (): void => {
          this.switchToNotesPage();
        })
        this.islandButton('knowledge', '知识库', true, (): void => { this.currentTab = 'knowledge'; })
        this.islandButton('meetings', '聊天室', true, (): void => { this.currentTab = 'meetings'; })
        if (GlobalState.canManageCurrentCourse()) {
          this.islandButton('review', '审核', true, (): void => { this.currentTab = 'review'; })
        }
      }
      .height(50)
      .padding(6)
      .borderRadius(28)
      .backgroundColor('rgba(255,255,255,0.88)')
      .border({ width: 1.2, color: 'rgba(255,255,255,0.94)' })
      .shadow({ radius: 22, color: 'rgba(31,62,68,0.13)', offsetX: 0, offsetY: 8 })
      }.scrollable(ScrollDirection.Horizontal).scrollBar(BarState.Off)
        .constraintSize({ maxWidth: this.compactLayout ? '100%' : '78%' }).height(56)
      Blank()
    }
    .width('100%')
    .height(this.compactLayout ? 128 : 78)
    .padding({ top: this.compactLayout ? 68 : AppTheme.SPACE_M })
    .zIndex(40)
  }

  @Builder
  recordEntryButton() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width(82)
        .height(82)
        .borderRadius(41)
        .linearGradient({
          angle: 145,
          colors: [
            ['#8EF2EF', 0],
            ['#57C8EE', 0.38],
            ['#5B8AF7', 0.72],
            ['#7556E5', 1]
          ]
        })
        .border({ width: 1.5, color: 'rgba(255,255,255,0.92)' })
        .shadow({
          radius: this.recordEntryPressed ? 16 : 28,
          color: this.recordEntryPressed ? 'rgba(43,80,180,0.28)' : 'rgba(91,112,232,0.34)',
          offsetX: 0,
          offsetY: this.recordEntryPressed ? 7 : 13
        })
        .clip(true)
      Column()
        .width(32)
        .height(20)
        .borderRadius(14)
        .rotate({ angle: -22 })
        .backgroundColor(this.recordEntryPressed ? 'rgba(255,255,255,0.13)' : 'rgba(255,255,255,0.24)')
        .position({ x: 25, y: 18 })
      Column()
        .width(13)
        .height(13)
        .borderRadius(7)
        .backgroundColor(this.recordEntryPressed ? 'rgba(255,255,255,0.12)' : 'rgba(255,255,255,0.20)')
        .position({ x: 55, y: 25 })
      Column({ space: 0 }) {
        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width(24)
            .height(32)
            .borderRadius(12)
            .backgroundColor(this.recordEntryPressed ? 'rgba(255,255,255,0.90)' : '#FFFFFF')
          Column()
            .width(6)
            .height(18)
            .borderRadius(4)
            .backgroundColor('rgba(117,138,239,0.28)')
            .margin({ left: 8 })
        }
        .width(32)
        .height(34)
        Column()
          .width(5)
          .height(12)
          .backgroundColor(this.recordEntryPressed ? 'rgba(255,255,255,0.90)' : '#FFFFFF')
        Column()
          .width(25)
          .height(5)
          .borderRadius(3)
          .backgroundColor(this.recordEntryPressed ? 'rgba(255,255,255,0.90)' : '#FFFFFF')
      }
      .width(42)
      .height(56)
      .alignItems(HorizontalAlign.Center)
      .justifyContent(FlexAlign.Center)
    }
    .width(92)
    .height(92)
    .margin({ right: AppTheme.SPACE_XL, bottom: AppTheme.SPACE_XL })
    .translate({ x: 0, y: this.recordEntryPressed ? 5 : 0 })
    .scale({
      x: this.recordEntryPressed ? 0.94 : 1,
      y: this.recordEntryPressed ? 0.94 : 1
    })
    .animation({ duration: this.recordEntryPressed ? 90 : 180, curve: Curve.EaseOut })
    .zIndex(20)
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.recordEntryPressed = true;
      } else if (event.type === TouchType.Up) {
        this.recordEntryPressed = false;
      }
    })
    .onClick(() => {
      this.recordEntryPressed = false;
      this.openRecordPage();
    })
  }

  @Builder
  workspaceView() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      Column() {
        if (this.shouldShowWorkbenchSwitcher()) {
          this.workbenchSwitcher()
        } else {
          Blank()
            .height(78)
        }
        Column() {
          if (this.currentTab === 'overview') {
            OverviewPage({
              courseId: GlobalState.courseId(),
              userId: GlobalState.userId()
            })
          } else if (this.currentTab === 'class') {
            if (this.classSubPage === 'record') {
              RecordPage()
            } else {
              ClassPage()
            }
          } else if (this.currentTab === 'course_ai') {
            CourseAiPage()
          } else if (this.currentTab === 'practice' && !GlobalState.isTeacher()) {
            PracticePage()
          } else if (this.currentTab === 'notes') {
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
          } else if (this.currentTab === 'knowledge') {
            KnowledgePage()
          } else if (this.currentTab === 'meetings') {
            MeetingPage()
          } else if (this.currentTab === 'review' && GlobalState.canManageCurrentCourse()) {
            ReviewPage()
          }
        }
        .layoutWeight(1)
        .width('100%')
      }
      .width('100%')
      .height('100%')

      this.workspaceTopControls()

      if (this.shouldShowRecordEntry()) {
        this.recordEntryButton()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.BG_SUNKEN)
    .opacity(this.workspaceClosing ? 0 : 1)
    .translate({ x: 0, y: this.workspaceClosing ? 18 : 0 })
    .scale({
      x: this.workspaceClosing ? 0.96 : 1,
      y: this.workspaceClosing ? 0.96 : 1
    })
    .animation({ duration: 260, curve: Curve.EaseOut })
  }

  build() {
    Stack() {
      if (this.restoring) {
        LoadingProgress().width(40).height(40)
      } else if (this.stage === 'login') {
        Stack() {
          AuthPage({ onAuthenticated: (response: AuthResponse) => { this.completeAuth(response); } })
        }
        .width('100%')
        .height('100%')
        .opacity(this.loginPageActive ? 1 : 0)
        .translate({ x: 0, y: this.loginPageActive ? 0 : 18 })
        .scale({
          x: this.loginPageActive ? 1 : 0.985,
          y: this.loginPageActive ? 1 : 0.985
        })
        .animation({ duration: 240, curve: Curve.EaseOut })
      } else if (this.stage === 'library') {
        Stack() {
          LibraryPage({
            onEnterCourse: () => {
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
        .opacity(this.libraryReturnActive ? 1 : 0)
        .translate({ x: 0, y: this.libraryReturnActive ? 0 : 24 })
        .scale({
          x: this.libraryReturnActive ? 1 : 0.985,
          y: this.libraryReturnActive ? 1 : 0.985
        })
        .animation({ duration: 300, curve: Curve.EaseOut })
      } else {
        this.workspaceView()
      }

      if (this.showSettings) {
        SettingsPage({
          onClose: () => {
            this.showSettings = false;
          },
          onLogout: () => {
            this.logoutToLogin();
          }
        })
      }
    }
    .width('100%')
    .height('100%')
    .onAreaChange((oldArea: Area, newArea: Area) => { this.compactLayout = Number(newArea.width) < 760; })
  }
}
