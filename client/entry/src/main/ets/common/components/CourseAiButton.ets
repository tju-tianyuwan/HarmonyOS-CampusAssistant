import { TouchMotion } from '../TouchMotion';
import { StudyMaterial } from '../StudyMaterial';

/** Shared course AI entry beside the navigation, matching the course-home dock. */
@Component
export struct CourseAiButton {
  @StorageLink('reduceMotion') reduceMotion: boolean = false;
  @StorageLink('crystalSoftMaterial') subtle: boolean = false;
  @Prop selected: boolean = false;
  @Prop interactive: boolean = true;
  onOpen: () => void = () => {};

  build() {
    Button('AI').stateStyles({
      normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
      pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'button'))
        .translate(TouchMotion.pressedOffset(this.reduceMotion, 'button')).animation(TouchMotion.press(this.reduceMotion)) },
      disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
    }).fontSize(19).fontWeight(FontWeight.Bold).fontColor('#FFFFFF').width(56).height(56).borderRadius(22)
      .backgroundColor('#124B87')
      .linearGradient({ angle: 150, colors: [['#5B9CC9', 0], ['#2362A0', 0.55], ['#1A437C', 1]] })
      .border({ width: this.selected ? 2 : 1.2, color: '#CCE9FA' })
      .shadow({ radius: 14, color: '#405780A9', offsetY: 6 })
      .visualEffect(StudyMaterial.light(this.subtle, true))
      .accessibilityText(this.selected ? '课程 AI 助手，当前页面' : '打开课程 AI 助手')
      .enabled(this.interactive).onClick(() => { this.onOpen(); })
  }
}
