import { ClassCourse, UserInfo } from '../model/Models';

/** 跨端迁移快照结构 */
interface ContinueSnapshot {
  user: UserInfo | null;
  course: ClassCourse | null;
  tab: string;
  sessionId: number;
}

/**
 * 全局会话状态：当前登录用户 / 当前课程集合 / 页面间传参。
 * 同时负责维护跨端迁移快照（AppStorage: continueSnapshot）。
 */
export class GlobalState {
  static user: UserInfo | null = null;
  static course: ClassCourse | null = null;
  /** 录音结束后跳课时详情用 */
  static currentSessionId: number = -1;

  // ===== 协同能力开关（默认开启，可在设置页关闭）=====
  static nfcEnabled: boolean = true;
  static lanGrabEnabled: boolean = true;
  static continuationEnabled: boolean = true;
  // 服务器地址可在设置页修改（写入 Api.BASE_URL）

  static isTeacher(): boolean {
    return GlobalState.user !== null && GlobalState.user.role === 'teacher';
  }

  static userId(): number {
    return GlobalState.user === null ? -1 : GlobalState.user.id;
  }

  static courseId(): number {
    return GlobalState.course === null ? -1 : GlobalState.course.id;
  }

  /** 状态变化时调用：刷新迁移快照，供 EntryAbility.onContinue 打包 */
  static updateSnapshot(tab: string): void {
    const snap: ContinueSnapshot = {
      user: GlobalState.user,
      course: GlobalState.course,
      tab: tab,
      sessionId: GlobalState.currentSessionId
    };
    AppStorage.setOrCreate<string>('continueSnapshot', JSON.stringify(snap));
  }

  /** 目标端恢复：返回应进入的页签（'' 表示恢复失败） */
  static restoreFromJson(json: string): string {
    try {
      const snap: ContinueSnapshot = JSON.parse(json) as ContinueSnapshot;
      GlobalState.user = snap.user;
      GlobalState.course = snap.course;
      GlobalState.currentSessionId = snap.sessionId;
      return snap.tab;
    } catch (e) {
      return '';
    }
  }
}
