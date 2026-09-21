import { TouchMotion } from '../common/TouchMotion';
import { deviceInfo } from '@kit.BasicServicesKit';
import { StudyBackdrop } from '../common/components/StudyBackdrop';
import { uiEffect } from '@kit.ArkGraphics2D';
import { hdsEffect } from '@kit.UIDesignKit';
import { GlobalState } from '../service/GlobalState';
import { Api } from '../service/Api';
import { CourseSession, CourseWorkspaceStats } from '../model/Models';

const INK: string = '#173A56';
const MUTED: string = '#526D83';
const BLUE: string = '#155AA5';

/** Student course home. HDS light effects are API 20+, blur is ArkUI material.
 * This does not label ordinary blur as HDS IMMERSIVE (API 23) material.
 * No writes: cards navigate to existing features; course information comes from the active course.
 */
@Component
export struct CrystalStudyPage {
  @StorageLink('reduceMotion') reduceMotion: boolean = false;
  onClose: () => void = () => {};
  onSettings: () => void = () => {};
  onNavigate: (key: string) => void = () => {};
  onOpenLesson: (id: number) => void = () => {};
  @State compact: boolean = true;
  @State canvasWidth: number = 400;
  @State canvasHeight: number = 800;
  @Link detailOpen: boolean;
  @StorageLink('crystalSoftMaterial') subtle: boolean = false;
  @State stats: CourseWorkspaceStats | null = null;
  @State statsError: boolean = false;
  @State lessons: CourseSession[] = [];
  @State lessonsReady: boolean = false;
  @State lessonsError: boolean = false;
  private alive: boolean = false;

  aboutToAppear(): void { this.alive = true; this.loadStats(); this.loadLessons(); }
  aboutToDisappear(): void { this.alive = false; }

  private async loadStats(): Promise<void> {
    this.statsError = false;
    try {
      const result = JSON.parse(await Api.get(`/courses/${GlobalState.courseId()}/stats?user_id=${GlobalState.userId()}`)) as CourseWorkspaceStats;
      if (this.alive) { this.stats = result; }
    } catch (e) { if (this.alive) { this.statsError = true; } }
  }

  private async loadLessons(): Promise<void> {
    this.lessonsError = false;
    this.lessonsReady = false;
    try {
      const all = JSON.parse(await Api.get(`/sessions?class_course_id=${GlobalState.courseId()}&user_id=${GlobalState.userId()}`)) as CourseSession[];
      if (!this.alive) { return; }
      this.lessons = all.filter((item: CourseSession) => item.outline_kind === 'official' && item.outline_status === 'published')
        .sort((a: CourseSession, b: CourseSession) => b.created_at.localeCompare(a.created_at) || b.id - a.id).slice(0, 3);
    } catch (e) { if (this.alive) { this.lessonsError = true; } }
    finally { if (this.alive) { this.lessonsReady = true; } }
  }

  private tabletHeroHeight(): number {
    return Math.max(290, Math.min(370, (this.canvasHeight - 350) * 0.58));
  }

  private tabletEntryHeight(): number {
    return (this.tabletHeroHeight() + 76) / 2;
  }

  private light(source: boolean = false): VisualEffect {
    if (deviceInfo.sdkApiVersion >= 20 && canIUse('SystemCapability.UIDesign.HDSComponent.Core') && !this.subtle) {
      return new hdsEffect.HdsEffectBuilder()
        .pressShadow(hdsEffect.PressShadowType.BLEND_WHITE)
        .pointLight({ sourceType: source ? hdsEffect.PointLightSourceType.SOFT : hdsEffect.PointLightSourceType.NONE,
          illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER,
          options: { color: '#A8EBFF', intensity: 0.35, height: 24, bloom: 0.1 } }).buildEffect();
    }
    return uiEffect.createEffect();
  }


  @Builder
  backdrop() {
    StudyBackdrop()
  }

  @Builder
  crystalIcon(icon: Resource, size: number, tint: string = BLUE) {
    Stack({ alignContent: Alignment.Center }) {
      Column().width(size - 6).height(size - 6).borderRadius(size * 0.27)
        .backgroundColor('#92B8D5').translate({ y: 5 }).opacity(0.45)
      Column().width(size).height(size).borderRadius(size * 0.27)
        .linearGradient({ angle: 135, colors: [['#FFFFFF', 0], ['#E5F3FD', 0.48], ['#B5D5EC', 1]] })
        .border({ width: 1, color: '#F8FCFF' }).shadow({ radius: 16, color: '#204275A0', offsetY: 8 })
      SymbolGlyph(icon).fontSize(size * 0.43).fontColor([tint])
    }.width(size + 8).height(size + 10).visualEffect(this.light())
  }

  @Builder
  topBar() {
    Row({ space: 12 }) {
      Button({ type: ButtonType.Normal }) {
        SymbolGlyph($r('sys.symbol.chevron_left')).fontSize(18).fontColor([INK])
      }.stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).width(44).height(44).borderRadius(18).backgroundColor('#BFFFFFFF')
        .accessibilityText('返回全部课程').onClick(this.onClose)
      Column({ space: 2 }) {
        Text('智慧伴学').fontSize(17).fontWeight(FontWeight.Bold).fontColor(INK)
        Text('我的课程 · 学习空间').fontSize(11).fontColor(MUTED)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      Button(this.subtle ? '柔和' : '通透').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).height(36).fontSize(12).fontColor(BLUE)
        .backgroundColor('#A6FFFFFF').borderRadius(18)
        .accessibilityText('切换界面材质强度').onClick(() => { this.subtle = !this.subtle; })
      Button({ type: ButtonType.Normal }) {
        Text(GlobalState.user?.name.substring(0, 1) ?? '我').fontSize(15).fontColor(BLUE)
      }.stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).width(40).height(40).borderRadius(16).backgroundColor('#C9FFFFFF')
        .border({ width: 1, color: '#EFFFFFFF' }).accessibilityText('个人设置').onClick(this.onSettings)
    }.width('100%').height(68).padding({ left: this.compact ? 18 : 32, right: this.compact ? 18 : 32 })
      .backgroundColor(this.subtle ? '#F2F6FC' : '#60FFFFFF')
      .backgroundBlurStyle(this.subtle ? BlurStyle.NONE : BlurStyle.Thin)
      .border({ width: { bottom: 1 }, color: '#BFFFFFFF' })
  }

  @Builder
  courseHero() {
    Column({ space: 18 }) {
      Row({ space: 14 }) {
        Column({ space: 8 }) {
          Text('我的学习空间').fontSize(12).fontColor(MUTED)
          Text(GlobalState.course?.name ?? '课程').fontSize(this.compact ? 29 : 38)
            .fontWeight(FontWeight.Bold).fontColor(INK).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${GlobalState.course?.class_name ?? ''} · ${GlobalState.course?.teacher_name ?? ''}`)
            .fontSize(13).fontColor(MUTED).maxLines(2)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        this.crystalIcon($r('sys.symbol.book'), this.compact ? 70 : 100)
      }.width('100%')
      Row({ space: 12 }) {
        Button('查看课程').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).height(44).fontSize(14).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
          .padding({ left: 24, right: 24 }).borderRadius(16)
          .backgroundColor('#124B87')
          .linearGradient({ angle: 160, colors: [['#377FB8', 0], ['#175493', 0.7], ['#123C72', 1]] })
          .border({ width: 1, color: '#8BB9DA' }).shadow({ radius: 12, color: '#30406C9A', offsetY: 5 })
          .visualEffect(this.light(true))
          .onClick(() => { this.detailOpen = true; })
        Text('课堂、思考与成长，在这里连接').fontSize(12).fontColor(MUTED).layoutWeight(1).maxLines(2)
      }.width('100%')
      if (this.stats !== null) {
        Row() {
          this.metric(`${this.stats.official_lesson_count}`, '课堂记录')
          this.metric(`${this.stats.class_note_count}`, '班级笔记')
          this.metric(`${this.stats.personal_note_count}`, '个人笔记')
        }.width('100%').padding({ top: 16 }).border({ width: { top: 1 }, color: '#94FFFFFF' })
      } else {
        Row() {
          Text(this.statsError ? '课程统计暂未加载' : '正在加载课程统计').fontSize(12).fontColor(MUTED).layoutWeight(1)
          if (this.statsError) { Button('重试').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).fontSize(12).height(32).backgroundColor('#E9F3FE').fontColor(BLUE)
            .onClick(() => { this.loadStats(); }) }
        }.width('100%')
      }
    }.width('100%').constraintSize({ minHeight: this.compact ? 0 : this.tabletHeroHeight() })
      .justifyContent(this.compact ? FlexAlign.Start : FlexAlign.SpaceBetween)
      .padding(this.compact ? 22 : 30).borderRadius(28)
      .linearGradient({ angle: 135, colors: [[this.subtle ? '#F6FAFF' : '#DCFFFFFF', 0], ['#BFEAF7FF', 0.58], ['#A1C6E2F8', 1]] })
      .border({ width: 1.2, color: '#EDFFFFFF' })
      .shadow({ radius: 24, color: '#18436F9D', offsetY: 12 }).visualEffect(this.light())
  }

  @Builder
  metric(value: string, label: string) {
    Column({ space: 4 }) {
      Text(value).fontSize(24).fontWeight(FontWeight.Medium).fontColor(INK)
      Text(label).fontSize(11).fontColor(MUTED)
    }.layoutWeight(1).alignItems(HorizontalAlign.Start)
  }

  @Builder
  entry(key: string, title: string, desc: string, icon: Resource) {
    Column({ space: 13 }) {
      Row() {
        this.crystalIcon(icon, 44, key === 'ai_meeting' ? '#187E85' : BLUE)
        Blank()
        SymbolGlyph($r('sys.symbol.arrow_up_right')).fontSize(14).fontColor([MUTED])
      }.width('100%')
      Column({ space: 5 }) {
        Text(title).fontSize(17).fontWeight(FontWeight.Bold).fontColor(INK)
        Text(desc).fontSize(11).fontColor(MUTED).maxLines(2)
      }.width('100%').alignItems(HorizontalAlign.Start)
    }.width('100%').padding(this.compact ? 18 : 24)
      .constraintSize({ minHeight: this.compact ? 144 : this.tabletEntryHeight() })
      .justifyContent(this.compact ? FlexAlign.Start : FlexAlign.SpaceBetween).borderRadius(24)
      .linearGradient({ angle: 150, colors: [['#EFFFFFFF', 0], [this.subtle ? '#EDF5FC' : '#A8E7F2FE', 1]] })
      .border({ width: 1, color: '#EFFFFFFF' }).shadow({ radius: 18, color: '#10436591', offsetY: 8 })
      .visualEffect(this.light()).stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'card'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'card')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          })
      .onClick(() => { this.onNavigate(key); }).accessibilityText(`打开${title}`)
  }

  @Builder
  recentLesson(item: CourseSession) {
    Column({ space: 12 }) {
      Row({ space: 10 }) {
        SymbolGlyph($r('sys.symbol.doc_text')).fontSize(20).fontColor([BLUE])
        Text(item.created_at.substring(0, 10)).fontSize(12).fontColor(MUTED).layoutWeight(1)
        SymbolGlyph($r('sys.symbol.arrow_up_right')).fontSize(14).fontColor([MUTED])
      }.width('100%')
      Text(item.ai_title || item.title).fontSize(19).fontWeight(FontWeight.Bold).fontColor(INK)
        .maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis }).width('100%')
      Text('查看已发布的课程提纲').fontSize(12).fontColor(MUTED).width('100%')
    }.width('100%').constraintSize({ minHeight: 146 }).padding(22).borderRadius(24)
      .justifyContent(FlexAlign.SpaceBetween).backgroundColor(this.subtle ? '#EFF5FA' : '#ADFFFFFF')
      .border({ width: 1, color: '#EAFFFFFF' }).visualEffect(this.light())
      .stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'card'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'card')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          })
      .onClick(() => { this.onOpenLesson(item.id); })
      .accessibilityText(`打开课程提纲：${item.ai_title || item.title}`)
  }

  @Builder
  recentLessons() {
    Column({ space: 14 }) {
      Row() {
        Column({ space: 4 }) {
          Text('近期课堂').fontSize(20).fontWeight(FontWeight.Bold).fontColor(INK)
          Text('从最近一堂课，继续理解与积累').fontSize(12).fontColor(MUTED)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        Button('全部课堂  ›').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).height(40).fontSize(13).fontColor(BLUE).backgroundColor('#BDFFFFFF')
          .onClick(() => { this.onNavigate('class'); })
      }.width('100%')
      if (!this.lessonsReady || this.lessonsError || this.lessons.length === 0) {
        Row({ space: 20 }) {
          this.crystalIcon($r('sys.symbol.folder'), 48)
          Column({ space: 8 }) {
            Text(!this.lessonsReady ? '正在整理近期课堂' : this.lessonsError ? '近期课堂暂未加载' : '等待下一次课堂相遇')
              .fontSize(18).fontWeight(FontWeight.Medium).fontColor(INK)
            Text(this.lessonsError ? '可以重试，或从“全部课堂”查看课程内容。' : '老师发布课程提纲后，会在这里显示。')
              .fontSize(13).fontColor(MUTED)
          }.layoutWeight(1).alignItems(HorizontalAlign.Start)
          if (this.lessonsError) {
            Button('重试').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).fontSize(13).fontColor(BLUE).backgroundColor('#DFFFFFFF')
              .onClick(() => { this.loadLessons(); })
          }
        }.width('100%').padding(24).constraintSize({ minHeight: 146 })
          .backgroundColor('#90FFFFFF').borderRadius(24).border({ width: 1, color: '#EFFFFFFF' })
      } else {
        Row({ space: 16 }) {
          ForEach(this.lessons, (item: CourseSession) => {
            Column() { this.recentLesson(item) }.layoutWeight(1)
          }, (item: CourseSession) => `${item.id}`)
        }.width('100%').alignItems(VerticalAlign.Top)
      }
    }.width('100%')
  }

  @Builder
  entries() {
    Column({ space: 12 }) {
      Row() {
        Text('开始学习').fontSize(20).fontWeight(FontWeight.Bold).fontColor(INK)
        Blank()
        Text('从课堂到掌握').fontSize(12).fontColor(MUTED)
      }.width('100%').padding({ bottom: 2 })
      Row({ space: 12 }) {
        Column() { this.entry('class', '课程', '课次提纲与学习资料', $r('sys.symbol.folder')) }.layoutWeight(1)
        Column() { this.entry('ai_meeting', 'AI学习小组', '与同学和 AI 一起讨论', $r('sys.symbol.person_2')) }.layoutWeight(1)
      }.width('100%')
      Row({ space: 12 }) {
        Column() { this.entry('practice', '巩固练习', '围绕课程重点练习', $r('sys.symbol.checkmark')) }.layoutWeight(1)
        Column() { this.entry('notes', '学习笔记', '整理每一次新的理解', $r('sys.symbol.doc_text')) }.layoutWeight(1)
      }.width('100%')
    }.width('100%')
  }

  @Builder
  aiCard() {
    Row({ space: 16 }) {
      this.crystalIcon($r('sys.symbol.lightbulb'), 50, '#187E85')
      Column({ space: 6 }) {
        Text('让问题，有回响').fontSize(19).fontWeight(FontWeight.Bold).fontColor(INK)
        Text('结合课程资料，和 AI 一起理清思路').fontSize(12).fontColor(MUTED).maxLines(2)
      }.layoutWeight(1).alignItems(HorizontalAlign.Start)
      SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(16).fontColor([BLUE])
    }.width('100%').padding(20).borderRadius(24)
      .linearGradient({ angle: 130, colors: [['#DFFFFFFF', 0], ['#BCD4EEF1', 1]] })
      .border({ width: 1, color: '#F0FFFFFF' }).visualEffect(this.light())
      .stateStyles({
        normal: { .translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
        pressed: { .translate(TouchMotion.pressedOffset(this.reduceMotion, 'card')).animation(TouchMotion.press(this.reduceMotion)) }
      })
      .onClick(() => { this.onNavigate('course_ai'); })
  }

  @Builder
  dock() {
    Row({ space: 8 }) {
      Row({ space: 4 }) {
        ForEach(['课程', '小组', '练习', '笔记'], (label: string, index: number) => {
          Button(label).stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).layoutWeight(1).height(42).fontSize(13).fontColor(index === 0 ? BLUE : MUTED)
            .backgroundColor(index === 0 ? '#CBFFFFFF' : Color.Transparent).borderRadius(18)
            .onClick(() => { this.onNavigate(['class', 'ai_meeting', 'practice', 'notes'][index]); })
        })
      }.layoutWeight(1).padding(6).borderRadius(24).backgroundColor(this.subtle ? '#F2F6FC' : '#80FFFFFF')
        .backgroundBlurStyle(this.subtle ? BlurStyle.NONE : BlurStyle.Thin)
        .border({ width: 1, color: '#EFFFFFFF' }).shadow({ radius: 18, color: '#1D32669D', offsetY: 6 })
      Button('AI').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).fontSize(19).fontWeight(FontWeight.Bold).fontColor('#FFFFFF').width(56).height(56).borderRadius(22)
        .backgroundColor('#124B87')
        .linearGradient({ angle: 150, colors: [['#5B9CC9', 0], ['#2362A0', 0.55], ['#1A437C', 1]] })
        .border({ width: 1.2, color: '#CCE9FA' }).shadow({ radius: 14, color: '#405780A9', offsetY: 6 })
        .visualEffect(this.light(true)).accessibilityText('打开课程 AI 助手').onClick(() => { this.onNavigate('course_ai'); })
    }.width('100%').constraintSize({ maxWidth: 560 }).padding({ left: 18, right: 18, top: 10, bottom: 16 })
  }

  @Builder
  details() {
    Stack({ alignContent: this.compact ? Alignment.Bottom : Alignment.Center }) {
      Column().width('100%').height('100%').backgroundColor('#55183250').onClick(() => { this.detailOpen = false; })
      Column({ space: 22 }) {
        Row() {
          Text('课程详情').fontSize(14).fontColor(MUTED).layoutWeight(1)
          Button({ type: ButtonType.Normal }) { SymbolGlyph($r('sys.symbol.xmark')).fontSize(16).fontColor([INK]) }.stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          })
            .width(44).height(44).borderRadius(18).backgroundColor('#BFFFFFFF').accessibilityText('关闭课程详情')
            .onClick(() => { this.detailOpen = false; })
        }.width('100%')
        Row({ space: 18 }) {
          this.crystalIcon($r('sys.symbol.book'), 64)
          Text(GlobalState.course?.name ?? '').fontSize(28).fontWeight(FontWeight.Bold).fontColor(INK).layoutWeight(1)
        }.width('100%')
        Column({ space: 16 }) {
          Text(`授课教师    ${GlobalState.course?.teacher_name ?? '待补充'}`).fontSize(15).fontColor(INK).width('100%')
          Text(`所属班级    ${GlobalState.course?.class_name ?? '待补充'}`).fontSize(15).fontColor(INK).width('100%')
          Text(`课程邀请码    ${GlobalState.course?.invite_code ?? ''}`).fontSize(15).fontColor(INK).width('100%')
        }.width('100%').padding(20).borderRadius(18).backgroundColor('#BFFFFFFF')
        Button('进入课堂').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).width('100%').height(48).fontSize(16).fontColor('#FFFFFF').backgroundColor(BLUE).borderRadius(18)
          .visualEffect(this.light(true)).onClick(() => { this.onNavigate('class'); })
      }.width(this.compact ? '94%' : 500).padding(26).borderRadius(30).margin({ bottom: this.compact ? 12 : 0 })
        .backgroundColor(this.subtle ? '#F2F6FC' : '#DEEDF5FF')
        .backgroundBlurStyle(this.subtle ? BlurStyle.NONE : BlurStyle.Thick)
        .border({ width: 1.2, color: '#F0FFFFFF' }).shadow({ radius: 32, color: '#30345277', offsetY: 12 })
    }.width('100%').height('100%')
      .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 18 }))
        .animation({ duration: this.reduceMotion ? 0 : 220, curve: TouchMotion.enter() }))
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      this.backdrop()
      Column() {
        this.topBar()
        Scroll() {
          Column({ space: 24 }) {
            if (this.compact) {
              this.courseHero()
              this.entries()
              this.aiCard()
            } else {
              Row({ space: 24 }) {
                Column({ space: 24 }) { this.courseHero(); this.aiCard() }.layoutWeight(1.1)
                Column() { this.entries() }.layoutWeight(1)
              }.width('100%').alignItems(VerticalAlign.Top)
              this.recentLessons()
            }
          }.width('100%').constraintSize({ maxWidth: 1440 }).padding({ left: this.compact ? 18 : 36,
            right: this.compact ? 18 : 36, top: this.compact ? 22 : 24, bottom: this.compact ? 104 : 24 })
        }.width('100%').layoutWeight(1).align(Alignment.Top).scrollBar(BarState.Off)
        if (!this.compact) { this.dock() }
      }.width('100%').height('100%')
      if (this.compact) { this.dock() }
      if (this.detailOpen) { this.details() }
    }.width('100%').height('100%').backgroundColor('#EAF3FA')
      .onAreaChange((oldArea: Area, newArea: Area) => {
        this.canvasWidth = Number(newArea.width);
        this.canvasHeight = Number(newArea.height);
        this.compact = this.canvasWidth < 840;
      })
  }
}
