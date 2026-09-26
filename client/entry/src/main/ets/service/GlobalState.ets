import { ClassCourse, UserInfo } from '../model/Models';
import { Api } from './Api';

/** 跨端迁移快照结构 */
interface ContinueSnapshot {
  server: string;
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
  static accessToken: string = '';
  static course: ClassCourse | null = null;
  /** 录音结束后跳课时详情用 */
  static currentSessionId: number = -1;
  static beforeLeaveNote: ((done: () => void) => void) | null = null;
  static closeOutlineDetail: (() => void) | null = null;
  static closeClassDetail: (() => void) | null = null;
  static beforeLeaveClass: ((done: () => void) => void) | null = null;
  static pendingNoteSessionId: number = -1;
  static pendingOpenNoteId: number = -1;

  // ===== 协同能力开关（默认开启，可在设置页关闭）=====
  static nfcEnabled: boolean = true;
  static lanGrabEnabled: boolean = true;
  static continuationEnabled: boolean = true;
  // 接续快照只接受与固定后端地址一致的来源。

  static isTeacher(): boolean {
    return GlobalState.user !== null && GlobalState.user.role === 'teacher';
  }

  static userId(): number {
    return GlobalState.user === null ? -1 : GlobalState.user.id;
  }

  static courseId(): number {
    return GlobalState.course === null ? -1 : GlobalState.course.id;
  }

  static isPersonal(): boolean {
    return GlobalState.user?.account_type === 'personal';
  }

  static canManageCurrentCourse(): boolean {
    return GlobalState.course !== null && GlobalState.course.teacher_id === GlobalState.userId() &&
      (GlobalState.isTeacher() || GlobalState.course.is_personal === true);
  }

  static clearSession(): void {
    GlobalState.user = null;
    GlobalState.course = null;
    GlobalState.accessToken = '';
    GlobalState.currentSessionId = -1;
    GlobalState.closeOutlineDetail = null;
    GlobalState.closeClassDetail = null;
    GlobalState.beforeLeaveClass = null;
    GlobalState.pendingNoteSessionId = -1;
    GlobalState.pendingOpenNoteId = -1;
    AppStorage.setOrCreate<string>('continueSnapshot', '');
    AppStorage.setOrCreate<string>('continueRestoreState', '');
  }

  static setCourse(course: ClassCourse | null): void {
    GlobalState.course = course;
  }

  /** 状态变化时调用：刷新迁移快照，供 EntryAbility.onContinue 打包 */
  static updateSnapshot(tab: string): void {
    const snap: ContinueSnapshot = {
      server: Api.BASE_URL,
      user: GlobalState.user === null ? null : { id: GlobalState.user.id, name: '', role: 'student' },
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
      if (GlobalState.user === null || snap.user?.id !== GlobalState.user.id || GlobalState.accessToken === '' || snap.server !== Api.BASE_URL) {
        return '';
      }
      GlobalState.setCourse(snap.course);
      GlobalState.currentSessionId = snap.sessionId;
      return snap.tab;
    } catch (e) {
      return '';
    }
  }
}
