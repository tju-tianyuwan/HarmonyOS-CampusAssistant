/**
 * 全局主题 —— Notein 活力风：活力绿主色 + 彩色几何封面 + 纯白底 + 手账感。
 */
export class AppTheme {
  // 主色（活力绿）：主按钮、选中态、强调
  static readonly PRIMARY: string = '#05CE91';
  static readonly PRIMARY_DEEP: string = '#00B37E';
  static readonly PRIMARY_LIGHT: string = '#E4FBF3';
  // 墨黑：大标题、次级强调
  static readonly INK: string = '#1A1A1A';

  // 灰阶
  static readonly BG_PAGE: string = '#F5F6F8';
  static readonly BG_SUNKEN: string = '#F5F6F8';
  static readonly BG_CARD: string = '#FFFFFF';
  static readonly BG_WHITE: string = '#FFFFFF';
  static readonly TEXT_PRIMARY: string = '#1A1A1A';
  static readonly TEXT_SECONDARY: string = '#5B5B5B';
  static readonly TEXT_TERTIARY: string = '#9A9AA0';
  static readonly DIVIDER: string = '#EDEEF1';

  // 语义色
  static readonly SUCCESS: string = '#05CE91';
  static readonly WARNING: string = '#FF9F43';
  static readonly DANGER: string = '#FF5A5A';

  // 封面调色板（彩色几何封面，按 id 取模）
  static readonly COVERS: string[] = ['#05CE91', '#4C8DFF', '#FF9F43', '#FF6B6B', '#9B8CFF', '#00C2C7'];

  // 圆角
  static readonly RADIUS_CARD: number = 16;
  static readonly RADIUS_BTN: number = 22;
  static readonly RADIUS_TAG: number = 8;

  // 间距
  static readonly SPACE_XS: number = 4;
  static readonly SPACE_S: number = 8;
  static readonly SPACE_M: number = 12;
  static readonly SPACE_L: number = 16;
  static readonly SPACE_XL: number = 24;
  static readonly SPACE_XXL: number = 32;

  // 字号
  static readonly FONT_TITLE: number = 22;
  static readonly FONT_SUBTITLE: number = 16;
  static readonly FONT_BODY: number = 14;
  static readonly FONT_CAPTION: number = 12;

  // 布局
  static readonly LEFT_PANE_WIDTH: number = 280;
  static readonly TOPBAR_HEIGHT: number = 60;

  /** 语义色的 10% 透明浅底（#1ARRGGBB），用于胶囊标签 */
  static tagBg(color: string): string {
    return '#1A' + color.substring(1);
  }

  static cover(id: number): string {
    return AppTheme.COVERS[id % AppTheme.COVERS.length];
  }
}
