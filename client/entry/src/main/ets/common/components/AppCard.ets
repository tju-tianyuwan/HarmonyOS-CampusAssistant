import { AppTheme } from '../AppTheme';

/**
 * 通用卡片 —— Notein 风：纯白、14vp 圆角、可选轻投影；
 * 选中态为青色描边 + 浅青底。样式参数化，预留动画挂载。
 */
@Component
export struct AppCard {
  cardRadius: number = AppTheme.RADIUS_CARD;
  cardPadding: number = AppTheme.SPACE_L;
  cardBgColor: string = AppTheme.BG_CARD;
  @Prop selected: boolean = false;
  clickable: boolean = false;
  fillHeight: boolean = false;
  hasShadow: boolean = false;
  onCardClick: () => void = () => {
  };
  @BuilderParam content: () => void = this.empty;

  @Builder
  empty() {
  }

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .height(this.fillHeight ? '100%' : 'auto')
    .padding(this.cardPadding)
    .borderRadius(this.cardRadius)
    .backgroundColor(this.selected ? AppTheme.PRIMARY_LIGHT : this.cardBgColor)
    .border({
      width: 1.5,
      color: this.selected ? AppTheme.PRIMARY : 'transparent'
    })
    .shadow(this.hasShadow ? {
      radius: 16,
      color: 'rgba(17,17,17,0.05)',
      offsetX: 0,
      offsetY: 4
    } : {
      radius: 0,
      color: 'transparent',
      offsetX: 0,
      offsetY: 0
    })
    .alignItems(HorizontalAlign.Start)
    .onClick(() => {
      if (this.clickable) {
        this.onCardClick();
      }
    })
  }
}
