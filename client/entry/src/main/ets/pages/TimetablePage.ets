import { TouchMotion } from '../common/TouchMotion';
import { LearningTheme as AppTheme } from '../common/LearningTheme';
import { ClassCourse } from '../model/Models';
import { Api } from '../service/Api';
import { GlobalState } from '../service/GlobalState';

interface ScheduleEntry {
  semester_start: string;
  id: number;
  class_course_id: number;
  weekday: number;
  start_section: number;
  end_section: number;
  start_week: number;
  end_week: number;
  week_type: string;
  location: string;
}

interface ScheduleData {
  semester_start: string;
  configured: boolean;
  multiple_semesters: boolean;
  entries: ScheduleEntry[];
}

interface ScheduleBlock { start: number; end: number; entries: ScheduleEntry[]; }

const DAYS: string[] = ['一', '二', '三', '四', '五', '六', '日'];
const SECTIONS: number[] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12];
const TINTS: string[] = ['#E0F6F0', '#E8EFFF', '#FFF0DB', '#FCE7EA', '#E3F3F7'];
const INKS: string[] = ['#00795C', '#305FC3', '#935B12', '#B54159', '#16708A'];
const SLOT_HEIGHT: number = 58;

@Component
export struct TimetablePage {
  @StorageLink('reduceMotion') reduceMotion: boolean = false;
  @Prop courses: ClassCourse[] = [];
  @Prop @Watch('refreshSchedule') revision: number = 0;
  onEnterCourse: (course: ClassCourse) => void = () => {};
  onJoinCourse: () => void = () => {};
  onOpenSettings: () => void = () => {};
  @State entries: ScheduleEntry[] = [];
  @State semesterStart: string = '';
  @State weekMonday: number = 0;
  @State loading: boolean = true;
  @State error: string = '';
  @State multipleSemesters: boolean = false;
  @State configured: boolean = false;
  @State conflictingEntries: ScheduleEntry[] = [];
  private requestVersion: number = 0;
  @State showCourses: boolean = false;
  @State selectedCourse: ClassCourse | null = null;
  @State selectedEntry: ScheduleEntry | null = null;

  aboutToAppear(): void {
    this.weekMonday = this.monday(new Date()).getTime();
    this.load();
  }

  private refreshSchedule(): void { this.load(); }

  private monday(date: Date): Date {
    const result = new Date(date.getFullYear(), date.getMonth(), date.getDate());
    result.setDate(result.getDate() - (result.getDay() + 6) % 7);
    return result;
  }

  private iso(date: Date): string {
    return `${date.getFullYear()}-${`${date.getMonth() + 1}`.padStart(2, '0')}-${`${date.getDate()}`.padStart(2, '0')}`;
  }

  private parseDate(value: string): Date {
    const parts = value.split('-');
    return new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2]));
  }

  private weekNumber(start: string = this.semesterStart): number {
    if (start === '') { return 1; }
    return Math.round((this.weekMonday - this.parseDate(start).getTime()) / 604800000) + 1;
  }

  private dayDate(index: number): Date {
    const value = new Date(this.weekMonday);
    value.setDate(value.getDate() + index);
    return value;
  }

  private weekRange(): string {
    const start = this.dayDate(0);
    const end = this.dayDate(6);
    return `${start.getFullYear()} / ${start.getMonth() + 1}.${start.getDate()} 至 ${end.getMonth() + 1}.${end.getDate()}`;
  }

  private shiftWeek(offset: number): void {
    const value = new Date(this.weekMonday);
    value.setDate(value.getDate() + offset * 7);
    this.weekMonday = value.getTime();
  }

  private isToday(index: number): boolean {
    return this.iso(this.dayDate(index)) === this.iso(new Date());
  }

  private courseFor(id: number): ClassCourse | undefined {
    return this.courses.find((course: ClassCourse) => course.id === id);
  }

  private weekEntries(day: number = 0): ScheduleEntry[] {
    return this.entries.filter((entry: ScheduleEntry) => {
      const week = this.weekNumber(entry.semester_start);
      return (day === 0 || entry.weekday === day) && week >= entry.start_week && week <= entry.end_week &&
        (entry.week_type === 'all' || week % 2 === (entry.week_type === 'odd' ? 1 : 0)) &&
        this.courseFor(entry.class_course_id) !== undefined;
    });
  }

  private dayBlocks(day: number): ScheduleBlock[] {
    const entries = this.weekEntries(day).sort((a: ScheduleEntry, b: ScheduleEntry) => a.start_section - b.start_section);
    const blocks: ScheduleBlock[] = [];
    entries.forEach((entry: ScheduleEntry) => {
      const last = blocks[blocks.length - 1];
      if (last !== undefined && entry.start_section <= last.end) {
        last.end = Math.max(last.end, entry.end_section);
        last.entries.push(entry);
      } else { blocks.push({ start: entry.start_section, end: entry.end_section, entries: [entry] }); }
    });
    return blocks;
  }

  private openBlock(block: ScheduleBlock): void {
    if (block.entries.length === 1) { this.openEntry(block.entries[0]); }
    else { this.conflictingEntries = block.entries; }
  }

  private unscheduled(): ClassCourse[] {
    return this.courses.filter((course: ClassCourse) => !this.entries.some(
      (entry: ScheduleEntry) => entry.class_course_id === course.id));
  }

  private async load(): Promise<void> {
    const version = ++this.requestVersion;
    this.loading = true;
    this.error = '';
    try {
      const data = JSON.parse(await Api.get('/timetable')) as ScheduleData;
      if (version !== this.requestVersion) { return; }
      this.entries = data.entries;
      this.multipleSemesters = data.multiple_semesters;
      this.configured = data.configured;
      this.semesterStart = data.semester_start;
    } catch (e) { if (version === this.requestVersion) { this.error = `课表加载失败：${(e as Error).message}`; } }
    finally { if (version === this.requestVersion) { this.loading = false; } }
  }

  private openEntry(entry: ScheduleEntry): void {
    const course = this.courseFor(entry.class_course_id);
    if (course !== undefined) {
      this.conflictingEntries = [];
      this.selectedCourse = course;
      this.selectedEntry = entry;
    }
  }

  @Builder
  iconButton(icon: Resource, label: string, action: () => void) {
    Button({ type: ButtonType.Normal }) {
      SymbolGlyph(icon).fontSize(19).fontColor([AppTheme.INK])
    }.stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).width(44).height(44).borderRadius(12).backgroundColor(AppTheme.BG_CARD)
      .border({ width: 1, color: AppTheme.DIVIDER })
      .accessibilityText(label).onClick(action)
  }

  @Builder
  header() {
    Column({ space: 12 }) {
      Row({ space: 8 }) {
        Image($r('app.media.app_icon')).width(34).height(34).borderRadius(8)
        Column({ space: 2 }) {
          Text('我的课表').fontSize(26).fontWeight(FontWeight.Bold).fontColor(AppTheme.INK)
          Text(GlobalState.user?.name ?? '').fontSize(12).fontColor(AppTheme.TEXT_SECONDARY).maxLines(1)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        this.iconButton($r('sys.symbol.arrow_clockwise'), '刷新课表', () => { this.load(); })
        this.iconButton($r('sys.symbol.gearshape'), '个人设置', this.onOpenSettings)
      }.width('100%')
      Row({ space: 8 }) {
        this.iconButton($r('sys.symbol.chevron_left'), '上一周', () => { this.shiftWeek(-1); })
        Column({ space: 3 }) {
          Text(!this.configured || this.multipleSemesters ? '课程周历' : this.weekNumber() < 1 ? '开学前' : `第 ${this.weekNumber()} 周`)
            .fontSize(19).fontWeight(FontWeight.Bold).fontColor(AppTheme.INK)
          Text(this.weekRange()).fontSize(11).fontColor(AppTheme.TEXT_SECONDARY)
        }.layoutWeight(1)
        this.iconButton($r('sys.symbol.chevron_right'), '下一周', () => { this.shiftWeek(1); })
        Button('本周').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).height(40).fontSize(12).fontColor(AppTheme.PRIMARY).backgroundColor(AppTheme.PRIMARY_LIGHT).borderRadius(12)
          .onClick(() => { this.weekMonday = this.monday(new Date()).getTime(); })
      }.width('100%').padding(12).borderRadius(22).backgroundColor(AppTheme.BG_CARD)
        .border({ width: 1, color: '#EDFFFFFF' })
        .border({ width: 1, color: AppTheme.DIVIDER })
      Row() {
        Text(`${this.weekEntries().length} 次课`).fontSize(12).fontColor(AppTheme.TEXT_SECONDARY)
        Blank()
        Text(this.multipleSemesters ? '按各课程学期计算' : this.configured ? `学期起始 ${this.semesterStart}` : '暂无上课时间')
          .fontSize(11).fontColor(AppTheme.TEXT_SECONDARY)
      }.width('100%')
    }.width('100%').padding({ left: 16, right: 16, top: 16, bottom: 12 })
  }

  @Builder
  weekGrid() {
    Column() {
      Row({ space: 2 }) {
        Text('节').fontSize(10).fontColor('#74817D').width(24).textAlign(TextAlign.Center)
        ForEach(DAYS, (day: string, index: number) => {
          Column({ space: 4 }) {
            Text(day).fontSize(11).fontColor(this.isToday(index) ? '#FFFFFF' : AppTheme.TEXT_SECONDARY)
            Text(`${this.dayDate(index).getDate()}`).fontSize(15).fontWeight(FontWeight.Bold)
              .fontColor(this.isToday(index) ? '#FFFFFF' : AppTheme.INK)
          }.layoutWeight(1).height(50).justifyContent(FlexAlign.Center).borderRadius(8)
            .backgroundColor(this.isToday(index) ? AppTheme.PRIMARY : AppTheme.BG_CARD)
            .foregroundColor(this.isToday(index) ? '#FFFFFF' : '#4A5C55')
        })
      }.width('100%').margin({ bottom: 8 })
      Row({ space: 2 }) {
        Column() {
          ForEach(SECTIONS, (section: number) => {
            Column({ space: 2 }) {
              Text(`${section}`).fontSize(12).fontWeight(FontWeight.Medium).fontColor('#5E7067')
              if (section === 1 || section === 5 || section === 9) {
                Text(section === 1 ? '上午' : section === 5 ? '下午' : '晚间').fontSize(8).fontColor('#82928B')
              }
            }.height(SLOT_HEIGHT).width(24).padding({ top: 8 })
          })
        }.width(24)
        ForEach(DAYS, (day: string, index: number) => {
          Stack({ alignContent: Alignment.TopStart }) {
            Column() {
              ForEach(SECTIONS, (section: number) => {
                Column().height(SLOT_HEIGHT).width('100%')
                  .border({ width: { bottom: 1 }, color: '#E8EFEB' })
                  .backgroundColor(this.isToday(index) ? '#DCEBF8' : '#BFFFFFFF')
              })
            }.width('100%')
            ForEach(this.dayBlocks(index + 1), (block: ScheduleBlock) => {
              Column({ space: 4 }) {
                Text(block.entries.length > 1 ? `${block.entries.length} 个时段冲突` :
                  this.courseFor(block.entries[0].class_course_id)?.name ?? '')
                  .fontSize(11).fontWeight(FontWeight.Medium).maxLines(3).textOverflow({ overflow: TextOverflow.Ellipsis })
                  .fontColor(block.entries.length > 1 ? '#B54159' : INKS[block.entries[0].class_course_id % INKS.length])
                if (block.end > block.start) {
                  Text(block.entries.length > 1 ? block.entries.map((entry: ScheduleEntry) =>
                    this.courseFor(entry.class_course_id)?.name ?? '').join('、') : block.entries[0].location || '教室待定')
                    .fontSize(9).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
                  Text(`${block.start}–${block.end}节`).fontSize(9)
                }
              }.width('100%').height((block.end - block.start + 1) * SLOT_HEIGHT - 4)
                .padding({ left: 3, right: 3, top: 7, bottom: 4 }).alignItems(HorizontalAlign.Start).borderRadius(6)
                .backgroundColor(block.entries.length > 1 ? '#FCE7EA' : TINTS[block.entries[0].class_course_id % TINTS.length])
                .position({ x: 0, y: (block.start - 1) * SLOT_HEIGHT }).clip(true)
                .accessibilityText(block.entries.map((entry: ScheduleEntry) =>
                  `${this.courseFor(entry.class_course_id)?.name} 周${day} 第${entry.start_section}到${entry.end_section}节`).join('、'))
                .onClick(() => { this.openBlock(block); })
            }, (block: ScheduleBlock) => JSON.stringify(block))
          }.layoutWeight(1).height(SLOT_HEIGHT * 12)
        })
      }.width('100%').alignItems(VerticalAlign.Top)
    }.width('100%')
  }

  @Builder
  courseList(courses: ClassCourse[]) {
    ForEach(courses, (course: ClassCourse) => {
      Row({ space: 12 }) {
        Text(course.name.substring(0, 1)).fontSize(16).fontWeight(FontWeight.Bold)
          .width(38).height(38).textAlign(TextAlign.Center).borderRadius(8)
          .backgroundColor(TINTS[course.id % TINTS.length]).fontColor(INKS[course.id % INKS.length])
        Column({ space: 4 }) {
          Text(course.name).fontSize(15).fontWeight(FontWeight.Medium).maxLines(1).textOverflow({ overflow: TextOverflow.Ellipsis })
          Text(`${course.class_name} · ${course.teacher_name ?? ''}`).fontSize(11).fontColor(AppTheme.TEXT_SECONDARY).maxLines(1)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        SymbolGlyph($r('sys.symbol.chevron_right')).fontSize(14).fontColor(['#78877F'])
      }.width('100%').padding({ top: 12, bottom: 12 })
        .border({ width: { bottom: 1 }, color: '#E6EDE9' })
        .onClick(() => { this.selectedCourse = course; this.selectedEntry = null; })
    }, (course: ClassCourse) => `${course.id}`)
  }

  @Builder
  detail() {
    Column({ space: 16 }) {
      Row({ space: 12 }) {
        Text(this.selectedCourse?.name.substring(0, 1) ?? '').fontSize(28).fontWeight(FontWeight.Bold)
          .width(64).height(64).textAlign(TextAlign.Center).backgroundColor(AppTheme.PRIMARY_LIGHT).fontColor(AppTheme.PRIMARY).borderRadius(16)
        Column({ space: 6 }) {
          Text(this.selectedCourse?.name ?? '').fontSize(24).fontWeight(FontWeight.Bold).fontColor(AppTheme.INK)
          Text(this.selectedCourse?.class_name ?? '').fontSize(13).fontColor(AppTheme.TEXT_SECONDARY)
        }.layoutWeight(1).alignItems(HorizontalAlign.Start)
        this.iconButton($r('sys.symbol.xmark'), '关闭详情', () => { this.selectedCourse = null; })
      }.width('100%')
      Text(this.selectedCourse?.teacher_name ?? '教师信息待补充').width('100%').fontSize(15).fontColor(AppTheme.TEXT_SECONDARY)
      if (this.selectedEntry !== null) {
        Text(`周${DAYS[this.selectedEntry.weekday - 1]} · 第 ${this.selectedEntry.start_section}–${this.selectedEntry.end_section} 节`)
          .width('100%').fontSize(17).fontWeight(FontWeight.Medium)
        Text(`${this.selectedEntry.location || '教室待定'} · 第 ${this.selectedEntry.start_week}–${this.selectedEntry.end_week} 周 · ${this.selectedEntry.week_type === 'odd' ? '单周' : this.selectedEntry.week_type === 'even' ? '双周' : '每周'}`)
          .width('100%').fontSize(13).fontColor(AppTheme.TEXT_SECONDARY)
      }
      if (this.selectedEntry !== null) {
        Text(`学期第 1 周：${this.selectedEntry.semester_start}`).width('100%').fontSize(13).fontColor(AppTheme.TEXT_SECONDARY)
      } else if (!this.entries.some((entry: ScheduleEntry) => entry.class_course_id === this.selectedCourse?.id)) {
        Text(this.selectedCourse?.is_personal ? '个人空间' : '教师尚未安排上课时间').width('100%').fontSize(13).fontColor(AppTheme.TEXT_SECONDARY)
      }
      if (this.selectedCourse?.invite_code) {
        Text(`邀请码  ${this.selectedCourse?.invite_code}`).width('100%').fontSize(13).fontColor(AppTheme.PRIMARY)
      }
      Button('进入课程').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).width('100%').height(48).borderRadius(12).backgroundColor(AppTheme.PRIMARY).fontColor('#FFFFFF')
        .onClick(() => { if (this.selectedCourse !== null) { this.onEnterCourse(this.selectedCourse); } })

    }.width('100%').padding(20).backgroundColor('#FFFFFF').borderRadius(16)
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        this.header()
        if (this.loading) {
          Column({ space: 12 }) {
            LoadingProgress().width(32).height(32).color('#00795C')
            Text('正在加载课表').fontSize(14).fontColor(AppTheme.TEXT_SECONDARY)
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center)
        } else if (this.error !== '') {
          Column({ space: 14 }) {
            Text(this.error).fontSize(14).fontColor(AppTheme.TEXT_SECONDARY)
            Button('重新加载').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).backgroundColor('#00795C').onClick(() => { this.load(); })
          }.width('100%').layoutWeight(1).justifyContent(FlexAlign.Center).padding(24)
        } else {
          Scroll() {
            Column({ space: 12 }) {
              if (this.weekEntries().length === 0) {
                Text(this.entries.length === 0 ? '教师尚未安排上课时间' : '本周没有课程安排')
                  .width('100%').fontSize(13).fontColor('#5E7067').padding(10).backgroundColor('#EAF4EE')
              }
              this.weekGrid()
              if (this.unscheduled().length > 0) {
                Text(`未安排时间的课程 · ${this.unscheduled().length}`).width('100%').fontSize(16).fontWeight(FontWeight.Bold).margin({ top: 12 })
                this.courseList(this.unscheduled())
              }
              if (this.courses.length === 0) {
                Button('加入第一门课程').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).height(44).backgroundColor('#00795C').onClick(this.onJoinCourse)
              }
            }.width('100%').padding({ left: 10, right: 10, bottom: 20 })
          }.layoutWeight(1).width('100%').align(Alignment.Top).scrollBar(BarState.Off)
        }
        Row({ space: 12 }) {
          Button(`全部课程 · ${this.courses.length}`).stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).layoutWeight(1).height(44).borderRadius(12).fontSize(14)
            .fontColor(AppTheme.PRIMARY).backgroundColor(AppTheme.PRIMARY_LIGHT).onClick(() => { this.showCourses = true; })
          Button('加入课程').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).layoutWeight(1).height(44).borderRadius(12).fontSize(14)
            .fontColor('#FFFFFF').backgroundColor(AppTheme.PRIMARY).onClick(this.onJoinCourse)
        }.width('100%').padding({ left: 16, right: 16, top: 10, bottom: 12 }).backgroundColor('#FFFFFF')
      }.width('100%').height('100%')
      if (this.showCourses || this.selectedCourse !== null || this.conflictingEntries.length > 0) {
        Stack({ alignContent: Alignment.Bottom }) {
          Column().width('100%').height('100%').backgroundColor('rgba(20,36,28,0.32)')
            .onClick(() => { this.showCourses = false; this.selectedCourse = null; this.conflictingEntries = []; })
          Scroll() {
            if (this.conflictingEntries.length > 0) {
              Column({ space: 12 }) {
                Row() {
                  Text('上课时间冲突').fontSize(20).fontWeight(FontWeight.Bold).layoutWeight(1)
                  this.iconButton($r('sys.symbol.xmark'), '关闭冲突列表', () => { this.conflictingEntries = []; })
                }.width('100%')
                ForEach(this.conflictingEntries, (entry: ScheduleEntry) => {
                  Button(`${this.courseFor(entry.class_course_id)?.name} · ${entry.start_section}–${entry.end_section}节`).stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          })
                    .width('100%').height(48).fontColor('#B54159').backgroundColor('#FCE7EA').borderRadius(8)
                    .onClick(() => { this.openEntry(entry); })
                }, (entry: ScheduleEntry) => `${entry.id}`)
              }.width('100%').padding(20).backgroundColor('#FFFFFF').borderRadius(8)
            } else if (this.selectedCourse !== null) { this.detail() }
            else {
              Column({ space: 10 }) {
                Row() {
                  Text('全部课程').fontSize(22).fontWeight(FontWeight.Bold).layoutWeight(1)
                  this.iconButton($r('sys.symbol.xmark'), '关闭课程列表', () => { this.showCourses = false; })
                }.width('100%')
                this.courseList(this.courses)
                Button('加入课程').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).width('100%').height(44).backgroundColor('#00795C')
                  .onClick(() => { this.showCourses = false; this.onJoinCourse(); })
              }.width('100%').padding(20).backgroundColor('#FFFFFF').borderRadius(8)
            }
          }.width('100%').constraintSize({ maxHeight: '92%', maxWidth: 520 }).align(Alignment.Bottom).scrollBar(BarState.Off)
        }.width('100%').height('100%')
          .transition(TransitionEffect.OPACITY.combine(TransitionEffect.translate({ y: 24 }))
            .animation({ duration: this.reduceMotion ? 0 : 240, curve: TouchMotion.enter() }))
      }
    }.width('100%').height('100%').backgroundColor(AppTheme.BG_PAGE)
  }
}
