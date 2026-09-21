import { TouchMotion } from '../TouchMotion';

/** Keeps the existing child lifecycle. The key changes motion, never rekeys business state. */
@Component
export struct MotionPage {
  @Prop @Watch('navigate') navigationKey: string = '0|page';
  @Prop horizontal: boolean = true;
  @Prop tabNavigation: boolean = false;
  @StorageLink('reduceMotion') @Watch('reductionChanged') reduceMotion: boolean = false;
  @State opacityValue: number = 1;
  @State motionOffset: number = 0;
  @BuilderParam content: () => void = this.empty;
  private previousKey: string = '';
  private motionTimer: number = -1;
  private active: boolean = false;

  @Builder empty() {}

  aboutToAppear(): void { this.active = true; this.previousKey = this.navigationKey; }
  aboutToDisappear(): void { this.active = false; this.clearTimer(); }

  private clearTimer(): void {
    if (this.motionTimer >= 0) { clearTimeout(this.motionTimer); this.motionTimer = -1; }
  }

  private reductionChanged(): void {
    this.clearTimer();
    this.getUIContext().animateTo({ duration: 0 }, () => { this.opacityValue = 1; this.motionOffset = 0; });
  }

  private navigate(): void {
    if (!this.active || this.navigationKey === this.previousKey) { return; }
    const oldDepth = Number(this.previousKey.split('|')[0]);
    const newDepth = Number(this.navigationKey.split('|')[0]);
    const tabChange = this.tabNavigation && this.previousKey.split('|')[1] !== this.navigationKey.split('|')[1];
    this.previousKey = this.navigationKey;
    this.clearTimer();
    if (this.reduceMotion) { this.reductionChanged(); return; }
    const direction: number = newDepth < oldDepth ? -1 : 1;
    // New destination is already interactive; only its presentation settles.
    this.getUIContext().animateTo({ duration: 0 }, () => {
      this.motionOffset = tabChange ? 0 : direction * (newDepth === oldDepth ? 10 : 22);
      this.opacityValue = tabChange ? 0.65 : 0.72;
    });
    this.motionTimer = setTimeout(() => {
      this.motionTimer = -1;
      if (!this.active) { return; }
      this.getUIContext().animateTo({ duration: tabChange ? 120 : 240, curve: TouchMotion.enter() }, () => {
        this.opacityValue = 1; this.motionOffset = 0;
      });
    }, 16);
  }

  build() {
    Column() { this.content() }
      .width('100%').height('100%')
      .opacity(this.opacityValue)
      .translate({ x: this.horizontal ? this.motionOffset : 0, y: this.horizontal ? 0 : this.motionOffset })
  }
}
