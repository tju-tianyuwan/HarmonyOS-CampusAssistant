import { AppTheme } from '../common/AppTheme';
import { UserInfo } from '../model/Models';
import { Api } from '../service/Api';
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
  @State users: UserInfo[] = [];
  @State loadError: string = '';
  @State showSettings: boolean = false;
  @State workspaceClosing: boolean = false;
  @State libraryReturnActive: boolean = true;
  @State loginPageActive: boolean = true;
  @State recordEntryPressed: boolean = false;
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
    this.loadUsers();
    // 冷启动迁移恢复：EntryAbility 已写入状态，但 @Watch 不触发初始化
    const pending: string | undefined = AppStorage.get<string>('continueRestoreState');
    if (pending !== undefined && pending !== '') {
      this.onContinueRestore();
    }
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

  private stopStageAnimation(): void {
    if (this.stageTimer >= 0) {
      clearTimeout(this.stageTimer);
      this.stageTimer = -1;
    }
  }

  private returnToLibrary(): void {
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
    this.stopStageAnimation();
    CollabManager.stop();
    GlobalState.setCourse(null);
    this.showSettings = false;
    this.workspaceClosing = this.stage === 'workspace';
    this.libraryReturnActive = this.stage === 'library' ? false : this.libraryReturnActive;
    this.stageTimer = setTimeout(() => {
      this.stageTimer = -1;
      GlobalState.user = null;
      this.stage = 'login';
      this.workspaceClosing = false;
      this.libraryReturnActive = true;
      this.loginPageActive = false;
      this.stageTimer = setTimeout(() => {
        this.loginPageActive = true;
        this.stageTimer = -1;
      }, 24);
    }, 240);
  }

  /** 跨端迁移：目标端恢复学习状态 */
  onContinueRestore(): void {
    const state: string | undefined = AppStorage.get<string>('continueRestoreState');
    if (state === undefined || state === '') {
      return;
    }
    AppStorage.setOrCreate<string>('continueRestoreState', '');
    const tab: string = GlobalState.restoreFromJson(state);
    const normalizedTab: string = this.normalizeWorkspaceTab(tab);
    if (GlobalState.user === null) {
      this.stage = 'login';
      this.loginPageActive = true;
      this.libraryReturnActive = true;
      return;
    }
    if (GlobalState.course !== null) {
      this.currentTab = normalizedTab === '' ? 'overview' : normalizedTab;
      this.classSubPage = tab === 'record' ? 'record' : 'list';
      this.noteSubPage = tab === 'ai' ? 'ai' : 'hub';
      this.noteBackTarget = 'hub';
      this.noteReadonly = false;
      this.stage = 'workspace';
      this.loginPageActive = true;
      this.libraryReturnActive = false;
    } else {
      this.stage = 'library';
      this.noteSubPage = 'hub';
      this.loginPageActive = true;
      this.libraryReturnActive = true;
    }
  }

  private async loadUsers(): Promise<void> {
    try {
      this.users = JSON.parse(await Api.get('/auth/users')) as UserInfo[];
      this.loadError = '';
    } catch (e) {
      this.loadError = `无法连接服务端：${(e as Error).message}`;
    }
  }

  private login(u: UserInfo): void {
    this.stopStageAnimation();
    this.loginPageActive = false;
    this.stageTimer = setTimeout(() => {
      this.stageTimer = -1;
      GlobalState.user = u;
      this.stage = 'library';
      this.libraryReturnActive = false;
      GlobalState.updateSnapshot('overview');
      this.stageTimer = setTimeout(() => {
        this.libraryReturnActive = true;
        this.stageTimer = -1;
      }, 24);
    }, 240);
  }

  private avatarColor(u: UserInfo): string {
    return u.role === 'teacher' ? AppTheme.INK : AppTheme.PRIMARY;
  }

  private shouldShowRecordEntry(): boolean {
    return this.currentTab === 'overview' || (this.currentTab === 'class' && this.classSubPage !== 'record');
  }

  private openRecordPage(): void {
    this.currentTab = 'class';
    this.classSubPage = 'record';
    GlobalState.updateSnapshot('class');
  }

  private shouldShowWorkbenchSwitcher(): boolean {
    if (this.currentTab === 'overview' || this.currentTab === 'class' || this.currentTab === 'course_ai' ||
      this.currentTab === 'practice') {
      return true;
    }
    return this.currentTab === 'notes' && this.noteSubPage !== 'ai' && this.noteSubPage !== 'handwriting';
  }

  private switchToOverviewPage(): void {
    this.currentTab = 'overview';
    this.classSubPage = 'list';
    this.noteSubPage = 'hub';
    this.noteReadonly = false;
    GlobalState.updateSnapshot('overview');
  }

  private switchToClassPage(): void {
    this.currentTab = 'class';
    this.classSubPage = 'list';
    GlobalState.updateSnapshot('class');
  }

  private switchToAiPage(): void {
    this.currentTab = 'course_ai';
    GlobalState.updateSnapshot('course_ai');
  }

  private switchToNotesPage(): void {
    this.currentTab = 'notes';
    this.noteSubPage = 'hub';
    this.noteReadonly = false;
    GlobalState.updateSnapshot('notes');
  }

  private switchToPracticePage(): void {
    this.currentTab = 'practice';
    GlobalState.updateSnapshot('practice');
  }

  private backFromWorkspace(): void {
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

  // ============ 登录页 ============
  @Builder
  loginView() {
    Column() {
      Blank().layoutWeight(1)
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width(96)
          .height(96)
          .borderRadius(28)
          .backgroundColor(AppTheme.PRIMARY)
        Text('伴')
          .fontSize(48)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
      }
      .margin({ bottom: AppTheme.SPACE_XL })

      Text('智慧伴学')
        .fontSize(40)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.INK)
      Text('课堂灵感 · 一触即达')
        .fontSize(AppTheme.FONT_SUBTITLE)
        .fontColor(AppTheme.TEXT_TERTIARY)
        .margin({ top: AppTheme.SPACE_S, bottom: AppTheme.SPACE_XXL })

      if (this.loadError !== '') {
        Column({ space: AppTheme.SPACE_M }) {
          Text(this.loadError).fontSize(AppTheme.FONT_CAPTION).fontColor(AppTheme.DANGER)
          Button('重试')
            .fontSize(AppTheme.FONT_BODY)
            .fontColor('#FFFFFF')
            .backgroundColor(AppTheme.PRIMARY)
            .borderRadius(999)
            .onClick(() => {
              this.loadUsers();
            })
        }
      } else {
        Row({ space: AppTheme.SPACE_XL }) {
          ForEach(this.users, (u: UserInfo) => {
            Column({ space: AppTheme.SPACE_M }) {
              Text(u.name.substring(0, 1))
                .fontSize(30)
                .fontColor('#FFFFFF')
                .width(72)
                .height(72)
                .textAlign(TextAlign.Center)
                .borderRadius(36)
                .backgroundColor(this.avatarColor(u))
              Text(u.name)
                .fontSize(AppTheme.FONT_SUBTITLE)
                .fontColor(AppTheme.TEXT_PRIMARY)
              Text(u.role === 'teacher' ? '教师' : '学生')
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor('#FFFFFF')
                .padding({ left: 10, right: 10, top: 3, bottom: 3 })
                .borderRadius(999)
                .backgroundColor(u.role === 'teacher' ? AppTheme.INK : AppTheme.PRIMARY)
            }
            .padding(AppTheme.SPACE_XL)
            .borderRadius(20)
            .backgroundColor(AppTheme.BG_CARD)
            .shadow({ radius: 24, color: 'rgba(0,0,0,0.06)', offsetX: 0, offsetY: 6 })
            .onClick(() => {
              this.login(u);
            })
          }, (u: UserInfo) => `${u.id}`)
        }
        Text('Demo 预置账号 · 点击头像进入')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.TEXT_TERTIARY)
          .margin({ top: AppTheme.SPACE_L })
      }
      Blank().layoutWeight(1)
    }
    .width('100%')
    .height('100%')
    .backgroundColor(AppTheme.BG_WHITE)
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
      .fontSize(AppTheme.FONT_BODY)
      .fontWeight(this.currentTab === key ? FontWeight.Bold : FontWeight.Medium)
      .fontColor(this.currentTab === key ? '#FFFFFF' : AppTheme.TEXT_SECONDARY)
      .width(86)
      .height(38)
      .borderRadius(19)
      .backgroundColor(this.currentTab === key ? AppTheme.PRIMARY : 'transparent')
      .enabled(enabled)
      .onClick(() => {
        onTap();
      })
  }

  @Builder
  workbenchSwitcher() {
    Row() {
      Blank()
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
      }
      .height(50)
      .padding(6)
      .borderRadius(28)
      .backgroundColor('rgba(255,255,255,0.88)')
      .border({ width: 1.2, color: 'rgba(255,255,255,0.94)' })
      .shadow({ radius: 22, color: 'rgba(31,62,68,0.13)', offsetX: 0, offsetY: 8 })
      Blank()
    }
    .width('100%')
    .height(78)
    .padding({ top: AppTheme.SPACE_M })
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
          } else if (this.currentTab === 'review') {
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
      if (this.stage === 'login') {
        Stack() {
          this.loginView()
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
  }
}
