import { socket } from '@kit.NetworkKit';
import { util } from '@kit.ArkTS';
import { Note } from '../../model/Models';
import { GlobalState } from '../GlobalState';

/**
 * 局域网互抓 —— 同一账号在不同设备间切换（隔空抓取）：
 * - 两台设备登录同一账号、接入同一 WLAN；
 * - 本机开启共享后：UDP 应答发现请求（41520，携带 user_id），
 *   TCP 服务（41521）提供「学习状态快照」与「本机笔记」的拉取；
 * - 新设备发现同账号旧设备 → 「接续」拉取快照恢复现场，或逐篇抓取笔记。
 *
 * 协议：
 *   发现   'SS_DISCOVER'  →  'SS_HERE|设备名|角色|共享数|user_id'
 *   状态   {"cmd":"state"}      →  {"state":"<continueSnapshot JSON>"}
 *   列表   {"cmd":"list"}       →  {"notes":[{id,title,kind}]}
 *   抓取   {"cmd":"get","id":n} →  {"note":{title,kind,content}}
 *
 * 说明：模拟器 NAT 网络通常无法互相广播，需两台真机同一 WLAN 验证。
 */

const DISCOVER_PORT: number = 41520;
const TRANSFER_PORT: number = 41521;
const DISCOVER_REQ: string = 'SS_DISCOVER';
const DISCOVER_RESP: string = 'SS_HERE';

export interface PeerDevice {
  address: string;
  name: string;
  role: string;
  sharedCount: number;
  userId: number;
}

export interface SharedNoteMeta {
  id: number;
  title: string;
  kind: string;
}

export interface SharedNotePayload {
  title: string;
  kind: string;
  content: string;
}

interface CmdBody {
  cmd: string;
  id?: number;
}

interface ListReply {
  notes: SharedNoteMeta[];
}

interface GetReply {
  note: SharedNotePayload | null;
}

interface StateReply {
  state: string;
}

export class TransferService {
  private udp: socket.UDPSocket | null = null;
  private server: socket.TCPSocketServer | null = null;
  private sharing: boolean = false;
  private sharedNotes: Note[] = [];
  private deviceName: string = '设备';
  private deviceRole: string = 'student';
  /** 状态日志回调（UI 展示） */
  onLog: (msg: string) => void = (msg: string) => {
  };

  private decode(buf: ArrayBuffer): string {
    const decoder: util.TextDecoder = util.TextDecoder.create('utf-8');
    return decoder.decodeWithStream(new Uint8Array(buf));
  }

  // ================= 分享端 =================
  async startSharing(notes: Note[], deviceName: string, role: string): Promise<boolean> {
    this.sharedNotes = notes;
    this.deviceName = deviceName;
    this.deviceRole = role;
    if (this.sharing) {
      return true;
    }
    try {
      // UDP 发现应答
      this.udp = socket.constructUDPSocketInstance();
      const bindAddr: socket.NetAddress = { address: '0.0.0.0', port: DISCOVER_PORT, family: 1 };
      await this.udp.bind(bindAddr);
      this.udp.on('message', (value: socket.SocketMessageInfo) => {
        const text: string = this.decode(value.message);
        if (!text.startsWith(DISCOVER_REQ) || this.udp === null || !this.sharing) {
          return;
        }
        const resp: string =
          `${DISCOVER_RESP}|${this.deviceName}|${this.deviceRole}|${this.sharedNotes.length}|${GlobalState.userId()}`;
        const sendOpt: socket.UDPSendOptions = {
          data: resp,
          address: {
            address: value.remoteInfo.address,
            port: value.remoteInfo.port,
            family: 1
          }
        };
        this.udp.send(sendOpt);
      });

      // TCP 笔记服务
      this.server = socket.constructTCPSocketServerInstance();
      const listenAddr: socket.NetAddress = { address: '0.0.0.0', port: TRANSFER_PORT, family: 1 };
      await this.server.listen(listenAddr);
      this.server.on('connect', (client: socket.TCPSocketConnection) => {
        client.on('message', (value: socket.SocketMessageInfo) => {
          if (!this.sharing) {
            return;
          }
          const reply: string = this.handleCommand(this.decode(value.message));
          const opt: socket.TCPSendOptions = { data: reply };
          client.send(opt);
        });
      });

      this.sharing = true;
      this.onLog(`共享已开启（${notes.length} 篇），等待同学抓取`);
      return true;
    } catch (e) {
      this.onLog(`共享开启失败：${(e as Error).message}`);
      this.stopSharing();
      return false;
    }
  }

  private handleCommand(raw: string): string {
    try {
      const cmd: CmdBody = JSON.parse(raw.trim()) as CmdBody;
      if (cmd.cmd === 'state') {
        // 同账号设备切换：交出本机学习状态快照
        const snap: string | undefined = AppStorage.get<string>('continueSnapshot');
        const reply: StateReply = { state: snap ?? '' };
        return JSON.stringify(reply);
      }
      if (cmd.cmd === 'list') {
        const metas: SharedNoteMeta[] = this.sharedNotes.map((n: Note): SharedNoteMeta => {
          const m: SharedNoteMeta = { id: n.id, title: n.title, kind: n.kind };
          return m;
        });
        const reply: ListReply = { notes: metas };
        return JSON.stringify(reply);
      }
      if (cmd.cmd === 'get' && cmd.id !== undefined) {
        let payload: SharedNotePayload | null = null;
        for (const n of this.sharedNotes) {
          if (n.id === cmd.id) {
            payload = { title: n.title, kind: n.kind, content: n.content };
            break;
          }
        }
        const reply: GetReply = { note: payload };
        return JSON.stringify(reply);
      }
    } catch (e) {
      // 非法命令
    }
    const bad: GetReply = { note: null };
    return JSON.stringify(bad);
  }

  stopSharing(): void {
    this.sharing = false;
    if (this.udp !== null) {
      const u: socket.UDPSocket = this.udp;
      this.udp = null;
      u.close();
    }
    // TCPSocketServer 无显式 close：置 sharing=false 后忽略新请求
    this.onLog('共享已关闭');
  }

  isSharing(): boolean {
    return this.sharing;
  }

  // ================= 抓取端 =================
  /** UDP 广播发现附近分享设备，扫描 timeoutMs 后回调结果 */
  discover(timeoutMs: number, onDone: (peers: PeerDevice[]) => void): void {
    const found: Map<string, PeerDevice> = new Map();
    let udp: socket.UDPSocket | null = null;
    try {
      udp = socket.constructUDPSocketInstance();
    } catch (e) {
      this.onLog(`发现失败：${(e as Error).message}`);
      onDone([]);
      return;
    }
    const finish = (): void => {
      if (udp !== null) {
        const u: socket.UDPSocket = udp;
        udp = null;
        u.close();
      }
      const peers: PeerDevice[] = [];
      found.forEach((p: PeerDevice) => {
        peers.push(p);
      });
      onDone(peers);
    };

    const bindAddr: socket.NetAddress = { address: '0.0.0.0', port: 0, family: 1 };
    udp.bind(bindAddr)
      .then(() => {
        if (udp === null) {
          return;
        }
        udp.on('message', (value: socket.SocketMessageInfo) => {
          const text: string = this.decode(value.message);
          if (!text.startsWith(DISCOVER_RESP)) {
            return;
          }
          const parts: string[] = text.split('|');
          const peer: PeerDevice = {
            address: value.remoteInfo.address,
            name: parts.length > 1 ? parts[1] : '未知设备',
            role: parts.length > 2 ? parts[2] : 'student',
            sharedCount: parts.length > 3 ? Number(parts[3]) : 0,
            userId: parts.length > 4 ? Number(parts[4]) : -1
          };
          found.set(peer.address, peer);
        });
        const opt: socket.UDPSendOptions = {
          data: DISCOVER_REQ,
          address: { address: '255.255.255.255', port: DISCOVER_PORT, family: 1 }
        };
        return udp.send(opt);
      })
      .catch((e: Error) => {
        this.onLog(`广播失败：${e.message}（模拟器网络不支持广播，请用真机同一 WLAN）`);
      });
    setTimeout(finish, timeoutMs);
  }

  /** 单次 TCP 请求：连接 → 发送命令 → 收齐完整 JSON → 关闭 */
  private request(address: string, cmdJson: string, timeoutMs: number): Promise<string> {
    return new Promise<string>((resolve: (v: string) => void, reject: (e: Error) => void) => {
      const tcp: socket.TCPSocket = socket.constructTCPSocketInstance();
      let buffer: string = '';
      let settled: boolean = false;
      const done = (err: Error | null): void => {
        if (settled) {
          return;
        }
        settled = true;
        tcp.close();
        if (err !== null) {
          reject(err);
        } else {
          resolve(buffer);
        }
      };
      setTimeout(() => {
        done(buffer === '' ? new Error('连接超时') : null);
      }, timeoutMs);

      tcp.on('message', (value: socket.SocketMessageInfo) => {
        buffer += this.decode(value.message);
        try {
          JSON.parse(buffer);
          done(null); // JSON 已完整
        } catch (e) {
          // 继续等待剩余分片
        }
      });

      const bindAddr: socket.NetAddress = { address: '0.0.0.0', port: 0, family: 1 };
      tcp.bind(bindAddr)
        .then(() => {
          const connectOpt: socket.TCPConnectOptions = {
            address: { address: address, port: TRANSFER_PORT, family: 1 },
            timeout: timeoutMs
          };
          return tcp.connect(connectOpt);
        })
        .then(() => {
          const opt: socket.TCPSendOptions = { data: cmdJson };
          return tcp.send(opt);
        })
        .catch((e: Error) => {
          done(e);
        });
    });
  }

  async fetchNoteList(address: string): Promise<SharedNoteMeta[]> {
    const cmd: CmdBody = { cmd: 'list' };
    const raw: string = await this.request(address, JSON.stringify(cmd), 6000);
    const reply: ListReply = JSON.parse(raw) as ListReply;
    return reply.notes;
  }

  async fetchNote(address: string, id: number): Promise<SharedNotePayload | null> {
    const cmd: CmdBody = { cmd: 'get', id: id };
    const raw: string = await this.request(address, JSON.stringify(cmd), 8000);
    const reply: GetReply = JSON.parse(raw) as GetReply;
    return reply.note;
  }

  /** 同账号设备切换：拉取对方学习状态快照（continueSnapshot JSON） */
  async fetchState(address: string): Promise<string> {
    const cmd: CmdBody = { cmd: 'state' };
    const raw: string = await this.request(address, JSON.stringify(cmd), 6000);
    const reply: StateReply = JSON.parse(raw) as StateReply;
    return reply.state;
  }
}

/** 全局单例（分享状态跨页面保持） */
export const transferService: TransferService = new TransferService();
