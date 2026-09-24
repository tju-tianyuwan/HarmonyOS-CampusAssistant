import { StudyMaterial } from '../StudyMaterial';

@Component
export struct CrystalIcon {
  icon: Resource = $r('sys.symbol.book');
  edge: number = 48;
  tint: string = '#155AA5';
  @StorageLink('crystalSoftMaterial') soft: boolean = false;

  build() {
    Stack({ alignContent: Alignment.Center }) {
      Column().width(this.edge - 6).height(this.edge - 6).borderRadius(this.edge * 0.27)
        .backgroundColor('#92B8D5').translate({ y: 5 }).opacity(0.45)
      Column().width(this.edge).height(this.edge).borderRadius(this.edge * 0.27)
        .linearGradient({ angle: 135, colors: [['#FFFFFF', 0], ['#E5F3FD', 0.48], ['#B5D5EC', 1]] })
        .border({ width: 1, color: '#F8FCFF' }).shadow({ radius: 16, color: '#204275A0', offsetY: 8 })
      SymbolGlyph(this.icon).fontSize(this.edge * 0.43).fontColor([this.tint])
    }.width(this.edge + 8).height(this.edge + 10).visualEffect(StudyMaterial.light(this.soft))
      .accessibilityLevel('no').hitTestBehavior(HitTestMode.None)
  }
}
