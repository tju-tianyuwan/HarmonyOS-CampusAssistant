import { StudyMaterial } from '../StudyMaterial';
import { TouchMotion } from '../TouchMotion';

/** Course-wide teacher action; hosted outside page transitions so it stays anchored. */
@Component
export struct FloatingRecordButton {
  @StorageLink('reduceMotion') reduceMotion: boolean = false;
  @StorageLink('crystalSoftMaterial') softMaterial: boolean = false;
  onRecord: () => void = () => {};

  build() {
    Stack() {
    Button({ type: ButtonType.Capsule }) {
      Row({ space: 8 }) {
        SymbolGlyph($r('sys.symbol.mic')).fontSize(23).fontColor(['#FFFFFF'])
        Text('录音').fontSize(16).fontWeight(FontWeight.Medium).fontColor('#FFFFFF')
      }.justifyContent(FlexAlign.Center).width('100%')
    }.id('teacher-floating-record').width(104).height(56).padding(0).borderRadius(22)
      .backgroundColor('#155AA5')
      .linearGradient({ angle: 150, colors: [['#4E91C3', 0], ['#2362A0', 0.48], ['#153F76', 1]] })
      .border({ width: 1.2, color: '#CCE9FA' })
      .shadow({ radius: 18, color: '#405780A9', offsetY: 6 })
      .visualEffect(StudyMaterial.light(this.softMaterial, true))
      .clip(true)
      .stateStyles({
        normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
        pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
          .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
        disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
      })
      .accessibilityText('一键开始当前课程录音').onClick(this.onRecord)
    }.width(104).height(56)
  }
}
