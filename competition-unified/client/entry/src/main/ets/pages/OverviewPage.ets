import { promptAction } from '@kit.ArkUI';
import { pasteboard } from '@kit.BasicServicesKit';
import { AppTheme } from '../common/AppTheme';
import { CourseWorkspaceStats } from '../model/Models';
import { Api } from '../service/Api';
import { GlobalState } from '../service/GlobalState';

const BG_CANVAS: string = '#F2F7F6';
const INK_PANEL: string = '#121818';
const INK_SOFT: string = '#1B2A28';
const GLASS_WHITE: string = 'rgba(255,255,255,0.82)';
const GLASS_STRONG: string = 'rgba(255,255,255,0.92)';
const GLASS_BORDER: string = 'rgba(255,255,255,0.90)';
const SHADOW_LOW: string = 'rgba(31,62,68,0.10)';
const SHADOW_MID: string = 'rgba(24,58,74,0.16)';
const PRIMARY_WASH: string = 'rgba(5,206,145,0.16)';
const CYAN: string = '#12BFE8';
const BLUE: string = '#3F7DFF';
const AMBER: string = '#FFB84D';
const CORAL: string = '#FF6F61';
const VIOLET: string = '#7A63F3';

/**
 * 课程主页：课程信息 + 统计 + 页面入口。
 */
@Component
export struct OverviewPage {
  @StorageLink('currentTab') @Watch('onCurrentTabChanged') currentTab: string = 'overview';
  @StorageLink('classSubPage') classSubPage: string = 'list';
  @StorageLink('noteSubPage') noteSubPage: string = 'hub';
  @Prop courseId: number = -1;
  @Prop userId: number = -1;
  @State officialLessonCount: number = 0;
  @State classNoteCount: number = 0;
  @State personalNoteCount: number = 0;
  @State pageReady: boolean = false;
  @State statsReady: boolean = false;
  @State entriesReady: boolean = false;
  @State atlasPulse: boolean = false;
  @State pressedEntry: string = '';
  @State pressedAtlasNode: string = '';
  @State invitePressed: boolean = false;
  private introTimer: number = -1;
  private statsTimer: number = -1;
  private entriesTimer: number = -1;
  private atlasTimer: number = -1;
  private statsSyncTimer: number = -1;
  private loadedCourseId: number = -1;

  aboutToAppear(): void {
    this.startStatsSync();
    this.startIntro();
    this.startAtlasMotion();
  }

  aboutToDisappear(): void {
    this.stopMotion();
  }

  onCurrentTabChanged(): void {
    if (this.currentTab === 'overview') {
      this.startStatsSync();
    } else {
      this.stopStatsSync();
    }
  }

  private startStatsSync(): void {
    this.load();
    if (this.statsSyncTimer >= 0) {
      return;
    }
    this.statsSyncTimer = setInterval(() => {
      this.load();
    }, 3000);
  }

  private stopStatsSync(): void {
    if (this.statsSyncTimer >= 0) {
      clearInterval(this.statsSyncTimer);
      this.statsSyncTimer = -1;
    }
  }

  private resetStats(): void {
    this.officialLessonCount = 0;
    this.classNoteCount = 0;
    this.personalNoteCount = 0;
  }

  private startIntro(): void {
    this.pageReady = false;
    this.statsReady = false;
    this.entriesReady = false;
    this.introTimer = setTimeout(() => {
      this.pageReady = true;
      this.introTimer = -1;
    }, 24);
    this.statsTimer = setTimeout(() => {
      this.statsReady = true;
      this.statsTimer = -1;
    }, 150);
    this.entriesTimer = setTimeout(() => {
      this.entriesReady = true;
      this.entriesTimer = -1;
    }, 280);
  }

  private startAtlasMotion(): void {
    if (this.atlasTimer >= 0) {
      return;
    }
    this.atlasTimer = setInterval(() => {
      this.atlasPulse = !this.atlasPulse;
    }, 1600);
  }

  private stopMotion(): void {
    if (this.introTimer >= 0) {
      clearTimeout(this.introTimer);
      this.introTimer = -1;
    }
    if (this.statsTimer >= 0) {
      clearTimeout(this.statsTimer);
      this.statsTimer = -1;
    }
    if (this.entriesTimer >= 0) {
      clearTimeout(this.entriesTimer);
      this.entriesTimer = -1;
    }
    if (this.atlasTimer >= 0) {
      clearInterval(this.atlasTimer);
      this.atlasTimer = -1;
    }
    this.stopStatsSync();
  }

  private courseName(): string {
    return GlobalState.course === null ? '' : GlobalState.course.name;
  }

  private courseMeta(): string {
    if (GlobalState.course === null) {
      return '';
    }
    return `${GlobalState.course.class_name} · ${GlobalState.course.teacher_name ?? ''}`;
  }

  private inviteCode(): string {
    return GlobalState.course === null ? '' : GlobalState.course.invite_code;
  }

  private toast(msg: string): void {
    promptAction.showToast({ message: msg });
  }

  private async load(): Promise<void> {
    const courseId: number = this.courseId;
    const userId: number = this.userId;
    if (courseId <= 0 || userId <= 0) {
      this.loadedCourseId = -1;
      this.resetStats();
      return;
    }
    if (this.loadedCourseId !== courseId) {
      this.loadedCourseId = courseId;
      this.resetStats();
    }
    try {
      const raw: string = await Api.get(`/courses/${courseId}/stats?user_id=${userId}`);
      const stats: CourseWorkspaceStats = JSON.parse(raw) as CourseWorkspaceStats;
      if (this.courseId !== courseId || stats.class_course_id !== courseId) {
        return;
      }
      this.officialLessonCount = stats.official_lesson_count;
      this.classNoteCount = stats.class_note_count;
      this.personalNoteCount = stats.personal_note_count;
    } catch (e) {
      // Keep the last confirmed backend snapshot and retry on the next sync tick.
    }
  }

  private copyInvite(): void {
    if (GlobalState.course === null) {
      return;
    }
    const data: pasteboard.PasteData =
      pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, GlobalState.course.invite_code);
    pasteboard.getSystemPasteboard().setData(data);
    this.toast('邀请码已复制');
  }

  private openClassPage(): void {
    this.classSubPage = 'list';
    this.currentTab = 'class';
    GlobalState.updateSnapshot('class');
  }

  private openAiPage(): void {
    this.currentTab = 'course_ai';
    GlobalState.updateSnapshot('course_ai');
  }

  private openPracticePage(): void {
    this.currentTab = 'practice';
    GlobalState.updateSnapshot('practice');
  }

  private openNotesPage(): void {
    this.noteSubPage = 'hub';
    this.currentTab = 'notes';
    GlobalState.updateSnapshot('notes');
  }

  private openRecordPage(): void {
    this.classSubPage = 'record';
    this.currentTab = 'class';
    GlobalState.updateSnapshot('class');
  }

  private openAtlasNode(target: string): void {
    if (target === 'capture') {
      this.openRecordPage();
    } else if (target === 'outline') {
      this.openClassPage();
    } else if (target === 'ai') {
      this.openAiPage();
    } else if (target === 'note') {
      this.openNotesPage();
    }
  }

  @Builder
  pageAtmosphere() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 30,
          colors: [
            ['#F7FCFA', 0],
            [BG_CANVAS, 0.48],
            ['#EEF4FF', 1]
          ]
        })
      Column()
        .width(520)
        .height(880)
        .borderRadius(80)
        .rotate({ angle: -18 })
        .linearGradient({
          angle: 120,
          colors: [
            ['rgba(5,206,145,0.13)', 0],
            ['rgba(18,191,232,0.08)', 0.56],
            ['rgba(255,255,255,0.02)', 1]
          ]
        })
        .position({ x: -210, y: -140 })
        .translate({ x: this.atlasPulse ? 12 : 0, y: this.atlasPulse ? 0 : 10 })
        .animation({ duration: 1300, curve: Curve.EaseOut })
      Column()
        .width(760)
        .height(760)
        .borderRadius(90)
        .rotate({ angle: 14 })
        .linearGradient({
          angle: 70,
          colors: [
            ['rgba(122,99,243,0.11)', 0],
            ['rgba(63,125,255,0.07)', 0.58],
            ['rgba(255,255,255,0.04)', 1]
          ]
        })
        .position({ x: 1160, y: -80 })
        .translate({ x: this.atlasPulse ? -16 : 0, y: this.atlasPulse ? 8 : 0 })
        .animation({ duration: 1300, curve: Curve.EaseOut })
      Column()
        .width(1180)
        .height(230)
        .borderRadius(46)
        .rotate({ angle: -3 })
        .backgroundColor('rgba(255,255,255,0.52)')
        .position({ x: 360, y: 690 })
      Column()
        .width('100%')
        .height(1)
        .backgroundColor('rgba(255,255,255,0.70)')
        .position({ x: 0, y: 200 })
      Column()
        .width('100%')
        .height(1)
        .backgroundColor('rgba(255,255,255,0.48)')
        .position({ x: 0, y: 515 })
      Column()
        .width(1)
        .height('100%')
        .backgroundColor('rgba(255,255,255,0.42)')
        .position({ x: 600, y: 0 })
      Column()
        .width(1)
        .height('100%')
        .backgroundColor('rgba(255,255,255,0.32)')
        .position({ x: 1250, y: 0 })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  graphEdge(width: number, angle: number, centerX: number, centerY: number, color: string) {
    Column()
      .width(width)
      .height(2)
      .borderRadius(1)
      .rotate({ angle: angle })
      .backgroundColor(color)
      .position({ x: centerX - width / 2, y: centerY - 1 })
  }

  @Builder
  graphNode(label: string, sub: string, color: string, x: number, y: number, size: number, active: boolean,
    target: string) {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width(size)
        .height(size)
        .borderRadius(size / 2)
        .backgroundColor(active ? color : 'rgba(255,255,255,0.10)')
        .border({ width: 1.4, color: active ? 'rgba(255,255,255,0.70)' : 'rgba(255,255,255,0.22)' })
        .shadow({
          radius: active ? 24 : 10,
          color: active ? color : 'rgba(0,0,0,0.10)',
          offsetX: 0,
          offsetY: active ? 9 : 4
        })
      Column({ space: 2 }) {
        Text(label)
          .fontSize(size > 58 ? 19 : 15)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
        Text(sub)
          .fontSize(9)
          .fontColor('rgba(255,255,255,0.72)')
      }
      .alignItems(HorizontalAlign.Center)
    }
    .width(size)
    .height(size)
    .position({ x: x, y: y })
    .scale({
      x: this.pressedAtlasNode === target ? 0.94 : (active && this.atlasPulse ? 1.05 : 1),
      y: this.pressedAtlasNode === target ? 0.94 : (active && this.atlasPulse ? 1.05 : 1)
    })
    .animation({ duration: this.pressedAtlasNode === target ? 90 : 800, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressedAtlasNode = target;
      } else if (event.type === TouchType.Up) {
        this.pressedAtlasNode = '';
      }
    })
    .onClick(() => {
      this.pressedAtlasNode = '';
      this.openAtlasNode(target);
    })
  }

  @Builder
  knowledgeAtlas() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .borderRadius(28)
        .backgroundColor('rgba(255,255,255,0.08)')
        .border({ width: 1.2, color: 'rgba(255,255,255,0.18)' })
      Text('知识流')
        .fontSize(12)
        .fontWeight(FontWeight.Bold)
        .fontColor('rgba(255,255,255,0.74)')
        .position({ x: 28, y: 24 })
      Text('从录音到思考，再到 AI 与笔记')
        .fontSize(11)
        .fontColor('rgba(255,255,255,0.48)')
        .position({ x: 28, y: 45 })
      this.graphEdge(61, 16.7, 148, 144, 'rgba(18,191,232,0.48)')
      this.graphEdge(55, -22.7, 257, 139, 'rgba(5,206,145,0.46)')
      this.graphEdge(50, 40.8, 361, 154, 'rgba(122,99,243,0.42)')
      this.graphNode('录', 'CAPTURE', CYAN, 56, 94, 64, true, 'capture')
      this.graphNode('思', 'THINK', AMBER, 176, 132, 58, this.officialLessonCount > 0 || this.atlasPulse,
        'outline')
      this.graphNode('问', 'AI', BLUE, 280, 80, 70, true, 'ai')
      this.graphNode('记', 'NOTE', AppTheme.PRIMARY, 372, 160, 62,
        this.classNoteCount + this.personalNoteCount > 0 || this.atlasPulse, 'note')
      Column({ space: 5 }) {
        Row({ space: 6 }) {
          Column()
            .width(8)
            .height(8)
            .borderRadius(4)
            .backgroundColor(AppTheme.PRIMARY)
          Text('课程知识已连接')
            .fontSize(11)
            .fontColor('rgba(255,255,255,0.76)')
        }
        Row({ space: 6 }) {
          Column()
            .width(8)
            .height(8)
            .borderRadius(4)
            .backgroundColor(BLUE)
          Text('AI 仅依据本课程作答')
            .fontSize(11)
            .fontColor('rgba(255,255,255,0.60)')
        }
      }
      .position({ x: 30, y: 202 })
    }
    .width(500)
    .height(260)
  }

  @Builder
  inviteChip() {
    Row({ space: 8 }) {
      Text('邀请码')
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(this.invitePressed ? '#121818' : 'rgba(255,255,255,0.62)')
      Text(this.inviteCode())
        .fontSize(AppTheme.FONT_BODY)
        .fontWeight(FontWeight.Bold)
        .fontColor(this.invitePressed ? '#121818' : '#FFFFFF')
      Text('⧉')
        .fontSize(AppTheme.FONT_BODY)
        .fontColor(this.invitePressed ? '#121818' : AppTheme.PRIMARY)
    }
    .height(42)
    .padding({ left: 16, right: 16 })
    .borderRadius(999)
    .backgroundColor(this.invitePressed ? '#FFFFFF' : 'rgba(255,255,255,0.10)')
    .border({ width: 1, color: this.invitePressed ? '#FFFFFF' : 'rgba(255,255,255,0.18)' })
    .shadow({
      radius: this.invitePressed ? 10 : 22,
      color: this.invitePressed ? 'rgba(255,255,255,0.12)' : 'rgba(5,206,145,0.18)',
      offsetX: 0,
      offsetY: this.invitePressed ? 4 : 9
    })
    .scale({ x: this.invitePressed ? 0.97 : 1, y: this.invitePressed ? 0.97 : 1 })
    .animation({ duration: 130, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.invitePressed = true;
      } else if (event.type === TouchType.Up) {
        this.invitePressed = false;
      }
    })
    .onClick(() => {
      this.invitePressed = false;
      this.copyInvite();
    })
  }

  @Builder
  heroStat(kind: string, label: string, color: string) {
    Row({ space: 8 }) {
      Text(kind === 'official' ? `${this.officialLessonCount}` :
        (kind === 'class' ? `${this.classNoteCount}` : `${this.personalNoteCount}`))
        .fontSize(25)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
      Text(label)
        .fontSize(11)
        .fontColor('rgba(255,255,255,0.62)')
    }
    .height(44)
    .padding({ left: 14, right: 14 })
    .borderRadius(16)
    .backgroundColor('rgba(255,255,255,0.09)')
    .border({ width: 1, color: color })
  }

  @Builder
  heroPanel() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .borderRadius(34)
        .linearGradient({
          angle: 122,
          colors: [
            [INK_PANEL, 0],
            [INK_SOFT, 0.48],
            ['#243E39', 1]
          ]
        })
      Column()
        .width(540)
        .height(380)
        .borderRadius(72)
        .rotate({ angle: -13 })
        .linearGradient({
          angle: 112,
          colors: [
            ['rgba(5,206,145,0.18)', 0],
            ['rgba(18,191,232,0.12)', 0.56],
            ['rgba(255,255,255,0.03)', 1]
          ]
        })
        .position({ x: -140, y: -86 })
        .translate({ x: this.atlasPulse ? 10 : 0, y: this.atlasPulse ? 0 : 8 })
        .animation({ duration: 1300, curve: Curve.EaseOut })
      Column()
        .width(520)
        .height(250)
        .borderRadius(48)
        .rotate({ angle: 9 })
        .linearGradient({
          angle: 62,
          colors: [
            ['rgba(63,125,255,0.18)', 0],
            ['rgba(122,99,243,0.12)', 0.60],
            ['rgba(255,255,255,0.02)', 1]
          ]
        })
        .position({ x: 930, y: -70 })
        .translate({ x: this.atlasPulse ? -12 : 0, y: this.atlasPulse ? 8 : 0 })
        .animation({ duration: 1300, curve: Curve.EaseOut })
      Row() {
        Column({ space: AppTheme.SPACE_L }) {
          Row({ space: 8 }) {
            Text('COURSE ATLAS')
              .fontSize(11)
              .fontWeight(FontWeight.Bold)
              .fontColor('#121818')
              .padding({ left: 12, right: 12, top: 5, bottom: 5 })
              .borderRadius(999)
              .backgroundColor(AppTheme.PRIMARY)
            Text(GlobalState.isTeacher() ? '教师工作台' : '学习工作台')
              .fontSize(11)
              .fontColor('rgba(255,255,255,0.68)')
              .padding({ left: 12, right: 12, top: 5, bottom: 5 })
              .borderRadius(999)
              .backgroundColor('rgba(255,255,255,0.09)')
          }
          Column({ space: AppTheme.SPACE_S }) {
            Text(this.courseName())
              .fontSize(54)
              .fontWeight(FontWeight.Bold)
              .fontColor('#FFFFFF')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
            Text(this.courseMeta())
              .fontSize(AppTheme.FONT_BODY)
              .fontColor('rgba(255,255,255,0.58)')
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
          .alignItems(HorizontalAlign.Start)
          Row({ space: 10 }) {
            this.heroStat('official', '官方课时', 'rgba(255,184,77,0.46)')
            this.heroStat('class', '班级笔记', 'rgba(5,206,145,0.46)')
            this.heroStat('personal', '个人笔记', 'rgba(63,125,255,0.46)')
          }
          Row({ space: AppTheme.SPACE_M }) {
            this.inviteChip()
            Row({ space: 7 }) {
              Column()
                .width(8)
                .height(8)
                .borderRadius(4)
                .backgroundColor(AppTheme.PRIMARY)
              Text('实时同步')
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor('rgba(255,255,255,0.58)')
            }
            .height(42)
            .padding({ left: 14, right: 14 })
            .borderRadius(999)
            .backgroundColor('rgba(255,255,255,0.08)')
            .border({ width: 1, color: 'rgba(255,255,255,0.14)' })
          }
        }
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Start)

        this.knowledgeAtlas()
      }
      .width('100%')
      .height('100%')
      .padding({ left: 42, right: 32, top: 24, bottom: 24 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(312)
    .borderRadius(34)
    .clip(true)
    .border({ width: 1.4, color: 'rgba(255,255,255,0.16)' })
    .shadow({ radius: 42, color: 'rgba(18,24,24,0.22)', offsetX: 0, offsetY: 20 })
    .opacity(this.pageReady ? 1 : 0)
    .translate({ x: 0, y: this.pageReady ? 0 : 28 })
    .scale({ x: this.pageReady ? 1 : 0.985, y: this.pageReady ? 1 : 0.985 })
    .animation({ duration: 420, curve: Curve.EaseOut })
  }

  @Builder
  practiceChoiceBadge(label: string, color: string, active: boolean) {
    Text(label)
      .fontSize(AppTheme.FONT_BODY)
      .fontWeight(FontWeight.Bold)
      .fontColor(active ? '#FFFFFF' : AppTheme.TEXT_SECONDARY)
      .width(42)
      .height(42)
      .textAlign(TextAlign.Center)
      .borderRadius(21)
      .backgroundColor(active ? color : 'rgba(18,24,24,0.06)')
      .border({ width: 1, color: active ? color : 'rgba(18,24,24,0.08)' })
      .shadow({ radius: active ? 14 : 0, color: active ? color : 'transparent', offsetX: 0, offsetY: 6 })
  }

  @Builder
  practiceEntryBanner() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .borderRadius(28)
        .linearGradient({
          angle: 104,
          colors: [
            ['rgba(255,255,255,0.96)', 0],
            ['#F2FFFA', 0.48],
            ['#EEF4FF', 1]
          ]
        })
      Column()
        .width(390)
        .height(132)
        .borderRadius(36)
        .rotate({ angle: -8 })
        .backgroundColor('rgba(5,206,145,0.10)')
        .position({ x: -90, y: -54 })
      Column()
        .width(340)
        .height(118)
        .borderRadius(32)
        .rotate({ angle: 9 })
        .backgroundColor('rgba(63,125,255,0.10)')
        .position({ x: 1130, y: 36 })
      Row({ space: AppTheme.SPACE_L }) {
        Stack({ alignContent: Alignment.Center }) {
          Column()
            .width(68)
            .height(68)
            .borderRadius(22)
            .rotate({ angle: -7 })
            .backgroundColor('rgba(255,111,97,0.14)')
          Text('练')
            .fontSize(28)
            .fontWeight(FontWeight.Bold)
            .fontColor(CORAL)
        }
        .width(82)
        .height(82)

        Column({ space: 6 }) {
          Row({ space: 8 }) {
            Text('AI PRACTICE')
              .fontSize(10)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.INK)
              .padding({ left: 10, right: 10, top: 4, bottom: 4 })
              .borderRadius(999)
              .backgroundColor(AppTheme.PRIMARY)
            Text('学生专属')
              .fontSize(10)
              .fontColor(CORAL)
          }
          Row({ space: 12 }) {
            Text('AI 刷题')
              .fontSize(30)
              .fontWeight(FontWeight.Bold)
              .fontColor(AppTheme.INK)
            Text('围绕课程重点自动组题，作答后即时查看解析')
              .fontSize(AppTheme.FONT_BODY)
              .fontColor(AppTheme.TEXT_SECONDARY)
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)

        Row({ space: 10 }) {
          this.practiceChoiceBadge('A', CORAL, true)
          this.practiceChoiceBadge('B', BLUE, false)
          this.practiceChoiceBadge('C', AppTheme.PRIMARY, false)
        }

        Row({ space: 8 }) {
          Text('开始刷题')
            .fontSize(AppTheme.FONT_BODY)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
          Text('→')
            .fontSize(AppTheme.FONT_BODY)
            .fontWeight(FontWeight.Bold)
            .fontColor('#FFFFFF')
        }
        .height(44)
        .padding({ left: 18, right: 18 })
        .borderRadius(22)
        .backgroundColor(AppTheme.INK)
      }
      .width('100%')
      .height('100%')
      .padding({ left: 26, right: 24 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height(122)
    .clip(true)
    .borderRadius(28)
    .border({ width: 1.2, color: GLASS_BORDER })
    .shadow({
      radius: this.pressedEntry === 'practiceBanner' ? 16 : 28,
      color: this.pressedEntry === 'practiceBanner' ? SHADOW_LOW : 'rgba(63,125,255,0.14)',
      offsetX: 0,
      offsetY: this.pressedEntry === 'practiceBanner' ? 6 : 12
    })
    .opacity(this.entriesReady ? 1 : 0)
    .translate({ x: 0, y: this.entriesReady ? (this.pressedEntry === 'practiceBanner' ? 3 : 0) : 24 })
    .scale({
      x: this.pressedEntry === 'practiceBanner' ? 0.986 : (this.entriesReady ? 1 : 0.99),
      y: this.pressedEntry === 'practiceBanner' ? 0.986 : (this.entriesReady ? 1 : 0.99)
    })
    .animation({ duration: this.pressedEntry === 'practiceBanner' ? 90 : 360, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressedEntry = 'practiceBanner';
      } else if (event.type === TouchType.Up) {
        this.pressedEntry = '';
      }
    })
    .onClick(() => {
      this.pressedEntry = '';
      this.openPracticePage();
    })
  }

  @Builder
  metricSymbol(kind: string, color: string) {
    if (kind === 'official') {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width(52)
          .height(52)
          .borderRadius(18)
          .backgroundColor('rgba(255,184,77,0.18)')
          .rotate({ angle: -8 })
        Column({ space: 5 }) {
          Column()
            .width(28)
            .height(5)
            .borderRadius(3)
            .backgroundColor(color)
          Column()
            .width(20)
            .height(5)
            .borderRadius(3)
            .backgroundColor(color)
            .opacity(0.55)
          Column()
            .width(26)
            .height(5)
            .borderRadius(3)
            .backgroundColor(color)
            .opacity(0.34)
        }
      }
      .width(62)
      .height(62)
    } else if (kind === 'class') {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width(56)
          .height(56)
          .borderRadius(28)
          .backgroundColor(PRIMARY_WASH)
        Column()
          .width(34)
          .height(34)
          .borderRadius(17)
          .border({ width: 4, color: color })
        Column()
          .width(12)
          .height(12)
          .borderRadius(6)
          .backgroundColor(color)
      }
      .width(62)
      .height(62)
    } else {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width(52)
          .height(52)
          .borderRadius(16)
          .backgroundColor('rgba(63,125,255,0.14)')
          .rotate({ angle: 9 })
        Column()
          .width(34)
          .height(44)
          .borderRadius(8)
          .backgroundColor('#FFFFFF')
          .border({ width: 1.4, color: 'rgba(63,125,255,0.28)' })
        Column()
          .width(24)
          .height(4)
          .borderRadius(2)
          .backgroundColor(color)
          .position({ x: 19, y: 24 })
        Column()
          .width(18)
          .height(4)
          .borderRadius(2)
          .backgroundColor(color)
          .opacity(0.42)
          .position({ x: 19, y: 34 })
      }
      .width(62)
      .height(62)
    }
  }

  @Builder
  metricCard(num: string, label: string, kind: string, color: string, index: number) {
    Row({ space: AppTheme.SPACE_M }) {
      this.metricSymbol(kind, color)
      Column({ space: AppTheme.SPACE_XS }) {
        Text(num)
          .fontSize(38)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.INK)
        Text(label)
          .fontSize(AppTheme.FONT_BODY)
          .fontColor(AppTheme.TEXT_TERTIARY)
      }
      .alignItems(HorizontalAlign.Start)
      Blank()
      Column({ space: 6 }) {
        Text(index === 0 ? '课时库' : (index === 1 ? '班级共创' : '个人资产'))
          .fontSize(11)
          .fontColor(color)
          .fontWeight(FontWeight.Medium)
        Text(index === 0 ? 'PUBLISHED' : (index === 1 ? 'SHARED' : 'PRIVATE'))
          .fontSize(9)
          .fontColor(AppTheme.TEXT_TERTIARY)
      }
      .alignItems(HorizontalAlign.End)
    }
    .layoutWeight(1)
    .height(124)
    .padding({ left: 22, right: 22 })
    .borderRadius(28)
    .backdropBlur(18)
    .backgroundColor(GLASS_WHITE)
    .border({ width: 1.2, color: GLASS_BORDER })
    .shadow({ radius: 26, color: SHADOW_LOW, offsetX: 0, offsetY: 10 })
    .opacity(this.statsReady ? 1 : 0)
    .translate({ x: 0, y: this.statsReady ? 0 : 18 + index * 5 })
    .animation({ duration: 330 + index * 80, curve: Curve.EaseOut })
  }

  @Builder
  courseIllustration() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width(74)
        .height(148)
        .borderRadius(26)
        .backgroundColor('rgba(255,184,77,0.16)')
        .position({ x: 118, y: -8 })
      Column()
        .width(4)
        .height(126)
        .borderRadius(2)
        .backgroundColor('rgba(26,26,26,0.18)')
        .position({ x: 44, y: 14 })
      ForEach([0, 1, 2], (i: number) => {
        Row({ space: 10 }) {
          Column()
            .width(18)
            .height(18)
            .borderRadius(9)
            .backgroundColor(i === 0 ? AMBER : (i === 1 ? CORAL : AppTheme.INK))
          Column({ space: 5 }) {
            Column()
              .width(84 - i * 12)
              .height(8)
              .borderRadius(4)
              .backgroundColor('rgba(26,26,26,0.16)')
            Column()
              .width(54 + i * 10)
              .height(6)
              .borderRadius(3)
              .backgroundColor('rgba(26,26,26,0.08)')
          }
        }
        .position({ x: 36, y: 20 + i * 42 })
      }, (i: number) => `${i}`)
    }
    .width(210)
    .height(150)
  }

  @Builder
  aiIllustration() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width(148)
        .height(148)
        .borderRadius(34)
        .rotate({ angle: 12 })
        .backgroundColor('rgba(63,125,255,0.12)')
        .position({ x: 40, y: 0 })
      this.graphEdge(44, 29.3, 97, 90, 'rgba(63,125,255,0.34)')
      this.graphEdge(42, 122.3, 168, 73, 'rgba(5,206,145,0.34)')
      this.graphEdge(30, -18.4, 99, 129, 'rgba(122,99,243,0.32)')
      this.smallNode('Q', BLUE, 38, 48, 42)
      this.smallNode('AI', VIOLET, 112, 86, 58)
      this.smallNode('K', AppTheme.PRIMARY, 170, 20, 38)
      this.smallNode('S', CYAN, 52, 122, 34)
    }
    .width(220)
    .height(150)
  }

  @Builder
  smallNode(label: string, color: string, x: number, y: number, size: number) {
    Text(label)
      .fontSize(size > 48 ? 17 : 13)
      .fontWeight(FontWeight.Bold)
      .fontColor('#FFFFFF')
      .width(size)
      .height(size)
      .textAlign(TextAlign.Center)
      .borderRadius(size / 2)
      .backgroundColor(color)
      .border({ width: 1.4, color: 'rgba(255,255,255,0.80)' })
      .shadow({ radius: 18, color: color, offsetX: 0, offsetY: 7 })
      .position({ x: x, y: y })
      .scale({ x: this.atlasPulse ? 1.03 : 1, y: this.atlasPulse ? 1.03 : 1 })
      .animation({ duration: 900, curve: Curve.EaseOut })
  }

  @Builder
  noteIllustration() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width(120)
        .height(92)
        .borderRadius(20)
        .rotate({ angle: -10 })
        .backgroundColor('rgba(5,206,145,0.14)')
        .position({ x: 46, y: 18 })
      Column()
        .width(124)
        .height(94)
        .borderRadius(20)
        .rotate({ angle: 8 })
        .backgroundColor('rgba(63,125,255,0.12)')
        .position({ x: 68, y: 34 })
      Column({ space: 8 }) {
        Column()
          .width(82)
          .height(9)
          .borderRadius(5)
          .backgroundColor(AppTheme.PRIMARY)
        Column()
          .width(58)
          .height(7)
          .borderRadius(4)
          .backgroundColor('rgba(26,26,26,0.18)')
        Column()
          .width(70)
          .height(7)
          .borderRadius(4)
          .backgroundColor('rgba(26,26,26,0.12)')
      }
      .width(132)
      .height(104)
      .padding(20)
      .borderRadius(22)
      .backgroundColor('#FFFFFF')
      .shadow({ radius: 20, color: 'rgba(31,62,68,0.12)', offsetX: 0, offsetY: 8 })
      .position({ x: 40, y: 28 })
    }
    .width(220)
    .height(150)
  }

  @Builder
  cardIllustration(key: string) {
    if (key === 'class') {
      this.courseIllustration()
    } else if (key === 'ai') {
      this.aiIllustration()
    } else {
      this.noteIllustration()
    }
  }

  @Builder
  entryCard(key: string, title: string, desc: string, accent: string, onTap: () => void) {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .borderRadius(32)
        .backgroundColor(GLASS_STRONG)
      Row() {
        Column({ space: AppTheme.SPACE_S }) {
          Text(key === 'class' ? '课堂路径' : (key === 'ai' ? '智能问答' : '笔记资产'))
            .fontSize(11)
            .fontWeight(FontWeight.Medium)
            .fontColor(accent)
          Text(title)
            .fontSize(30)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.INK)
          Text(desc)
            .fontSize(AppTheme.FONT_BODY)
            .fontColor(AppTheme.TEXT_TERTIARY)
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
        }
        .layoutWeight(1)
        .height('100%')
        .justifyContent(FlexAlign.Center)
        .alignItems(HorizontalAlign.Start)

        this.cardIllustration(key)
      }
      .width('100%')
      .height('100%')
      .padding({ left: 28, right: 18, top: 22, bottom: 22 })
      Row({ space: 8 }) {
        Text('进入')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontWeight(FontWeight.Medium)
          .fontColor('#FFFFFF')
        Text('→')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
      }
      .height(34)
      .padding({ left: 14, right: 14 })
      .borderRadius(999)
      .backgroundColor(accent)
      .position({ x: 28, y: 206 })
      .shadow({ radius: 18, color: accent, offsetX: 0, offsetY: 8 })
    }
    .layoutWeight(1)
    .height(264)
    .clip(true)
    .borderRadius(32)
    .border({ width: 1.2, color: GLASS_BORDER })
    .shadow({
      radius: this.pressedEntry === key ? 18 : 32,
      color: this.pressedEntry === key ? 'rgba(31,62,68,0.08)' :
        (key === 'class' ? 'rgba(255,184,77,0.18)' : (key === 'ai' ? 'rgba(63,125,255,0.16)' : SHADOW_MID)),
      offsetX: 0,
      offsetY: this.pressedEntry === key ? 7 : 14
    })
    .opacity(this.entriesReady ? 1 : 0)
    .translate({ x: 0, y: this.entriesReady ? (this.pressedEntry === key ? 4 : 0) : 28 })
    .scale({
      x: this.pressedEntry === key ? 0.976 : (this.entriesReady ? 1 : 0.985),
      y: this.pressedEntry === key ? 0.976 : (this.entriesReady ? 1 : 0.985)
    })
    .animation({ duration: this.pressedEntry === key ? 90 : 380, curve: Curve.EaseOut })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressedEntry = key;
      } else if (event.type === TouchType.Up) {
        this.pressedEntry = '';
      }
    })
    .onClick(() => {
      this.pressedEntry = '';
      onTap();
    })
  }

  build() {
    Stack() {
      this.pageAtmosphere()

      Column({ space: AppTheme.SPACE_L }) {
        this.heroPanel()

        if (!GlobalState.isTeacher()) {
          this.practiceEntryBanner()
        }

        Row({ space: AppTheme.SPACE_L }) {
          this.entryCard('class', '课程', '课堂记录、官方课时与录音成果', AMBER, (): void => {
            this.openClassPage();
          })
          this.entryCard('ai', 'AI', '基于课程知识库的问答助手', BLUE, (): void => {
            this.openAiPage();
          })
          this.entryCard('notes', '笔记', '班级笔记与个人笔记', AppTheme.PRIMARY, (): void => {
            this.openNotesPage();
          })
        }
        .layoutWeight(1)
        .width('100%')
        .alignItems(VerticalAlign.Top)
      }
      .width('100%')
      .height('100%')
      .padding({ left: AppTheme.SPACE_XXL, right: AppTheme.SPACE_XXL, top: 34, bottom: AppTheme.SPACE_XXL })
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BG_CANVAS)
  }
}
