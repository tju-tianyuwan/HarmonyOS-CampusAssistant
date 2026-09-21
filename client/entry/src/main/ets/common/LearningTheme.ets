import { AppTheme } from './AppTheme';
import { GlobalState } from '../service/GlobalState';

/** Student study surfaces: ice-blue crystal, readable ink, native material.
 * Teacher and signed-out screens retain their existing theme.
 * Native system type and interaction feedback; no decorative animation.
 */
export class LearningTheme {
  private static student(): boolean { return GlobalState.user !== null && !GlobalState.isTeacher(); }
  static get PRIMARY(): string { return this.student() ? '#155AA5' : AppTheme.PRIMARY; }
  static get PRIMARY_DEEP(): string { return this.student() ? '#124B87' : AppTheme.PRIMARY_DEEP; }
  static get PRIMARY_LIGHT(): string { return this.student() ? '#E0EDF9' : AppTheme.PRIMARY_LIGHT; }
  static get INK(): string { return this.student() ? '#173A56' : AppTheme.INK; }
  static get BG_PAGE(): string { return this.student() ? '#00ECF4FC' : AppTheme.BG_PAGE; }
  static get BG_SUNKEN(): string { return this.student() ? '#E7EFF7' : AppTheme.BG_SUNKEN; }
  static get BG_CARD(): string { return this.student() ? '#DEFFFFFF' : AppTheme.BG_CARD; }
  static readonly BG_WHITE: string = AppTheme.BG_WHITE;
  static get TEXT_PRIMARY(): string { return this.student() ? '#173A56' : AppTheme.TEXT_PRIMARY; }
  static get TEXT_SECONDARY(): string { return this.student() ? '#526D83' : AppTheme.TEXT_SECONDARY; }
  static get TEXT_TERTIARY(): string { return this.student() ? '#60788C' : AppTheme.TEXT_TERTIARY; }
  static get DIVIDER(): string { return this.student() ? '#D7E5F2' : AppTheme.DIVIDER; }
  static get SUCCESS(): string { return this.student() ? '#176B55' : AppTheme.SUCCESS; }
  static get WARNING(): string { return this.student() ? '#95601A' : AppTheme.WARNING; }
  static get DANGER(): string { return this.student() ? '#BA4141' : AppTheme.DANGER; }
  static get RADIUS_CARD(): number { return this.student() ? 24 : AppTheme.RADIUS_CARD; }
  static get RADIUS_BTN(): number { return this.student() ? 16 : AppTheme.RADIUS_BTN; }
  static readonly RADIUS_TAG: number = AppTheme.RADIUS_TAG;
  static readonly SPACE_XS: number = AppTheme.SPACE_XS;
  static readonly SPACE_S: number = AppTheme.SPACE_S;
  static readonly SPACE_M: number = AppTheme.SPACE_M;
  static readonly SPACE_L: number = AppTheme.SPACE_L;
  static readonly SPACE_XL: number = AppTheme.SPACE_XL;
  static readonly SPACE_XXL: number = AppTheme.SPACE_XXL;
  static readonly FONT_TITLE: number = AppTheme.FONT_TITLE;
  static readonly FONT_SUBTITLE: number = AppTheme.FONT_SUBTITLE;
  static readonly FONT_BODY: number = AppTheme.FONT_BODY;
  static readonly FONT_CAPTION: number = AppTheme.FONT_CAPTION;
  static readonly LEFT_PANE_WIDTH: number = AppTheme.LEFT_PANE_WIDTH;
  static readonly TOPBAR_HEIGHT: number = AppTheme.TOPBAR_HEIGHT;
  static readonly COVERS: string[] = AppTheme.COVERS;
  static tagBg(color: string): string { return AppTheme.tagBg(color); }
  static cover(id: number): string { return AppTheme.cover(id); }
}
