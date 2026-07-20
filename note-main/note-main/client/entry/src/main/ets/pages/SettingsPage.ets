import { promptAction } from '@kit.ArkUI';
import { abilityAccessCtrl, common, Permissions } from '@kit.AbilityKit';
import { AppTheme } from '../common/AppTheme';
import { Api } from '../service/Api';
import { GlobalState } from '../service/GlobalState';
import { CollabManager } from '../service/collab/CollabManager';
import { nfcService } from '../service/collab/NfcService';
import {
  PeerDevice,
  SharedNoteMeta,
  SharedNotePayload,
  transferService
} from '../service/collab/TransferService';

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
  @State lanOn: boolean = GlobalState.lanGrabEnabled;
  @State continueOn: boolean = GlobalState.continuationEnabled;
  @State serverUrl: string = Api.BASE_URL;
  @State nfcLog: string = '';
  @State lanLog: string = '';
  @State discovering: boolean = false;
  @State peers: PeerDevice[] = [];
  @State selectedPeer: PeerDevice | null = null;
  @State peerNotes: SharedNoteMeta[] = [];
  @State grabbedIds: number[] = [];

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

  private startDiscover(): void {
    this.discovering = true;
    this.peers = [];
    this.selectedPeer = null;
    this.peerNotes = [];
    this.lanLog = '正在扫描同一 WLAN 内我的设备…';
    transferService.discover(3000, (peers: PeerDevice[]) => {
      // 同账号设备切换：只显示登录同一账号的设备
      this.peers = peers.filter((p: PeerDevice) => p.userId === GlobalState.userId());
      this.discovering = false;
      this.lanLog = this.peers.length === 0 ?
        '未发现我的设备（两台真机需同一 WLAN、登录同一账号并开启共享）' :
        `发现 ${this.peers.length} 台我的设备`;
    });
  }

  /** 接续：拉取另一台设备的学习进度并恢复现场 */
  private async takeoverFrom(p: PeerDevice): Promise<void> {
    try {
      const state: string = await transferService.fetchState(p.address);
      CollabManager.applyHandoff(state, `已从「${p.name}」`);
      this.onClose();
    } catch (e) {
      this.toast(`接续失败：${(e as Error).message}`);
    }
  }

  private async openPeer(p: PeerDevice): Promise<void> {
    this.selectedPeer = p;
    this.peerNotes = [];
    try {
      this.peerNotes = await transferService.fetchNoteList(p.address);
      this.lanLog = `${p.name} 共享了 ${this.peerNotes.length} 篇笔记`;
    } catch (e) {
      this.lanLog = `获取列表失败：${(e as Error).message}`;
    }
  }

  private async grabNote(meta: SharedNoteMeta): Promise<void> {
    if (this.selectedPeer === null) {
      return;
    }
    try {
      const payload: SharedNotePayload | null =
        await transferService.fetchNote(this.selectedPeer.address, meta.id);
      if (payload === null) {
        this.toast('对方未提供该笔记');
        return;
      }
      interface NoteBody {
        class_course_id: number;
        owner_id: number;
        title: string;
        kind: string;
        content: string;
      }

      const body: NoteBody = {
        class_course_id: GlobalState.courseId(),
        owner_id: GlobalState.userId(),
        title: `${payload.title}（来自${this.selectedPeer.name}）`,
        kind: payload.kind,
        content: payload.content
      };
      await Api.post('/notes', body);
      this.grabbedIds = this.grabbedIds.concat([meta.id]);
      this.toast(`已抓取「${payload.title}」到我的笔记`);
    } catch (e) {
      this.toast(`抓取失败：${(e as Error).message}`);
    }
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

        this.switchRow('🫳', '局域网互抓', '同账号设备间切换进度与笔记', this.lanOn,
          (v: boolean): void => {
            this.lanOn = v;
            GlobalState.lanGrabEnabled = v;
            CollabManager.applyLan(v);
          })
        if (this.lanOn) {
          Row({ space: AppTheme.SPACE_S }) {
            Text(this.lanLog === '' ? '共享待命中，可在新设备上发现本机' : this.lanLog)
              .fontSize(AppTheme.FONT_CAPTION)
              .fontColor(AppTheme.TEXT_TERTIARY)
              .layoutWeight(1)
              .maxLines(2)
            Button(this.discovering ? '扫描中…' : '发现我的设备')
              .fontSize(AppTheme.FONT_CAPTION)
              .height(32)
              .enabled(!this.discovering)
              .fontColor('#FFFFFF')
              .backgroundColor(AppTheme.PRIMARY)
              .borderRadius(999)
              .onClick(() => {
                this.startDiscover();
              })
          }
          .width('100%')

          ForEach(this.peers, (p: PeerDevice) => {
            Row({ space: AppTheme.SPACE_S }) {
              Text('📱').fontSize(16)
              Column({ space: 1 }) {
                Text(p.name)
                  .fontSize(AppTheme.FONT_CAPTION)
                  .fontColor(AppTheme.TEXT_PRIMARY)
                Text(`我的设备 · ${p.sharedCount} 篇笔记`)
                  .fontSize(10)
                  .fontColor(AppTheme.TEXT_TERTIARY)
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)

              Text('接续')
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor('#FFFFFF')
                .padding({ left: 12, right: 12, top: 5, bottom: 5 })
                .borderRadius(999)
                .backgroundColor(AppTheme.PRIMARY)
                .onClick(() => {
                  this.takeoverFrom(p);
                })
              Text('笔记')
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(AppTheme.PRIMARY_DEEP)
                .onClick(() => {
                  this.openPeer(p);
                })
            }
            .width('100%')
            .padding(AppTheme.SPACE_S)
            .borderRadius(AppTheme.RADIUS_TAG)
            .backgroundColor(AppTheme.BG_CARD)
          }, (p: PeerDevice) => p.address)

          ForEach(this.peerNotes, (m: SharedNoteMeta) => {
            Row({ space: AppTheme.SPACE_S }) {
              Text(m.kind === 'md' ? '📝' : '✍️').fontSize(14)
              Text(m.title)
                .fontSize(AppTheme.FONT_CAPTION)
                .fontColor(AppTheme.TEXT_SECONDARY)
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .layoutWeight(1)
              if (this.grabbedIds.indexOf(m.id) >= 0) {
                Text('已抓取').fontSize(AppTheme.FONT_CAPTION).fontColor(AppTheme.SUCCESS)
              } else {
                Text('抓取')
                  .fontSize(AppTheme.FONT_CAPTION)
                  .fontColor(AppTheme.PRIMARY_DEEP)
                  .onClick(() => {
                    this.grabNote(m);
                  })
              }
            }
            .width('100%')
            .padding({ left: AppTheme.SPACE_L, right: AppTheme.SPACE_S, top: 6, bottom: 6 })
          }, (m: SharedNoteMeta) => `${m.id}`)
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
            Api.BASE_URL = this.serverUrl.trim();
            this.toast('已保存，返回后重新加载生效');
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
      .width(400)
      .height('100%')
      .padding(AppTheme.SPACE_XL)
      .backgroundColor(AppTheme.BG_SUNKEN)
    }
    .width('100%')
    .height('100%')
  }
}
