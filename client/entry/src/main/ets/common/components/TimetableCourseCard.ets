import { TimetableStyle } from '../TimetableStyle';
import { TouchMotion } from '../TouchMotion';

/** A small raised course tile, not a cell background. No blur layer per empty period. */
@Component
export struct TimetableCourseCard {
  @Prop courseId: number = 0;
  @Prop courseTitle: string = '';
  @Prop locationText: string = '';
  @Prop startSection: number = 1;
  @Prop endSection: number = 2;
  @Prop conflictCount: number = 0;
  @Prop description: string = '';
  blockId: string = '';
  onOpen: () => void = () => {};
  @StorageLink('reduceMotion') reduceMotion: boolean = false;
  @StorageLink('crystalSoftMaterial') softMaterial: boolean = false;

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column().width('100%').height(TimetableStyle.blockHeight(this.startSection, this.endSection) - 3)
        .borderRadius(11).backgroundColor(TimetableStyle.tone(this.courseId, this.conflictCount > 1).edge)
        .translate({ y: this.softMaterial ? 1 : 3 })
        .shadow({ radius: this.softMaterial ? 3 : 6, color: '#253E6083', offsetY: 3 })
      Column({ space: 4 }) {
        Text(this.conflictCount > 1 ? `${this.conflictCount}门课重叠` : this.courseTitle)
          .fontSize(12).lineHeight(15).fontWeight(FontWeight.Medium).width('100%')
          .fontColor(TimetableStyle.tone(this.courseId, this.conflictCount > 1).ink)
          .maxLines(this.endSection > this.startSection ? 3 : 2).textOverflow({ overflow: TextOverflow.Ellipsis })
        if (this.endSection > this.startSection) {
          Text(this.conflictCount > 1 ? '查看冲突' : this.locationText || '教室待定')
            .fontSize(10).lineHeight(13).maxLines(2).textOverflow({ overflow: TextOverflow.Ellipsis })
            .fontColor(TimetableStyle.tone(this.courseId, this.conflictCount > 1).ink).opacity(0.86).width('100%')
          Blank().layoutWeight(1)
          Text(`${this.startSection}–${this.endSection}节`).fontSize(9).lineHeight(12)
            .fontColor(TimetableStyle.tone(this.courseId, this.conflictCount > 1).ink).width('100%')
        }
      }.width('100%').height(TimetableStyle.blockHeight(this.startSection, this.endSection) - 3)
        .padding({ left: 5, right: 5, top: 8, bottom: 7 }).alignItems(HorizontalAlign.Start).borderRadius(11)
        .linearGradient({ angle: 145, colors: [
          [TimetableStyle.tone(this.courseId, this.conflictCount > 1).top, 0],
          [TimetableStyle.tone(this.courseId, this.conflictCount > 1).bottom, 1]
        ] })
        .border({ width: { top: 1, left: 0.6, right: 0.6, bottom: 0.6 }, color: '#A6FFFFFF' }).clip(true)
    }.width('100%').height(TimetableStyle.blockHeight(this.startSection, this.endSection))
      .id(`timetable-block-${this.blockId}`).focusable(true).accessibilityText(this.description)
      .stateStyles({
        normal: { .translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
        pressed: { .translate(TouchMotion.pressedOffset(this.reduceMotion, 'card')).animation(TouchMotion.press(this.reduceMotion)) }
      }).onClick(this.onOpen)
  }
}
