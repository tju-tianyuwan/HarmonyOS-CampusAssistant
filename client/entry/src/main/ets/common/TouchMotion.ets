import { curves } from '@kit.ArkUI';

/** Shared tokens used by native stateStyles. AttributeModifier cannot wrap animation. */
export class TouchMotion {
  static standard(): ICurve { return curves.cubicBezierCurve(0.4, 0, 0.2, 1); }
  static enter(): ICurve { return curves.cubicBezierCurve(0, 0, 0.2, 1); }
  static press(reduced: boolean): AnimateParam {
    return { duration: reduced ? 0 : 100, curve: TouchMotion.standard() };
  }
  static release(reduced: boolean): AnimateParam {
    return reduced ? { duration: 0 } : { curve: curves.springMotion(0.30, 0.86, 0.12) };
  }
  static pressedScale(reduced: boolean, kind: string): ScaleOptions {
    const scale = reduced || kind === 'card' ? 1 : kind === 'icon' ? 0.95 : kind === 'tab' ? 0.985 : 0.972;
    return { x: scale, y: scale };
  }
  static pressedOffset(reduced: boolean, kind: string): TranslateOptions {
    return { y: reduced || kind === 'tab' ? 0 : 1 };
  }
  static selection(reduced: boolean): AnimateParam {
    return { duration: reduced ? 0 : 120, curve: TouchMotion.standard() };
  }
}
