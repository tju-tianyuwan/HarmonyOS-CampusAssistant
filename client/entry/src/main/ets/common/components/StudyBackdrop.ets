/** Original user-supplied transparent artwork, softened by native ArkUI rendering.
 * Decorative only: never receives touch or accessibility focus.
 */
@Component
export struct StudyBackdrop {
  @StorageLink('crystalSoftMaterial') soft: boolean = false;
  @State viewWidth: number = 400;
  @State viewHeight: number = 800;

  build() {
    Stack() {
      Column().width('100%').height('100%')
        .linearGradient({ angle: 140, colors: [['#ECF4FC', 0], ['#DCEAF7', 0.48], ['#EAF3F7', 1]] })
      Image($r('app.media.transparent_clean')).objectFit(ImageFit.Contain)
        .width(this.viewWidth < 840 ? this.viewWidth * 1.3 : Math.min(this.viewWidth * 0.72, 1080))
        .height(this.viewWidth < 840 ? this.viewWidth * 1.3 : Math.min(this.viewWidth * 0.72, 1080))
        .opacity(this.soft ? 0.18 : 0.38).blur(this.soft ? 12 : 7)
        .position({ x: this.viewWidth < 840 ? -this.viewWidth * 0.12 : this.viewWidth * 0.3,
          y: this.viewHeight * 0.12 })
      Column().width('100%').height('100%').backgroundColor('#12F4F8FC')
    }.width('100%').height('100%').clip(true).hitTestBehavior(HitTestMode.None).accessibilityLevel('no')
      .onAreaChange((oldArea: Area, area: Area) => {
        this.viewWidth = Number(area.width); this.viewHeight = Number(area.height);
      })
  }
}
