import { promptAction } from '@kit.ArkUI';
import { Note } from '../../model/Models';
import { Api } from '../Api';
import { GlobalState } from '../GlobalState';
import { nfcService } from './NfcService';
import { transferService } from './TransferService';

/**
 * 协同能力总管（同账号多设备场景）：
 * - NFC 碰一碰：手机把学习快照写入标签 → 平板碰读即接续；
 * - 局域网互抓：新设备发现同账号旧设备，拉取学习进度/笔记完成切换；
 * - 依据 GlobalState 开关（默认全开）自动启停；模拟器无 NFC/广播受限时静默降级。
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
    // 局域网共享：自动共享我的笔记
    if (GlobalState.lanGrabEnabled && GlobalState.course !== null) {
      try {
        const all: Note[] = JSON.parse(await Api.get(
          `/notes?class_course_id=${GlobalState.courseId()}&user_id=${GlobalState.userId()}`)) as Note[];
        const mine: Note[] = all.filter((n: Note) => n.owner_id === GlobalState.userId());
        if (mine.length > 0) {
          const name: string = GlobalState.user === null ? '设备' : GlobalState.user.name;
          await transferService.startSharing(mine, name,
            GlobalState.isTeacher() ? 'teacher' : 'student');
        }
      } catch (e) {
        // 网络/端口异常忽略
      }
    }
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
    promptAction.showToast({ message: `${source}：已接续学习进度` });
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
