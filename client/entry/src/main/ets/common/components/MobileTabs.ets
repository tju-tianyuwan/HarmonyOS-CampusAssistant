import { TouchMotion } from '../TouchMotion';
import { LearningTheme as AppTheme } from '../LearningTheme';

@Component
export struct MobileTabs {
  @StorageLink('reduceMotion') reduceMotion: boolean = false;
  labels: string[] = [];
  keys: string[] = [];
  @Prop selected: string = '';
  @Prop interactive: boolean = true;
  @Prop solid: boolean = false;
  @Prop disabledKeys: string[] = [];
  @State tabWidth: number = 0;
  onSelect: (key: string) => void = () => {};

  build() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column().width(this.keys.length > 0 ? this.tabWidth / this.keys.length : 0).height(40)
        .borderRadius(this.solid ? 16 : 10)
        .backgroundColor(this.solid ? AppTheme.PRIMARY : '#FFFFFF')
        .translate({ x: Math.max(0, this.keys.indexOf(this.selected)) * this.tabWidth / Math.max(1, this.keys.length) })
        .animation({ duration: this.reduceMotion ? 0 : 220, curve: TouchMotion.standard() })
        .hitTestBehavior(HitTestMode.None)
      Row() {
      ForEach(this.labels, (label: string, index: number) => {
        Button(label, { type: ButtonType.Normal }).stateStyles({
            normal: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation(TouchMotion.release(this.reduceMotion)) },
            pressed: { .scale(TouchMotion.pressedScale(this.reduceMotion, 'tab'))
              .translate(TouchMotion.pressedOffset(this.reduceMotion, 'tab')).animation(TouchMotion.press(this.reduceMotion)) },
            disabled: { .scale({ x: 1, y: 1 }).translate({ y: 0 }).animation({ duration: 0 }) }
          }).height(40).layoutWeight(1).borderRadius(10)
          .padding({ left: 2, right: 2 })
          .fontSize(13).fontWeight(this.selected === this.keys[index] ? FontWeight.Bold : FontWeight.Medium)
          .backgroundColor(Color.Transparent)
          .fontColor(this.selected === this.keys[index] ? (this.solid ? '#FFFFFF' : AppTheme.PRIMARY_DEEP) : AppTheme.TEXT_SECONDARY)
          .enabled(this.interactive && !this.disabledKeys.includes(this.keys[index]))
          .onClick(() => { this.onSelect(this.keys[index]); })
      })
      }.width('100%')
    }.width('100%').height(48).padding(4).borderRadius(this.solid ? 20 : 14).backgroundColor(AppTheme.BG_SUNKEN)
      .onAreaChange((oldArea: Area, area: Area) => { this.tabWidth = Math.max(0, Number(area.width) - 8); })
  }
}
