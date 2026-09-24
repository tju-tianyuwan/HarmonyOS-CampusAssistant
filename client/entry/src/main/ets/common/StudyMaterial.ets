import { deviceInfo } from '@kit.BasicServicesKit';
import { uiEffect } from '@kit.ArkGraphics2D';
import { hdsEffect } from '@kit.UIDesignKit';

/** Same native light treatment for learning and teaching; unsupported devices use the base surface. */
export class StudyMaterial {
  static light(soft: boolean, source: boolean = false): VisualEffect {
    if (deviceInfo.sdkApiVersion >= 20 && canIUse('SystemCapability.UIDesign.HDSComponent.Core') && !soft) {
      return new hdsEffect.HdsEffectBuilder()
        .pressShadow(hdsEffect.PressShadowType.BLEND_WHITE)
        .pointLight({ sourceType: source ? hdsEffect.PointLightSourceType.SOFT : hdsEffect.PointLightSourceType.NONE,
          illuminatedType: hdsEffect.PointLightIlluminatedType.BORDER,
          options: { color: '#A8EBFF', intensity: 0.35, height: 24, bloom: 0.1 } }).buildEffect();
    }
    return uiEffect.createEffect();
  }
}
