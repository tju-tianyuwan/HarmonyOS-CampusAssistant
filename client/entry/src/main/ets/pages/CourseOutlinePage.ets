import { TouchMotion } from '../common/TouchMotion';
import { LearningTheme as AppTheme } from '../common/LearningTheme';
import { Outline } from '../model/Models';
import { Api } from '../service/Api';
import { GlobalState } from '../service/GlobalState';

interface CourseOutline extends Outline {
  session_title: string;
  session_created_at: string;
}

@Component
export struct CourseOutlinePage {
  @StorageLink('reduceMotion') reduceMotion: boolean = false;
  @State outlines: CourseOutline[] = [];
  @State selectedOutline: CourseOutline | null = null;
  @State loading: boolean = false;
  @State error: string = '';
  private active: boolean = true;

  aboutToAppear(): void {
    this.active = true;
    this.selectedOutline = null;
    GlobalState.closeOutlineDetail = null;
    this.load();
  }

  aboutToDisappear(): void {
    this.active = false;
    GlobalState.closeOutlineDetail = null;
  }

  private async load(): Promise<void> {
    if (this.loading || !GlobalState.isTeacher() || !GlobalState.canManageCurrentCourse()) { return; }
    this.loading = true;
    this.error = '';
    try {
      const rows = JSON.parse(await Api.get(
        `/sessions/outlines?class_course_id=${GlobalState.courseId()}`)) as CourseOutline[];
      if (this.active) { this.outlines = rows; }
    } catch (e) {
      if (this.active) { this.error = (e as Error).message; }
    } finally {
      this.loading = false;
    }
  }

  private openOutline(outline: CourseOutline): void {
    this.selectedOutline = outline;
    GlobalState.closeOutlineDetail = (): void => { this.closeOutline(); };
  }

  private closeOutline(): void {
    this.selectedOutline = null;
    GlobalState.closeOutlineDetail = null;
  }

  private statusLabel(status: string): string {
    if (status === 'generated') { return 'AI 已生成'; }
    if (status === 'draft') { return '教师草稿'; }
    if (status === 'pending') { return '待审核'; }
    if (status === 'published') { return '已发布'; }
    return '已退回';
  }

  private statusColor(status: string): string {
    if (status === 'published') { return AppTheme.SUCCESS; }
    if (status === 'rejected') { return AppTheme.DANGER; }
    if (status === 'pending') { return AppTheme.WARNING; }
    return AppTheme.PRIMARY_DEEP;
  }

  private formatTime(value: string): string {
    return value.length >= 16 ? value.substring(0, 16).replace('T', ' ') : value.replace('T', ' ');
  }

  @Builder
  outlineDetail() {
    Column({ space: 12 }) {
      Row({ space: 12 }) {
        Button('返回提纲列表').stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          })
          .fontColor(AppTheme.PRIMARY_DEEP)
          .backgroundColor(AppTheme.PRIMARY_LIGHT)
          .onClick(() => { this.closeOutline(); })
        Blank()
        Text(this.selectedOutline === null ? '' : this.statusLabel(this.selectedOutline.status))
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.selectedOutline === null ? AppTheme.TEXT_SECONDARY :
            this.statusColor(this.selectedOutline.status))
      }.width('100%')
      Text(this.selectedOutline === null ? '' : this.selectedOutline.session_title)
        .fontSize(22).fontWeight(FontWeight.Bold).fontColor(AppTheme.INK).width('100%')
      Text(this.selectedOutline === null ? '' :
        `更新于 ${this.formatTime(this.selectedOutline.updated_at)}`)
        .fontSize(12).fontColor(AppTheme.TEXT_TERTIARY).width('100%')
      Scroll() {
        Text(this.selectedOutline === null ? '' : this.selectedOutline.markdown)
          .fontSize(15)
          .fontColor(AppTheme.TEXT_PRIMARY)
          .lineHeight(24)
          .width('100%')
          .copyOption(CopyOptions.InApp)
      }
      .layoutWeight(1)
      .width('100%')
      .padding(16)
      .backgroundColor('#FFFFFF')
      .borderRadius(8)
    }.padding(24).width('100%').height('100%').backgroundColor(AppTheme.BG_PAGE)
  }

  build() {
    if (this.selectedOutline !== null) {
      this.outlineDetail()
    } else {
      Column({ space: 12 }) {
        Text('课程提纲').fontSize(22).fontWeight(FontWeight.Bold).width('100%')
        if (this.loading) {
          LoadingProgress().width(28).height(28)
        }
        if (this.error !== '') {
          Text(this.error).fontSize(13).fontColor(AppTheme.DANGER).width('100%')
        }
        if (!this.loading && this.error === '' && this.outlines.length === 0) {
          Text('暂无课程提纲').fontSize(15).fontColor(AppTheme.TEXT_TERTIARY).width('100%')
        }
        Scroll() {
          Column({ space: 10 }) {
            ForEach(this.outlines, (outline: CourseOutline) => {
              Row({ space: 12 }) {
                Column({ space: 5 }) {
                  Text(outline.session_title)
                    .fontSize(16).fontWeight(FontWeight.Medium).fontColor(AppTheme.TEXT_PRIMARY).width('100%')
                  Text(`${this.formatTime(outline.updated_at)} · ${outline.markdown.length} 字`)
                    .fontSize(12).fontColor(AppTheme.TEXT_TERTIARY).width('100%')
                }.layoutWeight(1)
                Column({ space: 5 }) {
                  Text(this.statusLabel(outline.status))
                    .fontSize(12).fontWeight(FontWeight.Bold).fontColor(this.statusColor(outline.status))
                  Text('查看').fontSize(13).fontColor(AppTheme.PRIMARY_DEEP)
                }.alignItems(HorizontalAlign.End)
              }
              .width('100%')
              .padding(14)
              .backgroundColor('#FFFFFF')
              .borderRadius(8)
              .onClick(() => { this.openOutline(outline); })
            }, (outline: CourseOutline) => `${outline.id}_${outline.updated_at}`)
          }.width('100%')
        }.layoutWeight(1).width('100%')
      }.padding(24).width('100%').height('100%').backgroundColor(AppTheme.BG_PAGE)
    }
  }
}
