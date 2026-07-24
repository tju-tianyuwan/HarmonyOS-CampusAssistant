import { promptAction } from '@kit.ArkUI';
import { AppTheme } from '../common/AppTheme';
import { ClassCourse } from '../model/Models';
import { Api } from '../service/Api';
import { GlobalState } from '../service/GlobalState';

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

const DEMO_COURSES: DisplayCourse[] = [
  { id: -1, name: '数据结构', class_name: '计科2301班', teacher_name: '王老师', invite_code: '230101', real: false },
  { id: -2, name: '高等数学', class_name: '计科2301班', teacher_name: '王老师', invite_code: '230102', real: false },
  { id: -3, name: '大学英语', class_name: '计科2301班', teacher_name: '王老师', invite_code: '230103', real: false },
  { id: -4, name: '计算机网络', class_name: '计科2301班', teacher_name: '王老师', invite_code: '230104', real: false },
  { id: -5, name: '人工智能导论', class_name: '计科2301班', teacher_name: '王老师', invite_code: '230105', real: false }
];

/**
 * 课程库（登录后的用户主页）：
 * 玻璃拟态课程主页 + 原有课程业务入口。
 */
@Component
export struct LibraryPage {
  onEnterCourse: () => void = () => {
  };
  onLogout: () => void = () => {
  };
  onOpenSettings: () => void = () => {
  };
  @State courses: ClassCourse[] = [];
  @State showForm: boolean = false;
  @State formOpenProgress: boolean = false;
  @State formCourseName: string = '';
  @State formClassName: string = '';
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
    this.startFabPulse();
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
    this.enteringCourseId = cc.id;
    this.enteringCourseActive = true;
    this.courseEnterTimer = setTimeout(() => {
      this.courseEnterTimer = -1;
      this.enter(cc);
      this.enteringCourseActive = false;
      this.enteringCourseId = -1;
    }, 260);
  }

  private openForm(): void {
    this.stopFormAnimation();
    this.showForm = true;
    this.formOpenProgress = false;
    this.formTimer = setTimeout(() => {
      this.formOpenProgress = true;
      this.formTimer = -1;
    }, 24);
  }

  private closeForm(): void {
    if (!this.showForm) {
      return;
    }
    this.stopFormAnimation();
    this.formOpenProgress = false;
    this.formTimer = setTimeout(() => {
      this.showForm = false;
      this.formTimer = -1;
    }, 340);
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
      return DEMO_COURSES;
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
    try {
      this.courses = JSON.parse(
        await Api.get(`/courses?user_id=${GlobalState.userId()}`)) as ClassCourse[];
    } catch (e) {
      this.toast(`加载课程失败：${(e as Error).message}`);
    }
  }

  private async createCourse(): Promise<void> {
    if (this.formCourseName.trim() === '' || this.formClassName.trim() === '') {
      this.toast('请填写课程名与班级名');
      return;
    }
    interface CreateBody {
      name: string;
      class_name: string;
      teacher_id: number;
    }

    const body: CreateBody = {
      name: this.formCourseName.trim(),
      class_name: this.formClassName.trim(),
      teacher_id: GlobalState.userId()
    };
    try {
      const cc: ClassCourse = JSON.parse(await Api.post('/courses', body)) as ClassCourse;
      this.toast(`已创建，邀请码 ${cc.invite_code}`);
      this.closeForm();
      this.formCourseName = '';
      this.formClassName = '';
      await this.loadCourses();
    } catch (e) {
      this.toast(`创建失败：${(e as Error).message}`);
    }
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
  topStatCard(value: string, label: string, tint: string) {
    Column({ space: 3 }) {
      Text(value)
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
    Row({ space: AppTheme.SPACE_L }) {
      Column({ space: AppTheme.SPACE_XS }) {
        Text(`${this.greeting}，${this.userName()}`)
          .fontSize(32)
          .fontWeight(FontWeight.Bold)
          .fontColor('#FFFFFF')
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('学生·课堂记录与复习')
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
        this.topStatCard('0', '课程数量', 'rgba(220,244,255,0.90)')
        this.topStatCard('暂无班级', '班级', 'rgba(239,232,255,0.88)')
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
    .opacity(this.isCourseEntering(dc.id) ? 0 : 1)
    .translate({
      x: 0,
      y: this.isCourseEntering(dc.id) ? -18 : (this.hoveredCourseId === dc.id ? -6 : 0)
    })
    .scale({
      x: this.isCourseEntering(dc.id) ? 1.12 : (this.pressedCourseId === dc.id ? 0.96 : 1),
      y: this.isCourseEntering(dc.id) ? 1.12 : (this.pressedCourseId === dc.id ? 0.96 : 1)
    })
    .animation({ duration: this.isCourseEntering(dc.id) ? 260 : 180, curve: Curve.EaseOut })
    .onHover((isHover: boolean) => {
      this.hoveredCourseId = isHover ? dc.id : -1;
    })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressedCourseId = dc.id;
      } else if (event.type === TouchType.Up) {
        this.pressedCourseId = -1;
      }
    })
    .onClick(() => {
      if (!this.isCourseEntering(dc.id)) {
        this.enterDisplay(dc);
      }
    })
  }

  @Builder
  courseGrid() {
    Scroll() {
      Flex({ wrap: FlexWrap.Wrap }) {
        ForEach(this.displayCourses(), (dc: DisplayCourse) => {
          Column() {
            this.courseCard(dc)
          }
          .margin({ right: AppTheme.SPACE_M, bottom: AppTheme.SPACE_L })
        }, (dc: DisplayCourse) => `${dc.id}`)
      }
      .width('100%')
    }
    .layoutWeight(1)
    .scrollBar(BarState.Off)
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
      .translate({ x: 0, y: this.fabPressed ? 5 : 0 })
      .scale({
        x: this.fabPressed ? 0.94 : (this.fabPulse ? 1.02 : 1),
        y: this.fabPressed ? 0.94 : (this.fabPulse ? 1.02 : 1)
      })
      .animation({ duration: this.fabPressed ? 90 : 180, curve: Curve.EaseOut })
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
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.fabPressed = true;
      } else if (event.type === TouchType.Up) {
        this.fabPressed = false;
      }
    })
    .onClick(() => {
      this.fabPressed = false;
      this.openForm();
    })
  }

  @Builder
  formOverlay() {
    Stack({ alignContent: Alignment.Center }) {
      Column()
        .width('100%')
        .height('100%')
        .backdropBlur(28)
        .backgroundColor('rgba(20,34,72,0.22)')
        .opacity(this.formOpenProgress ? 1 : 0)
        .animation({ duration: 220, curve: Curve.EaseOut })
        .onClick(() => {
          this.closeForm();
        })

      Column({ space: AppTheme.SPACE_L }) {
        Text(GlobalState.isTeacher() ? '新建课程' : '加入课程')
          .fontSize(AppTheme.FONT_TITLE)
          .fontWeight(FontWeight.Bold)
          .fontColor(AppTheme.INK)

        if (GlobalState.isTeacher()) {
          TextInput({ placeholder: '课程名，如：数据结构', text: this.formCourseName })
            .fontSize(AppTheme.FONT_BODY)
            .height(44)
            .borderRadius(26)
            .backdropBlur(GLASS_BLUR_STRENGTH)
            .backgroundColor('rgba(255,255,255,0.56)')
            .border({ width: 1.2, color: 'rgba(255,255,255,0.88)' })
            .shadow({ radius: 12, color: 'rgba(83,114,180,0.10)', offsetX: 0, offsetY: 5 })
            .onChange((v: string) => {
              this.formCourseName = v;
            })
          TextInput({ placeholder: '班级名，如：计科2301', text: this.formClassName })
            .fontSize(AppTheme.FONT_BODY)
            .height(44)
            .borderRadius(26)
            .backdropBlur(GLASS_BLUR_STRENGTH)
            .backgroundColor('rgba(255,255,255,0.56)')
            .border({ width: 1.2, color: 'rgba(255,255,255,0.88)' })
            .shadow({ radius: 12, color: 'rgba(83,114,180,0.10)', offsetX: 0, offsetY: 5 })
            .onChange((v: string) => {
              this.formClassName = v;
            })
          Button('创建课程')
            .width('100%')
            .height(44)
            .fontSize(AppTheme.FONT_BODY)
            .fontColor('#FFFFFF')
            .backgroundColor('#3863F0')
            .borderRadius(999)
            .shadow({ radius: 18, color: 'rgba(56,99,240,0.30)', offsetX: 0, offsetY: 8 })
            .onClick(() => {
              this.createCourse();
            })
        } else {
          TextInput({ placeholder: '输入 6 位邀请码', text: this.formInviteCode })
            .fontSize(AppTheme.FONT_BODY)
            .height(44)
            .maxLength(6)
            .borderRadius(26)
            .backdropBlur(GLASS_BLUR_STRENGTH)
            .backgroundColor('rgba(255,255,255,0.56)')
            .border({ width: 1.2, color: 'rgba(255,255,255,0.88)' })
            .shadow({ radius: 12, color: 'rgba(83,114,180,0.10)', offsetX: 0, offsetY: 5 })
            .onChange((v: string) => {
              this.formInviteCode = v;
            })
          Button('加入课程')
            .width('100%')
            .height(44)
            .fontSize(AppTheme.FONT_BODY)
            .fontColor('#FFFFFF')
            .backgroundColor('#3863F0')
            .borderRadius(999)
            .shadow({ radius: 18, color: 'rgba(56,99,240,0.30)', offsetX: 0, offsetY: 8 })
            .onClick(() => {
              this.joinCourse();
            })
        }

        Text('取消')
          .fontSize(AppTheme.FONT_BODY)
          .fontColor(AppTheme.TEXT_TERTIARY)
          .onClick(() => {
            this.closeForm();
          })
      }
      .width(392)
      .padding(AppTheme.SPACE_XL)
      .borderRadius(26)
      .backdropBlur(30)
      .backgroundColor('rgba(255,255,255,0.48)')
      .linearGradient({
        angle: 128,
        colors: [
          ['rgba(255,255,255,0.84)', 0],
          ['rgba(240,250,255,0.60)', 0.48],
          ['rgba(235,229,255,0.52)', 1]
        ]
      })
      .border({ width: 1.5, color: 'rgba(255,255,255,0.92)' })
      .shadow({ radius: 46, color: 'rgba(56,99,240,0.26)', offsetX: 0, offsetY: 20 })
      .opacity(this.formOpenProgress ? 1 : 0)
      .translate({
        x: this.formOpenProgress ? 0 : 540,
        y: this.formOpenProgress ? 0 : 320
      })
      .scale({
        x: this.formOpenProgress ? 1 : 0.14,
        y: this.formOpenProgress ? 1 : 0.14
      })
      .animation({ duration: 320, curve: Curve.EaseOut })
    }
    .width('100%')
    .height('100%')
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

  build() {
    Stack({ alignContent: Alignment.BottomEnd }) {
      this.nativeFluidBackground()

      Column({ space: AppTheme.SPACE_L }) {
        this.topArea()

        Row() {
          Text('我的课程')
            .fontSize(18)
            .fontWeight(FontWeight.Bold)
            .fontColor(AppTheme.INK)
          Blank()
          Text(GlobalState.isTeacher() ? '课程创作台' : '学习空间')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontWeight(FontWeight.Medium)
            .fontColor('#2452B9')
            .padding({ left: 12, right: 12, top: 5, bottom: 5 })
            .borderRadius(999)
            .backdropBlur(GLASS_BLUR_STRENGTH)
            .backgroundColor('rgba(255,255,255,0.66)')
            .border({ width: 1.2, color: GLASS_BORDER_LIGHT })
        }
        .width('100%')
        .padding({ left: AppTheme.SPACE_S, right: 110 })

        Column() {
          this.courseGrid()
        }
        .width('100%')
        .layoutWeight(1)
        .padding({ right: 72 })
      }
      .width('100%')
      .height('100%')
      .padding(AppTheme.SPACE_XXL)

      this.fab()

      if (this.showForm) {
        this.formOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor(BG_BASE)
  }
}
