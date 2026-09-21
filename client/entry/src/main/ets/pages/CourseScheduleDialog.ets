import { TouchMotion } from '../common/TouchMotion';
import { AppTheme } from '../common/AppTheme';
import { ClassCourse } from '../model/Models';
import { Api } from '../service/Api';
import { GlobalState } from '../service/GlobalState';

const DAYS: string[] = ['周一', '周二', '周三', '周四', '周五', '周六', '周日'];
let nextSlotKey: number = 0;

interface SlotBody {
  weekday: number;
  start_section: number;
  end_section: number;
  start_week: number;
  end_week: number;
  week_type: string;
  location: string;
}
interface ScheduleBody { semester_start: string; slots: SlotBody[]; }
interface CreateBody { name: string; class_name: string; teacher_id: number; schedule: ScheduleBody; }

@Observed
class SlotDraft {
  key: number = nextSlotKey++;
  weekday: number = 1;
  start_section: number = 1;
  end_section: number = 2;
  start_week: number = 1;
  end_week: number = 20;
  week_type: string = 'all';
  location: string = '';

  static from(body: SlotBody): SlotDraft {
    const draft = new SlotDraft();
    draft.weekday = body.weekday;
    draft.start_section = body.start_section;
    draft.end_section = body.end_section;
    draft.start_week = body.start_week;
    draft.end_week = body.end_week;
    draft.week_type = body.week_type;
    draft.location = body.location;
    return draft;
  }

  body(): SlotBody {
    return { weekday: this.weekday, start_section: this.start_section, end_section: this.end_section,
      start_week: this.start_week, end_week: this.end_week, week_type: this.week_type, location: this.location.trim() };
  }
}

@Component
struct SlotEditor {
  @StorageLink('reduceMotion') reduceMotion: boolean = false;
  @ObjectLink slot: SlotDraft;
  index: number = 0;
  onRemove: () => void = () => {};

  build() {
    Column({ space: 10 }) {
      Row() {
        Text(`时段 ${this.index + 1}`).fontSize(15).fontWeight(FontWeight.Medium).layoutWeight(1)
        Button({ type: ButtonType.Normal }) {
          SymbolGlyph($r('sys.symbol.trash')).fontSize(18).fontColor(['#B54159'])
        }.stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).width(40).height(40).backgroundColor(Color.Transparent).accessibilityText('删除时段').onClick(this.onRemove)
      }.width('100%')
      Row({ space: 10 }) {
        Select(DAYS.map((day: string): SelectOption => { return { value: day }; }))
          .selected(this.slot.weekday - 1).value(DAYS[this.slot.weekday - 1]).layoutWeight(1)
          .onSelect((index: number) => { this.slot.weekday = index + 1; })
        Select([{ value: '每周' }, { value: '单周' }, { value: '双周' }])
          .selected(['all', 'odd', 'even'].indexOf(this.slot.week_type))
          .value(this.slot.week_type === 'all' ? '每周' : this.slot.week_type === 'odd' ? '单周' : '双周')
          .layoutWeight(1).onSelect((index: number) => { this.slot.week_type = ['all', 'odd', 'even'][index]; })
      }.width('100%')
      Text('节次（1–12）').width('100%').fontSize(12).fontColor(AppTheme.TEXT_SECONDARY)
      Row({ space: 8 }) {
        TextInput({ text: this.slot.start_section ? `${this.slot.start_section}` : '', placeholder: '开始节次' })
          .layoutWeight(1).height(40).type(InputType.Number).maxLength(2)
          .onChange((value: string) => { this.slot.start_section = Number(value); })
        Text('至').fontSize(13)
        TextInput({ text: this.slot.end_section ? `${this.slot.end_section}` : '', placeholder: '结束节次' })
          .layoutWeight(1).height(40).type(InputType.Number).maxLength(2)
          .onChange((value: string) => { this.slot.end_section = Number(value); })
      }.width('100%')
      Text('周次（1–30）').width('100%').fontSize(12).fontColor(AppTheme.TEXT_SECONDARY)
      Row({ space: 8 }) {
        TextInput({ text: this.slot.start_week ? `${this.slot.start_week}` : '', placeholder: '开始周次' })
          .layoutWeight(1).height(40).type(InputType.Number).maxLength(2)
          .onChange((value: string) => { this.slot.start_week = Number(value); })
        Text('至').fontSize(13)
        TextInput({ text: this.slot.end_week ? `${this.slot.end_week}` : '', placeholder: '结束周次' })
          .layoutWeight(1).height(40).type(InputType.Number).maxLength(2)
          .onChange((value: string) => { this.slot.end_week = Number(value); })
      }.width('100%')
      TextInput({ text: this.slot.location, placeholder: '教室 / 上课地点（选填）' }).height(40).maxLength(100)
        .onChange((value: string) => { this.slot.location = value; })
    }.width('100%').padding({ top: 8, bottom: 16 }).border({ width: { bottom: 1 }, color: '#E5E9ED' })
  }
}

@Component
export struct CourseScheduleDialog {
  @StorageLink('reduceMotion') reduceMotion: boolean = false;
  courseId: number = -1;
  courseName: string = '';
  onClose: () => void = () => {};
  onSaved: () => void = () => {};
  @State name: string = '';
  @State className: string = '';
  @State semesterStart: string = '';
  @State slots: SlotDraft[] = [];
  @State loading: boolean = false;
  @State busy: boolean = false;
  @State error: string = '';
  @State loadFailed: boolean = false;

  aboutToAppear(): void {
    const today = new Date();
    today.setDate(today.getDate() - (today.getDay() + 6) % 7);
    this.semesterStart = this.iso(today);
    if (this.courseId > 0) { this.load(); }
    else { this.slots = [new SlotDraft()]; }
  }

  private iso(date: Date): string {
    return `${date.getFullYear()}-${`${date.getMonth() + 1}`.padStart(2, '0')}-${`${date.getDate()}`.padStart(2, '0')}`;
  }

  private chooseSemester(): void {
    const parts = this.semesterStart.split('-');
    DatePickerDialog.show({ selected: new Date(Number(parts[0]), Number(parts[1]) - 1, Number(parts[2])),
      onAccept: (value: DatePickerResult) => {
        const day = new Date(value.year ?? new Date().getFullYear(), value.month ?? 0, value.day ?? 1);
        day.setDate(day.getDate() - (day.getDay() + 6) % 7);
        this.semesterStart = this.iso(day);
      } });
  }

  private async load(): Promise<void> {
    this.loading = true;
    this.loadFailed = false;
    this.error = '';
    try {
      const data = JSON.parse(await Api.get(`/courses/${this.courseId}/schedule`)) as ScheduleBody;
      this.semesterStart = data.semester_start;
      this.slots = data.slots.map((slot: SlotBody) => SlotDraft.from(slot));
    } catch (e) { this.error = (e as Error).message; this.loadFailed = true; }
    finally { this.loading = false; }
  }

  private async save(): Promise<void> {
    if (this.busy || this.loading || this.loadFailed) { return; }
    this.error = '';
    if (this.courseId < 0 && (!this.name.trim() || !this.className.trim() || this.slots.length === 0)) {
      this.error = '请填写课程名、班级名，并安排至少一个上课时段'; return;
    }
    if (this.slots.some((slot: SlotDraft) => slot.start_section < 1 || slot.end_section > 12 ||
      slot.start_section > slot.end_section || slot.start_week < 1 || slot.end_week > 30 || slot.start_week > slot.end_week)) {
      this.error = '请检查节次（1–12）和周次（1–30），结束不能早于开始'; return;
    }
    if (this.courseId > 0 && this.slots.length === 0) {
      AlertDialog.show({ title: '清空课程上课时间？', message: '所有已加入学生的课表将同步移除这些时段，课程和资料仍保留。',
        primaryButton: { value: '取消', action: () => {} },
        secondaryButton: { value: '清空', action: () => { this.submit(); } } });
    } else { await this.submit(); }
  }

  private async submit(): Promise<void> {
    if (this.busy) { return; }
    this.busy = true;
    const schedule: ScheduleBody = { semester_start: this.semesterStart,
      slots: this.slots.map((slot: SlotDraft) => slot.body()) };
    try {
      if (this.courseId > 0) { await Api.put(`/courses/${this.courseId}/schedule`, schedule); }
      else {
        const body: CreateBody = { name: this.name.trim(), class_name: this.className.trim(),
          teacher_id: GlobalState.userId(), schedule: schedule };
        const course = JSON.parse(await Api.post('/courses', body)) as ClassCourse;
        AlertDialog.show({ title: '课程已创建', message: `邀请码：${course.invite_code}`,
          confirm: { value: '确定', action: () => {} } });
      }
      this.onSaved();
    } catch (e) { this.error = (e as Error).message; }
    finally { this.busy = false; }
  }

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column().width('100%').height('100%').backgroundColor('rgba(20,34,50,0.3)')
        .onClick(() => { if (!this.busy) { this.onClose(); } })
      Column({ space: 12 }) {
        Row({ space: 8 }) {
          Text(this.courseId > 0 ? `${this.courseName} · 上课时间` : '新建课程').fontSize(20).fontWeight(FontWeight.Bold)
            .layoutWeight(1).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
          Button({ type: ButtonType.Normal }) { SymbolGlyph($r('sys.symbol.xmark')).fontSize(20) }.stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          })
            .width(40).height(40).backgroundColor(Color.Transparent).enabled(!this.busy)
            .accessibilityText('关闭课程安排').onClick(this.onClose)
        }.width('100%')
        if (this.loading) { LoadingProgress().width(32).height(32) }
        else if (this.loadFailed) {
          Button('重新加载').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).onClick(() => { this.load(); })
        } else {
          Scroll() {
            Column({ space: 10 }) {
              if (this.courseId < 0) {
                TextInput({ text: this.name, placeholder: '课程名' }).height(44).maxLength(100)
                  .onChange((value: string) => { this.name = value; })
                TextInput({ text: this.className, placeholder: '班级名' }).height(44).maxLength(100)
                  .onChange((value: string) => { this.className = value; })
              }
              Text('学期第 1 周起始日（周一）').width('100%').fontSize(13).fontColor(AppTheme.TEXT_SECONDARY)
              Button(this.semesterStart).stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).width('100%').height(40).borderRadius(8)
                .backgroundColor('#E8EFFF').fontColor('#305FC3').onClick(() => { this.chooseSemester(); })
              ForEach(this.slots, (slot: SlotDraft, index: number) => {
                SlotEditor({ slot: slot, index: index,
                  onRemove: () => { this.slots = this.slots.filter((item: SlotDraft) => item.key !== slot.key); } })
              }, (slot: SlotDraft) => `${slot.key}`)
              Button('添加上课时段').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).width('100%').height(40).borderRadius(8).enabled(this.slots.length < 40)
                .fontColor('#305FC3').backgroundColor('#E8EFFF')
                .onClick(() => { this.slots = [...this.slots, new SlotDraft()]; })
            }.width('100%')
          }.width('100%').layoutWeight(1).scrollBar(BarState.Auto).enabled(!this.busy)
        }
        if (this.error) { Text(this.error).width('100%').fontSize(13).fontColor('#B54159').maxLines(4) }
        Button(this.busy ? '保存中…' : this.courseId > 0 ? '保存上课时间' : '创建课程').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          })
          .width('100%').height(44).borderRadius(8).backgroundColor('#305FC3')
          .enabled(!this.busy && !this.loading && !this.loadFailed).onClick(() => { this.save(); })
      }.width('92%').height('90%').constraintSize({ maxWidth: 520, maxHeight: 760 })
        .padding(20).backgroundColor('#FFFFFF').borderRadius(8)
    }.width('100%').height('100%')
  }
}
