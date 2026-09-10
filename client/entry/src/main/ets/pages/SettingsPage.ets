import { promptAction } from '@kit.ArkUI';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { AppTheme } from '../common/AppTheme';
import { Api } from '../service/Api';
import { SessionStore } from '../service/SessionStore';
import { GlobalState } from '../service/GlobalState';
import { CollabManager } from '../service/collab/CollabManager';
import { nfcService } from '../service/collab/NfcService';
import { transferService } from '../service/collab/TransferService';
import { AccountSecurityPage } from './AccountSecurityPage';

/**
 * 设置（覆盖层）：账号信息 / 服务器地址 / 协同能力开关（NFC·局域网互抓·跨端接续，默认开启）。
 * 协同能力集中在此以开关形式管理，不再占用独立页签。
 */
@Component
export struct SettingsPage {
  onClose: () => void = () => {
  };
  onLogout: () => void = () => {
  };
  @State nfcOn: boolean = GlobalState.nfcEnabled;
  @State securityOpen: boolean = false;
  @State lanOn: boolean = GlobalState.lanGrabEnabled;
  @State continueOn: boolean = GlobalState.continuationEnabled;
  @State serverUrl: string = Api.BASE_URL;
  @State nfcLog: string = '';
  @State lanLog: string = '';

  aboutToAppear(): void {
    nfcService.onLog = (msg: string): void => {
      this.nfcLog = msg;
    };
    transferService.onLog = (msg: string): void => {
      this.lanLog = msg;
    };
  }

  private toast(msg: string): void {
    promptAction.showToast({ message: msg });
  }

  // ---------- 协同动作 ----------
  /** 把当前学习状态快照写入 NFC 标签（手机端操作，平板碰读接续） */
  private writeStateTag(): void {
    const snap: string | undefined = AppStorage.get<string>('continueSnapshot');
    if (snap === undefined || snap === '') {
      this.toast('暂无学习状态（请先进入课程）');
      return;
    }
    nfcService.startWriting(snap);
  }

  private async requestContinuation(): Promise<void> {
    try {
      const perms: Permissions[] = ['ohos.permission.DISTRIBUTED_DATASYNC'];
      const atManager: abilityAccessCtrl.AtManager = abilityAccessCtrl.createAtManager();
      const ctx: common.UIAbilityContext = getContext(this) as common.UIAbilityContext;
      const result = await atManager.requestPermissionsFromUser(ctx, perms);
      const granted: boolean = result.authResults.length > 0 && result.authResults[0] === 0;
      this.toast(granted ? '流转授权已开启，可在另一设备任务中心接续' : '未授权，跨端接续不可用');
    } catch (e) {
      this.toast(`授权失败：${(e as Error).message}`);
    }
  }

  @Builder
  sectionTitle(text: string) {
    Text(text)
      .fontSize(AppTheme.FONT_CAPTION)
      .fontColor(AppTheme.TEXT_TERTIARY)
      .width('100%')
      .margin({ top: AppTheme.SPACE_S })
  }

  @Builder
  switchRow(icon: string, title: string, desc: string, on: boolean, onToggle: (v: boolean) => void) {
    Row({ space: AppTheme.SPACE_M }) {
      Text(icon)
        .fontSize(20)
        .width(40)
        .height(40)
        .textAlign(TextAlign.Center)
        .borderRadius(12)
        .backgroundColor(AppTheme.PRIMARY_LIGHT)
      Column({ space: 2 }) {
        Text(title).fontSize(AppTheme.FONT_BODY).fontColor(AppTheme.TEXT_PRIMARY)
        Text(desc).fontSize(AppTheme.FONT_CAPTION).fontColor(AppTheme.TEXT_TERTIARY)
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)

      Toggle({ type: ToggleType.Switch, isOn: on })
        .selectedColor(AppTheme.PRIMARY)
        .onChange((v: boolean) => {
          onToggle(v);
        })
    }
    .width('100%')
    .padding(AppTheme.SPACE_M)
    .borderRadius(AppTheme.RADIUS_CARD)
    .backgroundColor(AppTheme.BG_CARD)
  }

  build() {
    if (this.securityOpen) {
      AccountSecurityPage({ onClose: () => { this.securityOpen = false; },
        onPasswordChanged: () => { this.toast('密码已修改，请重新登录'); this.onLogout(); } })
    } else {
    Stack({ alignContent: Alignment.End }) {
      // 遮罩
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor('rgba(0,0,0,0.35)')
        .onClick(() => {
          this.onClose();
        })

      // 右侧抽屉
      Column({ space: AppTheme.SPACE_L }) {
        Row() {
          Text('设置').fontSize(AppTheme.FONT_TITLE).fontWeight(FontWeight.Bold).fontColor(AppTheme.INK)
          Blank()
          Text('✕')
            .fontSize(18)
            .fontColor(AppTheme.TEXT_SECONDARY)
            .onClick(() => {
              this.onClose();
            })
        }
        .width('100%')

        Scroll() {
          Column({ space: AppTheme.SPACE_L }) {
            // 账号
            this.sectionTitle('账号')
        Row({ space: AppTheme.SPACE_M }) {
          Text(GlobalState.user === null ? '' : GlobalState.user.name.substring(0, 1))
            .fontSize(AppTheme.FONT_SUBTITLE)
            .fontColor('#FFFFFF')
            .width(44)
            .height(44)
            .textAlign(TextAlign.Center)
            .borderRadius(22)
            .backgroundColor(GlobalState.isTeacher() ? AppTheme.INK : AppTheme.PRIMARY)
          Column({ space: 2 }) {
            Text(GlobalState.user === null ? '' : GlobalState.user.name)
              .fontSize(AppTheme.FONT_BODY)
              .fontColor(AppTheme.TEXT_PRIMARY)
            Text(GlobalState.isTeacher() ? '教师' : '学生')
              .fontSize(AppTheme.FONT_CAPTION)
              .fontColor(AppTheme.TEXT_TERTIARY)
          }
          .alignItems(HorizontalAlign.Start)
          .layoutWeight(1)

          Text('切换身份')
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.DANGER)
            .padding({ left: 14, right: 14, top: 7, bottom: 7 })
            .borderRadius(999)
            .backgroundColor(AppTheme.tagBg(AppTheme.DANGER))
            .onClick(() => {
              this.onLogout();
            })
        }
        .width('100%')
        .padding(AppTheme.SPACE_M)
        .borderRadius(AppTheme.RADIUS_CARD)
        .backgroundColor(AppTheme.BG_CARD)

        Button('账号安全').width('100%').backgroundColor(AppTheme.PRIMARY_LIGHT).fontColor(AppTheme.PRIMARY_DEEP)
          .enabled(AppStorage.get<boolean>('recordingActive') !== true).onClick(() => { this.securityOpen = true; })
        // 鸿蒙协同（默认开启）
        this.sectionTitle('鸿蒙协同（默认开启，真机可用）')
        this.switchRow('📳', 'NFC 碰一碰', '同账号手机→平板，一碰接续学习', this.nfcOn,
          (v: boolean): void => {
            this.nfcOn = v;
            GlobalState.nfcEnabled = v;
            CollabManager.applyNfc(v);
          })
        if (this.nfcOn) {
          Button('📳 把当前学习状态写入 NFC 标签')
            .width('100%')
            .height(40)
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.PRIMARY_DEEP)
            .backgroundColor(AppTheme.PRIMARY_LIGHT)
            .borderRadius(999)
            .onClick(() => {
              this.writeStateTag();
            })
        }
        if (this.nfcLog !== '') {
          Text(this.nfcLog)
            .fontSize(AppTheme.FONT_CAPTION)
            .fontColor(AppTheme.TEXT_TERTIARY)
            .width('100%')
        }

        this.switchRow('🫳', '系统隔空传送', '华为握拳抓取、张手释放', this.lanOn,
          (v: boolean): void => {
            this.lanOn = v;
            GlobalState.lanGrabEnabled = v;
            CollabManager.applyLan(v);
          })
        if (this.lanOn && this.lanLog !== '') {
          Text(this.lanLog).fontSize(AppTheme.FONT_CAPTION).fontColor(AppTheme.TEXT_TERTIARY)
        }

        this.switchRow('🔁', '跨端接续', '手机↔平板无缝续学（同华为账号）', this.continueOn,
          (v: boolean): void => {
            this.continueOn = v;
            GlobalState.continuationEnabled = v;
            if (v) {
              this.requestContinuation();
            } else {
              this.toast('跨端接续已关闭');
            }
          })

        // 服务器
        this.sectionTitle('服务器地址')
        TextInput({ text: this.serverUrl })
          .fontSize(AppTheme.FONT_CAPTION)
          .height(44)
          .borderRadius(AppTheme.RADIUS_CARD)
          .backgroundColor(AppTheme.BG_SUNKEN)
          .onChange((v: string) => {
            this.serverUrl = v;
          })
        Button('保存服务器地址')
          .width('100%')
          .height(42)
          .fontSize(AppTheme.FONT_BODY)
          .fontColor('#FFFFFF')
          .backgroundColor(AppTheme.PRIMARY)
          .borderRadius(999)
          .onClick(() => {
            const url = this.serverUrl.trim().replace(/\/+$/, '');
            if (!/^https?:\/\/[^\s/?#@]+(?:\/[^\s?#]*)?\/api\/v1$/.test(url)) {
              this.toast('请输入有效的服务器 API 地址'); return;
            }
            if (url !== Api.BASE_URL) {
              if (AppStorage.get<boolean>('recordingActive') === true) { this.toast('请先结束录音'); return; }
              this.onLogout();
              Api.BASE_URL = url;
              SessionStore.save(url, '').catch(() => {});
            }
            this.toast('服务器地址已保存');
          })
          }
          .width('100%')
        }
        .layoutWeight(1)
        .scrollBar(BarState.Off)
        .align(Alignment.Top)

        Text('智慧伴学 Demo · v0.2')
          .fontSize(AppTheme.FONT_CAPTION)
          .fontColor(AppTheme.TEXT_TERTIARY)
      }
      .width('100%').constraintSize({ maxWidth: 400 })
      .height('100%')
      .padding(AppTheme.SPACE_XL)
      .backgroundColor(AppTheme.BG_SUNKEN)
    }
    .width('100%')
    .height('100%')
    }
  }
}
