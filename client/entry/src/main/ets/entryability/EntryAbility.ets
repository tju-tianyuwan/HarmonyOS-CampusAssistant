import { AbilityConstant, UIAbility, Want } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { window } from '@kit.ArkUI';
import { GlobalState } from '../service/GlobalState';

const DOMAIN: number = 0x0000;
const TAG: string = 'EntryAbility';

/**
 * 跨端迁移（流转）说明：
 * - module.json5 中本 Ability 已声明 "continuable": true；
 * - 源端：系统发起迁移时回调 onContinue()，把学习状态（用户/课程/页签/课时）写入 wantParam；
 * - 目标端：冷启动走 onCreate、热启动走 onNewWant，launchReason 为 CONTINUATION 时
 *   从 want.parameters 取回状态写入 AppStorage，Index 页监听 continueRestoreTick 完成恢复。
 * - 需要同华为账号 + 同局域网 + ohos.permission.DISTRIBUTED_DATASYNC（协同页运行时申请）。
 */
export default class EntryAbility extends UIAbility {
  onCreate(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'Ability onCreate');
    this.restoreFromContinuation(want, launchParam);
  }

  onNewWant(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    hilog.info(DOMAIN, TAG, 'Ability onNewWant');
    this.restoreFromContinuation(want, launchParam);
  }

  /** 源端：打包当前学习状态（设置中关闭跨端接续时拒绝迁移） */
  onContinue(wantParam: Record<string, Object>): AbilityConstant.OnContinueResult {
    if (!GlobalState.continuationEnabled) {
      return AbilityConstant.OnContinueResult.REJECT;
    }
    const snapshot: string | undefined = AppStorage.get<string>('continueSnapshot');
    wantParam['smartstudy_state'] = snapshot ?? '';
    hilog.info(DOMAIN, TAG, 'onContinue snapshot=%{public}s', snapshot ?? 'empty');
    return AbilityConstant.OnContinueResult.AGREE;
  }

  /** 目标端：还原学习状态 */
  private restoreFromContinuation(want: Want, launchParam: AbilityConstant.LaunchParam): void {
    if (launchParam.launchReason !== AbilityConstant.LaunchReason.CONTINUATION) {
      return;
    }
    const params: Record<string, Object> | undefined =
      want.parameters as Record<string, Object> | undefined;
    if (params === undefined) {
      return;
    }
    const state: Object | undefined = params['smartstudy_state'];
    if (typeof state === 'string' && state !== '') {
      AppStorage.setOrCreate<string>('continueRestoreState', state);
      const tick: number = AppStorage.get<number>('continueRestoreTick') ?? 0;
      AppStorage.setOrCreate<number>('continueRestoreTick', tick + 1);
      hilog.info(DOMAIN, TAG, 'continuation state restored to AppStorage');
    }
  }

  onDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Ability onDestroy');
  }

  onWindowStageCreate(windowStage: window.WindowStage): void {
    hilog.info(DOMAIN, TAG, 'Ability onWindowStageCreate');
    windowStage.loadContent('pages/Index', (err) => {
      if (err.code) {
        hilog.error(DOMAIN, TAG, 'Failed to load content. Cause: %{public}s', JSON.stringify(err));
        return;
      }
      hilog.info(DOMAIN, TAG, 'Succeeded in loading content.');
    });
  }

  onWindowStageDestroy(): void {
    hilog.info(DOMAIN, TAG, 'Ability onWindowStageDestroy');
  }

  onForeground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onForeground');
  }

  onBackground(): void {
    hilog.info(DOMAIN, TAG, 'Ability onBackground');
  }
}
