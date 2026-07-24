import { tag } from '@kit.ConnectivityKit';
import { util } from '@kit.ArkTS';

/**
 * NFC 碰一碰 —— 同一账号从手机到平板的学习接续（NDEF 标签中介）：
 * - 手机端「写入」：把当前学习状态快照（SSHANDOFF|<JSON>）写入 NFC 标签；
 * - 平板端「碰一碰」：贴近标签读取快照，立即恢复到相同课程/页面/课时。
 * 兼容：标签内容若为 6 位数字邀请码，则按加入课程处理。
 *
 * 技术要点：
 * - 前台分发 tag.registerForegroundDispatch：应用在前台时优先接管贴卡事件；
 * - 权限 ohos.permission.NFC_TAG（normal 级，module.json5 声明即可）；
 * - 快照约 300~600 字节，建议 NTAG215/216 等容量 ≥496B 的标签；
 * - 模拟器无 NFC 芯片，需真机验证；三方应用无设备间 NFC P2P 通道，
 *   故采用「标签中介」承载快照，设备直连切换由局域网互抓承担。
 */

const BUNDLE_NAME: string = 'com.demo.smartstudy';
const MODULE_NAME: string = 'entry';
const ABILITY_NAME: string = 'EntryAbility';
const HANDOFF_PREFIX: string = 'SSHANDOFF|';

export type NfcMode = 'idle' | 'read' | 'write';

export class NfcService {
  private mode: NfcMode = 'idle';
  private pendingWritePayload: string = '';
  private registered: boolean = false;
  /** 读到 6 位邀请码（兼容入班） */
  onCode: (code: string) => void = (code: string) => {
  };
  /** 读到学习快照 → 跨设备接续 */
  onHandoff: (snapshotJson: string) => void = (snapshotJson: string) => {
  };
  onLog: (msg: string) => void = (msg: string) => {
  };

  getMode(): NfcMode {
    return this.mode;
  }

  /** 开启碰一碰接续待命（贴近标签即读取） */
  startReading(): void {
    this.mode = 'read';
    this.register();
  }

  /** 把当前学习状态快照写入标签（手机端） */
  startWriting(snapshotJson: string): void {
    this.mode = 'write';
    this.pendingWritePayload = HANDOFF_PREFIX + snapshotJson;
    this.register();
  }

  stop(): void {
    this.mode = 'idle';
    if (!this.registered) {
      return;
    }
    try {
      // ElementName 直接内联字面量（其类型定义在 bundleManager，不经 tag 命名空间引用）
      tag.unregisterForegroundDispatch({
        bundleName: BUNDLE_NAME,
        moduleName: MODULE_NAME,
        abilityName: ABILITY_NAME
      });
    } catch (e) {
      // 忽略注销异常
    }
    this.registered = false;
    this.onLog('NFC 待命已关闭');
  }

  private register(): void {
    if (this.registered) {
      this.onLog(this.mode === 'read' ? '碰一碰待命中：贴近学习标签即接续…' : '请贴近 NFC 标签写入学习状态…');
      return;
    }
    try {
      const techs: number[] = [tag.NFC_A, tag.NFC_B, tag.NFC_F, tag.NFC_V];
      tag.registerForegroundDispatch({
        bundleName: BUNDLE_NAME,
        moduleName: MODULE_NAME,
        abilityName: ABILITY_NAME
      }, techs, (err: Error, tagInfo: tag.TagInfo) => {
        if (err) {
          this.onLog(`NFC 事件异常：${err.message}`);
          return;
        }
        this.handleTag(tagInfo);
      });
      this.registered = true;
      this.onLog(this.mode === 'read' ? 'NFC 就绪：碰一碰即接续（手机→平板）' : 'NFC 就绪：贴近标签写入学习状态');
    } catch (e) {
      this.onLog(`NFC 不可用：${(e as Error).message}（模拟器无 NFC，请用真机）`);
      this.mode = 'idle';
    }
  }

  private async handleTag(tagInfo: tag.TagInfo): Promise<void> {
    if (this.mode === 'read') {
      await this.readInviteCode(tagInfo);
    } else if (this.mode === 'write') {
      await this.writeInviteCode(tagInfo);
    }
  }

  private async readInviteCode(tagInfo: tag.TagInfo): Promise<void> {
    try {
      const ndef: tag.NdefTag = tag.getNdef(tagInfo);
      await ndef.connect();
      const msg: tag.NdefMessage = await ndef.readNdef();
      const records: tag.NdefRecord[] = msg.getNdefRecords();
      for (const r of records) {
        const text: string = this.parseTextPayload(r.payload).trim();
        // 学习快照：同账号手机→平板接续
        if (text.startsWith(HANDOFF_PREFIX)) {
          const snapshot: string = text.substring(HANDOFF_PREFIX.length);
          this.onLog('读取到学习快照，正在接续…');
          this.onHandoff(snapshot);
          return;
        }
        // 兼容：6 位邀请码入班
        if (text.length === 6 && !isNaN(Number(text))) {
          this.onLog(`读取到邀请码 ${text}`);
          this.onCode(text);
          return;
        }
      }
      this.onLog('标签中未找到学习快照或邀请码');
    } catch (e) {
      this.onLog(`读取失败：${(e as Error).message}`);
    }
  }

  private async writeInviteCode(tagInfo: tag.TagInfo): Promise<void> {
    try {
      const ndef: tag.NdefTag = tag.getNdef(tagInfo);
      await ndef.connect();
      const record: tag.NdefRecord = tag.ndef.makeTextRecord(this.pendingWritePayload, 'zh');
      const msg: tag.NdefMessage = tag.ndef.createNdefMessage([record]);
      await ndef.writeNdef(msg);
      this.onLog('学习状态已写入标签：另一台设备（同账号）碰一碰即可接续');
    } catch (e) {
      this.onLog(`写入失败：${(e as Error).message}（标签需支持 NDEF、容量足够且未写保护）`);
    }
  }

  /** NDEF Text Record payload：首字节低 6 位为语言码长度，其后为语言码 + 正文（UTF-8） */
  private parseTextPayload(payload: number[]): string {
    if (payload.length < 1) {
      return '';
    }
    const langLen: number = payload[0] & 0x3F;
    const textBytes: number[] = payload.slice(1 + langLen);
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
    return decoder.decodeWithStream(new Uint8Array(textBytes));
  }
}

/** 全局单例 */
export const nfcService: NfcService = new NfcService();
