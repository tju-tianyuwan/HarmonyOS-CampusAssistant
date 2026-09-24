import { TouchMotion } from '../common/TouchMotion';
import { promptAction } from '@kit.ArkUI';
import { LearningTheme as AppTheme } from '../common/LearningTheme';
import { ClassCourse } from '../model/Models';
import { Api } from '../service/Api';
import { GlobalState } from '../service/GlobalState';
import { deviceInfo } from '@kit.BasicServicesKit';
import { TimetablePage } from './TimetablePage';
import { CourseScheduleDialog } from './CourseScheduleDialog';
import { CrystalIcon } from '../common/components/CrystalIcon';
import { StudyMaterial } from '../common/StudyMaterial';

// 玻璃分层：底层面板/内容卡片/弹窗浮层，透明度逐级升高
const GLASS_PANEL_BG: string = 'rgba(255,255,255,0.56)';
const GLASS_CARD_BG: string = 'rgba(255,255,255,0.78)';
const GLASS_MODAL_BG: string = 'rgba(255,255,255,0.20)';//0.72->0.50
const GLASS_BORDER_LIGHT: string = 'rgba(255,255,255,0.50)';//0.96->0.75
const GLASS_BORDER_NORMAL: string = 'rgba(255,255,255,0.82)';
// 分层阴影：远层大面板 / 中层卡片 / 悬浮hover强化阴影
const SHADOW_LAYER_BACK: string = 'rgba(70,118,203,0.14)';
const SHADOW_LAYER_CARD: string = 'rgba(79,113,188,0.18)';
const SHADOW_LAYER_HOVER: string = 'rgba(78,201,226,0.30)';
// 鸿蒙原生毛玻璃模糊强度
const GLASS_BLUR_STRENGTH: number = 20;
// 背景底层低饱和底色
const BG_BASE: string = '#F1FBFF';

interface CourseVisual {
  base: string;
  wash: string;
  accent: string;
  ink: string;
}

interface DisplayCourse {
  id: number;
  name: string;
  class_name: string;
  teacher_name: string;
  invite_code: string;
  real: boolean;
}

const COURSE_VISUALS: CourseVisual[] = [
  {
    base: '#35C7E8',
    wash: 'rgba(210,246,255,0.56)',
    accent: '#316CF3',
    ink: '#2566C8'
  },
  {
    base: '#62DDD9',
    wash: 'rgba(219,255,249,0.58)',
    accent: '#7E6BFF',
    ink: '#1684A7'
  },
  {
    base: '#6A88FF',
    wash: 'rgba(235,238,255,0.54)',
    accent: '#29396F',
    ink: '#6246C9'
  }
];


/**
 * 课程库（登录后的用户主页）：
 * 玻璃拟态课程主页 + 原有课程业务入口。
 */
@Component
export struct LibraryPage {
  @StorageLink('reduceMotion') reduceMotion: boolean = false;
  @StorageLink('crystalSoftMaterial') softMaterial: boolean = false;
  @State compact: boolean = false;
  @State pageWidth: number = 400;
  @State loading: boolean = true;
  @State loadError: string = '';
  onEnterCourse: () => void = () => {
  };
  onLogout: () => void = () => {
  };
  onOpenSettings: () => void = () => {
  };
  @State courses: ClassCourse[] = [];
  @State showForm: boolean = false;
  @State formOpenProgress: boolean = false;
  @State scheduleCourseId: number = -1;
  @State scheduleCourseName: string = '';
  @State timetableRevision: number = 0;
  @State formInviteCode: string = '';
  @State hoveredCourseId: number = -1;
  @State pressedCourseId: number = -1;
  @State enteringCourseId: number = -1;
  @State enteringCourseActive: boolean = false;
  @State fabPulse: boolean = false;
  @State fabPressed: boolean = false;
  @State greeting: string = '早上好';
  private fabTimer: number = -1;
  private formTimer: number = -1;
  private courseEnterTimer: number = -1;
  private greetingTimer: number = -1;

  aboutToAppear(): void {
    this.enteringCourseId = -1;
    this.enteringCourseActive = false;
    this.updateGreeting();
    this.loadCourses();
    this.startGreetingClock();
  }

  aboutToDisappear(): void {
    this.stopFabPulse();
    this.stopFormAnimation();
    this.stopCourseEnterAnimation();
    this.stopGreetingClock();
  }

  private startGreetingClock(): void {
    if (this.greetingTimer >= 0) {
      return;
    }
    this.greetingTimer = setInterval(() => {
      this.updateGreeting();
    }, 60000);
  }

  private stopGreetingClock(): void {
    if (this.greetingTimer >= 0) {
      clearInterval(this.greetingTimer);
      this.greetingTimer = -1;
    }
  }

  private updateGreeting(): void {
    const hour: number = new Date().getHours();
    if (hour >= 5 && hour < 10) {
      this.greeting = '早上好';
    } else if (hour >= 10 && hour < 12) {
      this.greeting = '上午好';
    } else if (hour >= 12 && hour < 14) {
      this.greeting = '中午好';
    } else if (hour >= 14 && hour < 18) {
      this.greeting = '下午好';
    } else if (hour >= 18) {
      this.greeting = '晚上好';
    } else {
      this.greeting = '夜深了';
    }
  }

  private startFabPulse(): void {
    if (this.fabTimer >= 0) {
      return;
    }
    this.fabTimer = setInterval(() => {
      this.fabPulse = !this.fabPulse;
    }, 1400);
  }

  private stopFabPulse(): void {
    if (this.fabTimer >= 0) {
      clearInterval(this.fabTimer);
      this.fabTimer = -1;
    }
  }

  private stopFormAnimation(): void {
    if (this.formTimer >= 0) {
      clearTimeout(this.formTimer);
      this.formTimer = -1;
    }
  }

  private stopCourseEnterAnimation(): void {
    if (this.courseEnterTimer >= 0) {
      clearTimeout(this.courseEnterTimer);
      this.courseEnterTimer = -1;
    }
  }

  private playCourseEnter(cc: ClassCourse): void {
    this.stopCourseEnterAnimation();
    this.pressedCourseId = -1;
    this.hoveredCourseId = -1;
    this.enter(cc);
  }

  private openForm(): void {
    this.scheduleCourseId = -1;
    this.scheduleCourseName = '';
    this.stopFormAnimation();
    this.showForm = true;
    this.formOpenProgress = true;
  }

  private closeForm(): void {
    if (!this.showForm) {
      return;
    }
    this.stopFormAnimation();
    this.formOpenProgress = false;
    this.showForm = false;
  }

  private toast(msg: string): void {
    promptAction.showToast({ message: msg });
  }

  private userName(): string {
    return GlobalState.user === null ? '小明' : GlobalState.user.name;
  }

  private userInitial(): string {
    return this.userName().substring(0, 1);
  }

  private visual(id: number): CourseVisual {
    const idx: number = Math.abs(id) % COURSE_VISUALS.length;
    return COURSE_VISUALS[idx];
  }

  private isCourseEntering(id: number): boolean {
    return this.enteringCourseId === id && this.enteringCourseActive;
  }

  private displayCourses(): DisplayCourse[] {
    if (this.courses.length === 0) {
      return [];
    }
    const list: DisplayCourse[] = [];
    for (let i = 0; i < this.courses.length; i++) {
      const cc: ClassCourse = this.courses[i];
      list.push({
        id: cc.id,
        name: cc.name,
        class_name: cc.class_name,
        teacher_name: cc.teacher_name ?? '王老师',
        invite_code: cc.invite_code,
        real: true
      });
    }
    return list;
  }

  private enterDisplay(dc: DisplayCourse): void {
    if (!dc.real) {
      this.openForm();
      return;
    }
    for (let i = 0; i < this.courses.length; i++) {
      if (this.courses[i].id === dc.id) {
        this.playCourseEnter(this.courses[i]);
        return;
      }
    }
  }

  private async loadCourses(): Promise<void> {
    this.loading = true;
    this.loadError = '';
    try {
      this.courses = JSON.parse(
        await Api.get(`/courses?user_id=${GlobalState.userId()}`)) as ClassCourse[];
      this.timetableRevision++;
    } catch (e) {
      this.loadError = (e as Error).message;
      this.toast(`加载课程失败：${(e as Error).message}`);
    } finally { this.loading = false; }
  }

  private canSchedule(id: number): boolean {
    return GlobalState.isTeacher() && this.courses.some((course: ClassCourse) =>
      course.id === id && course.teacher_id === GlobalState.userId() && !course.is_personal);
  }

  private editSchedule(id: number): void {
    const course = this.courses.find((item: ClassCourse) => item.id === id);
    if (course === undefined || !this.canSchedule(id)) { return; }
    this.scheduleCourseId = id;
    this.scheduleCourseName = course.name;
    this.showForm = true;
    this.formOpenProgress = true;
  }

  private async joinCourse(): Promise<void> {
    if (this.formInviteCode.trim().length !== 6) {
      this.toast('请输入 6 位邀请码');
      return;
    }
    interface JoinBody {
      user_id: number;
      invite_code: string;
    }

    const body: JoinBody = { user_id: GlobalState.userId(), invite_code: this.formInviteCode.trim() };
    try {
      await Api.post('/courses/join', body);
      this.toast('加入成功');
      this.closeForm();
      this.formInviteCode = '';
      await this.loadCourses();
    } catch (e) {
      this.toast(`加入失败：${(e as Error).message}`);
    }
  }

  private enter(cc: ClassCourse): void {
    GlobalState.setCourse(cc);
    this.onEnterCourse();
  }

  // ---------- Glass UI ----------
  @Builder
  topStatCard(label: string, tint: string) {
    Column({ space: 3 }) {
      Text(label === '课程数量' ? `${this.courses.length}` : `${new Set(this.courses
        .filter((course: ClassCourse) => !course.is_personal).map((course: ClassCourse) => course.class_name)).size}`)
        .fontSize(24)
        .fontWeight(FontWeight.Bold)
        .fontColor(AppTheme.INK)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(label)
        .fontSize(AppTheme.FONT_CAPTION)
        .fontColor(AppTheme.TEXT_TERTIARY)
    }
    .width(116)
    .height(76)
    .justifyContent(FlexAlign.Center)
    .borderRadius(24)
    .backdropBlur(GLASS_BLUR_STRENGTH)
    .backgroundColor(tint)
    .border({ width: 1.2, color: GLASS_BORDER_LIGHT })
    .shadow({ radius: 24, color: SHADOW_LAYER_CARD, offsetX: 0, offsetY: 10 })
  }

  @Builder
  avatarSwitch() {
    Column({ space: 5 }) {
      Text(this.userInitial())
        .fontSize(AppTheme.FONT_SUBTITLE)
        .fontWeight(FontWeight.Bold)
        .fontColor('#FFFFFF')
        .width(52)
        .height(52)
        .textAlign(TextAlign.Center)
        .borderRadius(26)
        .backgroundColor(GlobalState.isTeacher() ? 'rgba(61,78,132,0.84)' : 'rgba(64,169,229,0.88)')
        .border({ width: 1.4, color: 'rgba(255,255,255,0.88)' })
        .shadow({ radius: 24, color: 'rgba(64,169,229,0.34)', offsetX: 0, offsetY: 9 })
      Text('个人设置')
        .fontSize(11)
        .fontColor(AppTheme.TEXT_SECONDARY)
    }
    .width(86)
    .height(76)
    .justifyContent(FlexAlign.Center)
    .borderRadius(26)
    .backdropBlur(GLASS_BLUR_STRENGTH)
    .backgroundColor(GLASS_CARD_BG)
    .border({ width: 1.2, color: GLASS_BORDER_LIGHT })
    .shadow({ radius: 22, color: SHADOW_LAYER_CARD, offsetX: 0, offsetY: 8 })
    .onClick(() => {
      this.onOpenSettings();
    })
  }

  @Builder
  topArea() {
    if (this.compact) {
      Row({ space: 12 }) {
        Column({ space: 4 }) {
          Text(this.userName()).fontSize(20).fontWeight(FontWeight.Bold).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${this.courses.length} 门课程`).fontSize(13).fontColor(AppTheme.TEXT_SECONDARY)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Button('个人设置').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).fontColor(AppTheme.PRIMARY_DEEP).backgroundColor(AppTheme.PRIMARY_LIGHT)
          .onClick(() => { this.onOpenSettings(); })
      }.width('100%').height(64)
    } else {
    Row({ space: AppTheme.SPACE_L }) {
      Column({ space: AppTheme.SPACE_XS }) {
        Text(`${this.greeting}，${this.userName()}`)
          .fontSize(32)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text(GlobalState.isTeacher() ? '教师 · 课程教学' : '学生 · 课堂记录与复习')
          .fontSize(AppTheme.FONT_BODY)
          .fontColor('rgba(255,255,255,0.82)')
      }
      .layoutWeight(1)
      .height(104)
      .padding({ left: AppTheme.SPACE_XL, right: AppTheme.SPACE_XL })
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Start)
      .borderRadius(26)
      .backdropBlur(GLASS_BLUR_STRENGTH)
      .linearGradient({
        angle: 118,
        colors: [
          ['#43D0EB', 0],
          ['#338AF1', 0.55],
          ['#3863F0', 1]
        ]
      })
      .border({ width: 1.2, color: 'rgba(255,255,255,0.68)' })
      .shadow({ radius: 36, color: 'rgba(53,108,243,0.28)', offsetX: 0, offsetY: 14 })

      Row({ space: AppTheme.SPACE_M }) {
        this.topStatCard('课程数量', 'rgba(220,244,255,0.90)')
        this.topStatCard('班级数量', 'rgba(239,232,255,0.88)')
        this.avatarSwitch()
      }
      .height(104)
      .padding({ left: AppTheme.SPACE_M, right: AppTheme.SPACE_M })
      .borderRadius(26)
      .backdropBlur(GLASS_BLUR_STRENGTH)
      .backgroundColor(GLASS_PANEL_BG)
      .border({ width: 1.2, color: GLASS_BORDER_LIGHT })
      .shadow({ radius: 32, color: SHADOW_LAYER_BACK, offsetX: 0, offsetY: 12 })
    }
    .width('100%')
    }
  }

  @Builder
  courseHero(dc: DisplayCourse, visual: CourseVisual) {
    Stack({ alignContent: Alignment.TopStart }) {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 118,
          colors: [
            [visual.base, 0],
            [visual.accent, 1]
          ]
        })
      Column()
        .width(112)
        .height(78)
        .borderRadius(22)
        .backgroundColor('rgba(255,255,255,0.10)')
        .border({ width: 1, color: 'rgba(255,255,255,0.20)' })
        .position({ x: 174, y: 32 })
      Column()
        .width(178)
        .height(2)
        .borderRadius(1)
        .backgroundColor('rgba(255,255,255,0.74)')
        .position({ x: 22, y: 92 })
      Column({ space: 5 }) {
        Text('CLASSROOM')
          .fontSize(10)
          .fontColor('rgba(255,255,255,0.74)')
          .fontWeight(FontWeight.Medium)
        Text(dc.name)
          .fontSize(20)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width(170)
        Text(dc.real ? '实时课程' : '演示课程')
          .fontSize(11)
          .fontColor('rgba(255,255,255,0.76)')
      }
      .alignItems(HorizontalAlign.Start)
      .position({ x: 22, y: 24 })
      Column({ space: 5 }) {
        Text(dc.name.substring(0, 1))
          .fontSize(24)
          .fontWeight(FontWeight.Bold)
          .fontColor(visual.ink)
        Column()
          .width(28)
          .height(4)
          .borderRadius(2)
          .backgroundColor(visual.ink)
          .opacity(0.60)
        Column()
          .width(22)
          .height(4)
          .borderRadius(2)
          .backgroundColor(visual.ink)
          .opacity(0.36)
      }
      .width(56)
      .height(56)
      .justifyContent(FlexAlign.Center)
      .alignItems(HorizontalAlign.Center)
      .borderRadius(18)
      .backgroundColor('rgba(255,255,255,0.88)')
      .border({ width: 1.2, color: GLASS_BORDER_LIGHT })
      .shadow({ radius: 20, color: 'rgba(26,48,104,0.18)', offsetX: 0, offsetY: 8 })
      .position({ x: 224, y: 40 })
      Column()
        .width(64)
        .height(20)
        .borderRadius(10)
        .backgroundColor(visual.wash)
        .position({ x: 210, y: 104 })
      Column()
        .width(92)
        .height(8)
        .borderRadius(4)
        .backgroundColor('rgba(255,255,255,0.24)')
        .position({ x: 20, y: 118 })
      Column()
        .width(54)
        .height(8)
        .borderRadius(4)
        .backgroundColor('rgba(255,255,255,0.18)')
        .position({ x: 132, y: 118 })
    }
    .width('100%')
    .height(140)
    .clip(true)
  }

  @Builder
  courseCard(dc: DisplayCourse) {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        this.courseHero(dc, this.visual(dc.id))

        Column({ space: AppTheme.SPACE_XS }) {
          Text(dc.name)
            .fontSize(AppTheme.FONT_SUBTITLE)
            .fontWeight(FontWeight.Medium)
            .fontColor(AppTheme.TEXT_PRIMARY)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${dc.class_name} · ${dc.teacher_name}`)
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.TEXT_TERTIARY)
            .maxLines(1)
          Row() {
            Row({ space: 5 }) {
              Text('邀请码')
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(AppTheme.TEXT_TERTIARY)
              Text(dc.invite_code)
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(this.visual(dc.id).ink)
                .fontWeight(FontWeight.Medium)
            }
            Blank()
            Text('进入课程')
              .fontSize(11)
              .fontWeight(FontWeight.Medium)
              .fontColor('#FFFFFF')
              .padding({ left: 12, right: 12, top: 5, bottom: 5 })
              .borderRadius(999)
              .backgroundColor(this.visual(dc.id).accent)
              .shadow({ radius: 14, color: 'rgba(91,112,232,0.22)', offsetX: 0, offsetY: 5 })
          }
          .width('100%')
          .alignItems(VerticalAlign.Center)
        }
        .width('100%')
        .padding({ left: AppTheme.SPACE_M, right: AppTheme.SPACE_M, top: AppTheme.SPACE_M, bottom: AppTheme.SPACE_M })
        .alignItems(HorizontalAlign.Start)
      }
      if (this.canSchedule(dc.id)) {
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.calendar')).fontSize(20).fontColor(['#305FC3'])
        }.stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).width(40).height(40).borderRadius(8).backgroundColor('#FFFFFF')
          .position({ x: 240, y: 8 }).accessibilityText('设置上课时间')
          .onClick(() => { this.editSchedule(dc.id); })
      }
    }
    .width(292)
    .height(276)
    .borderRadius(24)
    .clip(true)
    .backdropBlur(GLASS_BLUR_STRENGTH)
    .backgroundColor('rgba(255,255,255,0.86)')
    .border({
      width: 1.2,
      color: this.hoveredCourseId === dc.id ? GLASS_BORDER_LIGHT : GLASS_BORDER_NORMAL
    })
    .shadow({
      radius: this.isCourseEntering(dc.id) ? 56 : (this.hoveredCourseId === dc.id ? 38 : 26),
      color: this.isCourseEntering(dc.id) ? 'rgba(78,201,226,0.34)' :
        (this.hoveredCourseId === dc.id ? SHADOW_LAYER_HOVER : SHADOW_LAYER_CARD),
      offsetX: 0,
      offsetY: this.isCourseEntering(dc.id) ? 22 : (this.hoveredCourseId === dc.id ? 16 : 9)
    })
    .stateStyles({
      normal: { .translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
      pressed: { .translate(TouchMotion.pressedOffset(this.reduceMotion, 'card')).animation(TouchMotion.press(this.reduceMotion)) }
    })
    .onHover((isHover: boolean) => {
      this.hoveredCourseId = isHover ? dc.id : -1;
    })
    .onClick(() => {
      if (!this.showForm && !this.isCourseEntering(dc.id)) {
        this.enterDisplay(dc);
      }
    })
  }

  @Builder
  compactTeacherCourseCard(dc: DisplayCourse) {
    Row({ space: 8 }) {
      Row({ space: 12 }) {
        SymbolGlyph($r('sys.symbol.doc_text'))
          .fontSize(24).fontColor([this.visual(dc.id).ink])
          .width(44).height(44).backgroundColor(this.visual(dc.id).wash).borderRadius(8)
        Column({ space: 6 }) {
          Text(dc.name).fontSize(17).fontWeight(FontWeight.Medium).fontColor(AppTheme.INK)
            .width('100%').maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${dc.class_name} · ${dc.teacher_name}`).fontSize(12).fontColor(AppTheme.TEXT_SECONDARY)
            .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`邀请码 ${dc.invite_code}`).fontSize(12).fontColor(this.visual(dc.id).ink)
            .width('100%').maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(12).fontColor([AppTheme.TEXT_TERTIARY])
      }.layoutWeight(1).height('100%')
        .accessibilityText(`进入课程：${dc.name}，${dc.class_name}`)
        .stateStyles({
          normal: { .translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
          pressed: { .translate(TouchMotion.pressedOffset(this.reduceMotion, 'card')).animation(TouchMotion.press(this.reduceMotion)) }
        })
        .onClick(() => {
          if (!this.showForm && !this.enteringCourseActive) { this.enterDisplay(dc); }
        })
      if (this.canSchedule(dc.id)) {
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.calendar')).fontSize(20).fontColor(['#305FC3'])
        }.stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).width(44).height(44).borderRadius(8).backgroundColor('#EEF3FC')
          .accessibilityText(`设置${dc.name}的上课时间`)
          .bindPopup(this.hoveredCourseId === dc.id, { message: '设置上课时间' })
          .onHover((hovered: boolean) => { this.hoveredCourseId = hovered ? dc.id : -1; })
          .onClick(() => { this.editSchedule(dc.id); })
      }
    }.width('100%').height(120).padding(12).borderRadius(8)
      .backgroundColor('#FFFFFF').border({ width: 1, color: '#E5EAF0' })
  }

  @Builder
  courseGrid() {
    Scroll() {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.displayCourses(), (dc: DisplayCourse) => {
          Column() {
            if (this.compact && GlobalState.isTeacher()) {
              this.compactTeacherCourseCard(dc)
            } else {
              this.courseCard(dc)
            }
          }
          .width(this.compact && GlobalState.isTeacher() ? '100%' : 292)
          .margin({ right: this.compact && GlobalState.isTeacher() ? 0 : AppTheme.SPACE_M,
            bottom: this.compact && GlobalState.isTeacher() ? 10 : AppTheme.SPACE_L })
        }, (dc: DisplayCourse) => `${dc.id}`)
      }
      .width('100%')
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off)
    .align(Alignment.TopStart)
  }

  @Builder
  fab() {
    Column({ space: 8 }) {
      Stack({ alignContent: Alignment.Center }) {
        Column()
          .width(124)
          .height(124)
          .borderRadius(62)
          .linearGradient({
            angle: 145,
            colors: [
              ['#9AF6F0', 0],
              ['#5CC7ED', 0.42],
              ['#5B8AF7', 0.72],
              ['#7556E5', 1]
            ]
          })
          .border({ width: 1.6, color: 'rgba(255,255,255,0.92)' })
          .shadow({
            radius: this.fabPressed ? 18 : (this.fabPulse ? 34 : 28),
            color: this.fabPressed ? 'rgba(43,80,180,0.28)' :
              (this.fabPulse ? 'rgba(80,201,230,0.48)' : 'rgba(91,112,232,0.34)'),
            offsetX: 0,
            offsetY: this.fabPressed ? 7 : 14
          })
        Column()
          .width(42)
          .height(26)
          .borderRadius(18)
          .rotate({ angle: -22 })
          .backgroundColor(this.fabPressed ? 'rgba(255,255,255,0.13)' : 'rgba(255,255,255,0.24)')
          .position({ x: 30, y: 24 })
        Column()
          .width(18)
          .height(18)
          .borderRadius(9)
          .backgroundColor(this.fabPressed ? 'rgba(255,255,255,0.12)' : 'rgba(255,255,255,0.22)')
          .position({ x: 75, y: 32 })
        Text('＋')
          .fontSize(50)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.fabPressed ? 'rgba(255,255,255,0.90)' : '#FFFFFF')
          .width(124)
          .height(124)
          .textAlign(TextAlign.Center)
      }
      .width(132)
      .height(132)
      Text('新建/加入课程')
        .fontSize(AppTheme.FONT_CAPTION)
        .fontWeight(FontWeight.Medium)
        .fontColor('#2452B9')
        .padding({ left: 14, right: 14, top: 6, bottom: 6 })
        .borderRadius(999)
        .backdropBlur(GLASS_BLUR_STRENGTH)
        .backgroundColor('rgba(255,255,255,0.78)')
        .border({ width: 1.2, color: GLASS_BORDER_LIGHT })
        .shadow({ radius: 18, color: 'rgba(76,110,180,0.14)', offsetX: 0, offsetY: 6 })
    }
    .margin({ right: AppTheme.SPACE_L, bottom: AppTheme.SPACE_L })
    .stateStyles({
      normal: { .scale({ x: 1, y: 1 }).animation(TouchMotion.release(this.reduceMotion)) },
      pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'icon')).animation(TouchMotion.press(this.reduceMotion)) }
    })
    .onClick(() => {
      this.fabPressed = false;
      this.openForm();
    })
  }

  @Builder
  formOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column().width('100%').height('100%').backgroundColor('rgba(20,34,50,0.3)')
        .onClick(() => { this.closeForm(); })
      Column({ space: 18 }) {
        Text('加入课程').fontSize(22).fontWeight(FontWeight.Bold)
        TextInput({ placeholder: '输入 6 位邀请码', text: this.formInviteCode }).height(44).maxLength(6)
          .onChange((value: string) => { this.formInviteCode = value; })
        Button('加入课程').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).width('100%').height(44).borderRadius(8).backgroundColor('#305FC3')
          .onClick(() => { this.joinCourse(); })
        Button('取消').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).width('100%').height(40).backgroundColor(Color.Transparent).fontColor(AppTheme.TEXT_SECONDARY)
          .onClick(() => { this.closeForm(); })
      }.width('92%').constraintSize({ maxWidth: 392 }).padding(24).borderRadius(8).backgroundColor('#FFFFFF')
    }.width('100%').height('100%')
      .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 18 }))
        .animation({ duration: this.reduceMotion ? 0 : 220, curve: TouchMotion.enter() }))
  }

  @Builder
  nativeFluidBackground() {
    Stack() {
      Column()
        .width('100%')
        .height('100%')
        .linearGradient({
          angle: 35,
          colors: [
            ['rgba(217,253,255,1)', 0],
            ['rgba(244,250,255,1)', 0.44],
            ['rgba(246,239,255,1)', 0.74],
            ['rgba(235,242,255,1)', 1]
          ]
        })
      Column()
        .width(420)
        .height('100%')
        .linearGradient({
          angle: 90,
          colors: [
            ['rgba(118,238,233,0.24)', 0],
            ['rgba(207,250,255,0.12)', 0.68],
            ['rgba(255,255,255,0.02)', 1]
          ]
        })
        .position({ x: 0, y: 0 })
      Column()
        .width(640)
        .height(1040)
        .borderRadius(180)
        .rotate({ angle: -18 })
        .backgroundColor('rgba(57,204,237,0.15)')
        .position({ x: -280, y: -120 })
      Column()
        .width(780)
        .height(920)
        .borderRadius(180)
        .rotate({ angle: 16 })
        .backgroundColor('rgba(134,100,255,0.13)')
        .position({ x: 1080, y: -120 })
      Column()
        .width(980)
        .height(360)
        .borderRadius(170)
        .rotate({ angle: -7 })
        .backgroundColor('rgba(108,236,224,0.16)')
        .position({ x: 730, y: 730 })
      Column()
        .width(820)
        .height(1160)
        .borderRadius(170)
        .rotate({ angle: -13 })
        .backdropBlur(8)
        .linearGradient({
          angle: 115,
          colors: [
            ['rgba(255,255,255,0.32)', 0],
            ['rgba(255,255,255,0.09)', 0.48],
            ['rgba(125,226,244,0.10)', 1]
          ]
        })
        .border({ width: 1, color: 'rgba(255,255,255,0.36)' })
        .position({ x: -260, y: -92 })
      Column()
        .width(620)
        .height(980)
        .borderRadius(150)
        .rotate({ angle: 13 })
        .backdropBlur(10)
        .linearGradient({
          angle: 70,
          colors: [
            ['rgba(255,255,255,0.22)', 0],
            ['rgba(231,226,255,0.16)', 0.52],
            ['rgba(255,255,255,0.06)', 1]
          ]
        })
        .border({ width: 1, color: 'rgba(255,255,255,0.30)' })
        .position({ x: 1180, y: 8 })
      Column()
        .width(900)
        .height(1)
        .backgroundColor('rgba(255,255,255,0.34)')
        .position({ x: 70, y: 242 })
      Column()
        .width(760)
        .height(1)
        .backgroundColor('rgba(255,255,255,0.24)')
        .position({ x: 980, y: 706 })
      Column()
        .width(1)
        .height(920)
        .backgroundColor('rgba(255,255,255,0.18)')
        .position({ x: 558, y: 62 })
      Column()
        .width('100%')
        .height(150)
        .backgroundColor('rgba(255,255,255,0.34)')
        .position({ x: 0, y: 930 })
      Column()
        .width('100%')
        .height('100%')
        .backdropBlur(4)
        .backgroundColor('rgba(255,255,255,0.06)')
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  studentLibrary() {
    Column({ space: 24 }) {
      Row({ space: 20 }) {
        Column({ space: 8 }) {
          Text(`${this.greeting}，${this.userName()}`).fontSize(30).fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.TEXT_PRIMARY).maxLines(2)
          Text(`我的课程 · ${this.courses.length} 门`).fontSize(15).fontColor(AppTheme.TEXT_SECONDARY)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Button('个人设置').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).height(44).fontSize(14).borderRadius(12)
          .fontColor(AppTheme.PRIMARY).backgroundColor(AppTheme.PRIMARY_LIGHT).onClick(this.onOpenSettings)
        Button('加入课程').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).height(44).fontSize(14).borderRadius(12)
          .fontColor(AppTheme.BG_WHITE).backgroundColor(AppTheme.PRIMARY).onClick(() => { this.openForm(); })
      }.width('100%')
      Scroll() {
        Grid() {
          if (this.courses.length === 0) {
            GridItem() {
              Text('还没有课程，使用老师的邀请码加入吧').fontSize(16)
                .fontColor(AppTheme.TEXT_SECONDARY).padding(32)
            }
          }
          ForEach(this.courses, (course: ClassCourse) => {
            GridItem() {
            Column({ space: 22 }) {
              Row() {
              Stack() { SymbolGlyph($r('sys.symbol.book')).fontSize(28).fontColor([AppTheme.PRIMARY]) }
                .width(64).height(64).borderRadius(20).backgroundColor(AppTheme.PRIMARY_LIGHT)
              Blank()
              SymbolGlyph($r('sys.symbol.arrow_up_right')).fontSize(18).fontColor([AppTheme.PRIMARY])
              }.width('100%')
              Column({ space: 8 }) {
                Text(course.name).fontSize(21).fontWeight(FontWeight.Medium).fontColor(AppTheme.TEXT_PRIMARY)
                  .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(`${course.class_name} · ${course.teacher_name}`).fontSize(14).fontColor(AppTheme.TEXT_SECONDARY)
                  .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
              }.width('100%').alignItems(HorizontalAlign.Start)
              Text('进入课程  ›').fontSize(14).fontColor(AppTheme.PRIMARY).width('100%')
            }.width('100%').constraintSize({ minHeight: 240 }).padding(24).borderRadius(26)
              .backgroundColor(AppTheme.BG_CARD).border({ width: 1, color: '#F5FFFFFF' })
              .shadow({ radius: 20, color: '#12436F9D', offsetY: 8 })
              .stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'card'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'card')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          })
              .accessibilityText(`进入${course.name}`).onClick(() => { this.enter(course); })
            }
          }, (course: ClassCourse) => `${course.id}`)
        }.width('100%').columnsTemplate(this.compact ? '1fr 1fr' : '1fr 1fr 1fr').columnsGap(20).rowsGap(20)
      }.width('100%').layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Auto)
    }.width('100%').height('100%').padding(32).backgroundColor(AppTheme.BG_PAGE)
  }

  @Builder
  teacherCourseCard(course: ClassCourse) {
    Column({ space: 18 }) {
      Row({ space: 16 }) {
        CrystalIcon({ icon: $r('sys.symbol.book'), edge: this.pageWidth < 600 ? 42 : 50 })
        Column({ space: 6 }) {
          Text(course.name).fontSize(this.pageWidth < 600 ? 19 : 22).fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.INK).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
          Text(course.class_name || '课程空间').fontSize(14).fontColor(AppTheme.TEXT_SECONDARY)
            .maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        SymbolGlyph($r('sys.symbol.arrow_up_right')).fontSize(16).fontColor([AppTheme.PRIMARY])
      }.width('100%').constraintSize({ minHeight: this.pageWidth < 600 ? 62 : 88 })
        .stateStyles({
          normal: { .translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
          pressed: { .translate(TouchMotion.pressedOffset(this.reduceMotion, 'card')).animation(TouchMotion.press(this.reduceMotion)) }
        })
        .accessibilityText(`进入${course.name}`).onClick(() => { this.enter(course); })
      Row({ space: 8 }) {
        Column({ space: 4 }) {
          Text(`邀请码 ${course.invite_code}`).fontSize(12).fontColor(AppTheme.TEXT_SECONDARY)
            .copyOption(CopyOptions.InApp).maxLines(1)
          Text('进入课程 ›').fontSize(14).fontColor(AppTheme.PRIMARY)
            .onClick(() => { this.enter(course); })
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        if (this.canSchedule(course.id)) {
          Button('排课').height(40).fontSize(14).borderRadius(14)
            .backgroundColor(AppTheme.PRIMARY_LIGHT).fontColor(AppTheme.PRIMARY)
            .stateStyles({
              normal: { .scale({ x: 1, y: 1 }).animation(TouchMotion.release(this.reduceMotion)) },
              pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) }
            }).accessibilityText(`设置${course.name}上课时间`).onClick(() => { this.editSchedule(course.id); })
        }
      }.width('100%')
    }.width('100%').padding(this.pageWidth < 600 ? 20 : 24).borderRadius(26)
      .backgroundColor(AppTheme.BG_CARD).border({ width: 1, color: '#F5FFFFFF' })
      .shadow({ radius: 20, color: '#12436F9D', offsetY: 8 })
      .visualEffect(StudyMaterial.light(this.softMaterial))
  }

  @Builder
  teacherLibrary() {
    Column({ space: this.pageWidth < 600 ? 20 : 28 }) {
      Row({ space: 12 }) {
        Column({ space: 8 }) {
          Text(`${this.greeting}，${this.userName()}`).fontSize(this.pageWidth < 600 ? 26 : 32)
            .fontWeight(FontWeight.Bold).fontColor(AppTheme.INK).maxLines(2)
          Text(`我的教学空间 · ${this.courses.length} 门课程`).fontSize(14).fontColor(AppTheme.TEXT_SECONDARY)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.person')).fontSize(22).fontColor([AppTheme.PRIMARY])
        }.width(48).height(48).borderRadius(18).backgroundColor(AppTheme.BG_CARD)
          .visualEffect(StudyMaterial.light(this.softMaterial))
          .stateStyles({
            normal: { .scale({ x: 1, y: 1 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'icon')).animation(TouchMotion.press(this.reduceMotion)) }
          }).accessibilityText('个人设置').onClick(this.onOpenSettings)
      }.width('100%')
      Row({ space: 12 }) {
        Column({ space: 5 }) {
          Text('我的课程').fontSize(20).fontWeight(FontWeight.Bold).fontColor(AppTheme.INK)
          Text('课堂记录、教学资料与学情，一处掌握').fontSize(12).fontColor(AppTheme.TEXT_SECONDARY)
            .maxLines(2)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Button('新建课程').height(44).fontSize(14).borderRadius(16)
          .backgroundColor(AppTheme.PRIMARY).fontColor('#FFFFFF')
          .stateStyles({
            normal: { .scale({ x: 1, y: 1 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) }
          }).onClick(() => { this.openForm(); })
      }.width('100%')
      if (this.loading && this.courses.length === 0) {
        LoadingProgress().width(40).height(40).color(AppTheme.PRIMARY)
      } else if (this.loadError !== '') {
        Column({ space: 12 }) {
          Text('课程暂时未能加载').fontSize(18).fontWeight(FontWeight.Medium).fontColor(AppTheme.INK)
          Text(this.loadError).fontSize(13).fontColor(AppTheme.TEXT_SECONDARY)
          Button('重新加载').backgroundColor(AppTheme.PRIMARY).enabled(!this.loading)
            .onClick(() => { this.loadCourses(); })
        }.padding(24).width('100%').borderRadius(24).backgroundColor(AppTheme.BG_CARD)
      } else if (this.courses.length === 0) {
        Column({ space: 16 }) {
          CrystalIcon({ icon: $r('sys.symbol.book'), edge: 56 })
          Text('从第一门课程开始').fontSize(20).fontWeight(FontWeight.Bold).fontColor(AppTheme.INK)
          Text('新建课程并安排上课时间，学生加入后即可同步课表。')
            .fontSize(14).fontColor(AppTheme.TEXT_SECONDARY).textAlign(TextAlign.Center)
        }.padding(32).width('100%').borderRadius(26).backgroundColor(AppTheme.BG_CARD)
      }
      Grid() {
        ForEach(this.courses, (course: ClassCourse) => {
          GridItem() { this.teacherCourseCard(course) }
        }, (course: ClassCourse) => `${course.id}`)
      }.width('100%').layoutWeight(1).columnsTemplate(this.pageWidth < 600 ? '1fr' :
        (this.pageWidth < 1150 ? '1fr 1fr' : '1fr 1fr 1fr'))
        .columnsGap(20).rowsGap(this.pageWidth < 600 ? 14 : 20).scrollBar(BarState.Auto)
    }.width('100%').height('100%').padding(this.pageWidth < 600 ? 20 : 32)
  }

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      if (deviceInfo.deviceType === 'phone' && !GlobalState.isTeacher()) {
        TimetablePage({ courses: this.courses, revision: this.timetableRevision,
          onEnterCourse: (course: ClassCourse) => { this.enter(course); },
          onJoinCourse: () => { this.openForm(); },
          onOpenSettings: this.onOpenSettings })
      } else if (!GlobalState.isTeacher()) {
        this.studentLibrary()
      } else {
        this.teacherLibrary()
      }

      if (this.showForm) {
        if (GlobalState.isTeacher()) {
          CourseScheduleDialog({ courseId: this.scheduleCourseId, courseName: this.scheduleCourseName,
            onClose: () => { this.showForm = false; },
            onSaved: () => { this.showForm = false; this.loadCourses(); } })
        } else { this.formOverlay() }
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(Color.Transparent)
    .onAreaChange((oldArea: Area, newArea: Area) => {
      this.pageWidth = Number(newArea.width);
      this.compact = Number(newArea.width) < 900 || Number(newArea.height) < 500;
    })
  }
}
