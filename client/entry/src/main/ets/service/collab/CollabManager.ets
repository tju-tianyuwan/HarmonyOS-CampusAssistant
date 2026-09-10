import { promptAction } from '@kit.ArkUI';
import { Api } from '../Api';
import { GlobalState } from '../GlobalState';
import { nfcService } from './NfcService';
import { transferService } from './TransferService';

/**
 * 协同能力总管（同账号多设备场景）：
 * - NFC 碰一碰：手机把学习快照写入标签 → 平板碰读即接续；
 * - 系统隔空传送：握拳抓取当前笔记或学习状态，在目标设备张手释放；
 * - 依据 GlobalState 开关（默认全开）注册系统回调。
 */
export class CollabManager {
  static async start(): Promise<void> {
    // NFC 碰卡：快照 → 接续；6 位邀请码 → 入班（兼容）
    nfcService.onHandoff = (snapshotJson: string): void => {
      CollabManager.applyHandoff(snapshotJson, 'NFC 碰一碰');
    };
    nfcService.onCode = (code: string): void => {
      CollabManager.joinByCode(code);
    };
    // 碰一碰接续对所有用户开放（同账号手机→平板）
    if (GlobalState.nfcEnabled) {
      try {
        nfcService.startReading();
      } catch (e) {
        // 无 NFC 环境忽略
      }
    }
    if (GlobalState.lanGrabEnabled) { transferService.startSharing(); }
  }

  static stop(): void {
    try {
      nfcService.stop();
    } catch (e) {
      // 忽略
    }
    try {
      transferService.stopSharing();
    } catch (e) {
      // 忽略
    }
  }

  /** NFC 开关联动 */
  static applyNfc(on: boolean): void {
    if (!on) {
      nfcService.stop();
      return;
    }
    nfcService.startReading();
  }

  /** 局域网共享开关联动 */
  static async applyLan(on: boolean): Promise<void> {
    if (!on) {
      transferService.stopSharing();
      return;
    }
    if (GlobalState.course !== null) {
      await CollabManager.start();
    }
  }

  /** 应用学习快照（NFC 碰读 / 局域网拉取共用）：走 Index 的迁移恢复通道 */
  static applyHandoff(snapshotJson: string, source: string): void {
    if (snapshotJson.trim() === '') {
      promptAction.showToast({ message: `${source}：对方暂无学习状态` });
      return;
    }
    AppStorage.setOrCreate<string>('continueRestoreState', snapshotJson);
    const tick: number = AppStorage.get<number>('continueRestoreTick') ?? 0;
    AppStorage.setOrCreate<number>('continueRestoreTick', tick + 1);
  }

  private static async joinByCode(code: string): Promise<void> {
    interface JoinBody {
      user_id: number;
      invite_code: string;
    }

    const body: JoinBody = { user_id: GlobalState.userId(), invite_code: code };
    try {
      await Api.post('/courses/join', body);
      promptAction.showToast({ message: `碰一碰成功，已加入课程（邀请码 ${code}）` });
    } catch (e) {
      promptAction.showToast({ message: `碰一碰加入失败：${(e as Error).message}` });
    }
  }
}
