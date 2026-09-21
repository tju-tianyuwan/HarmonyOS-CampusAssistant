import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';
import { hilog } from '@kit.PerformanceAnalysisKit';

/** App-local UI preference, independent of the account and of system settings. */
export class MotionPreferences {
  private static store: preferences.Preferences | null = null;
  private static queue: Promise<void> = Promise.resolve();

  static initialize(context: common.UIAbilityContext): void {
    try {
      MotionPreferences.store = preferences.getPreferencesSync(context, { name: 'study-ui-motion' });
      AppStorage.setOrCreate<boolean>('reduceMotion', MotionPreferences.store.getSync('reduceMotion', false) === true);
    } catch (error) {
      AppStorage.setOrCreate<boolean>('reduceMotion', false);
      hilog.warn(0x0000, 'MotionPreferences', 'UI preference storage is unavailable');
    }
  }

  static save(value: boolean): Promise<void> {
    const task = MotionPreferences.queue.catch(() => {}).then(async () => {
      const store = MotionPreferences.store;
      if (store === null) { throw new Error('UI preference storage is unavailable'); }
      store.putSync('reduceMotion', value);
      await store.flush();
    });
    MotionPreferences.queue = task;
    return task;
  }
}
