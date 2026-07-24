import { fileIo } from '@kit.CoreFileKit';
import {
  AiAgentInfo,
  ChatMessageInfo,
  ChatSessionInfo,
  ClassCourse,
  CourseSession,
  CourseWorkspaceStats,
  KeywordInsight,
  Note,
  Outline,
  TranscriptSegment,
  UserInfo
} from '../model/Models';

interface LocalQuestionLog {
  id: number;
  class_course_id: number;
  user_id: number;
  chat_session_id: number;
  question: string;
  keywords: string[];
  kb_missed: boolean;
  created_at: string;
}

interface LocalData {
  version: number;
  users: UserInfo[];
  courses: ClassCourse[];
  memberships: LocalMembership[];
  sessions: CourseSession[];
  transcripts: TranscriptSegment[];
  outlines: Outline[];
  notes: Note[];
  chatSessions: ChatSessionInfo[];
  chatMessages: ChatMessageInfo[];
  questionLogs: LocalQuestionLog[];
}

interface LocalMembership {
  id: number;
  user_id: number;
  class_course_id: number;
}

interface QueryMap {
  user_id?: string;
  class_course_id?: string;
}

interface ParsedPath {
  pathname: string;
  query: QueryMap;
}

interface CreateCourseBody {
  name: string;
  class_name: string;
  teacher_id: number;
}

interface JoinCourseBody {
  user_id: number;
  invite_code: string;
}

interface CreateSessionBody {
  class_course_id: number;
  title: string;
  creator_id: number;
}

interface CreateNoteBody {
  class_course_id: number;
  owner_id: number;
  title: string;
  kind: string;
  content: string;
}

interface UpdateNoteBody {
  title?: string;
  content?: string;
}

interface UpdateOutlineBody {
  markdown: string;
}

interface ReviewOutlineBody {
  user_id: number;
  action: string;
}

interface CreateChatBody {
  class_course_id: number;
  user_id: number;
  title: string;
}

interface GeneratePracticeBody {
  class_course_id: number;
  user_id: number;
  count: number;
  mode: string;
  topic: string;
  difficulty: string;
  requirements: string;
}

export interface LocalPracticeQuestion {
  id: number;
  type: string;
  difficulty: string;
  topic: string;
  stem: string;
  options: string[];
  answer: number;
  explanation: string;
  source: string;
}

export interface LocalPracticeResponse {
  questions: LocalPracticeQuestion[];
  knowledge_sources: string[];
}

export interface LocalAgentTurn {
  agent: AiAgentInfo | null;
  role: string;
  content: string;
}

export interface LocalAskResult {
  sources: string[];
  warning: string;
  turns: LocalAgentTurn[];
}

const AGENTS: AiAgentInfo[] = [
  {
    id: 'analyst', name: '小研', title: '严谨分析派',
    personality: '冷静严谨，先澄清概念再给结论', focus: '概念、条件与推理',
    catchphrase: '先把条件理清楚。', color: '#3F7DFF'
  },
  {
    id: 'skeptic', name: '小问', title: '追问质疑派',
    personality: '善用追问和反例发现理解漏洞', focus: '反例、边界与易错点',
    catchphrase: '换个条件还成立吗？', color: '#7A63F3'
  },
  {
    id: 'connector', name: '小拓', title: '类比拓展派',
    personality: '活跃，擅长把抽象知识连到实例', focus: '类比、应用与章节联系',
    catchphrase: '可以把它想成……', color: '#FFB84D'
  },
  {
    id: 'synthesizer', name: '小结', title: '温和总结派',
    personality: '耐心清晰，负责归纳共识与分歧', focus: '总结与下一步建议',
    catchphrase: '我们把观点收一下。', color: '#05CE91'
  }
];

const KB_WARNING: string =
  '知识库中暂时未包含该知识点，以下内容可能有误，请结合课程资料核对。';

export class LocalBackend {
  private static dataPath: string = '';
  private static ready: boolean = false;
  private static data: LocalData = LocalBackend.seedData();

  static initialize(filesDir: string): void {
    if (LocalBackend.ready) {
      return;
    }
    LocalBackend.dataPath = `${filesDir}/zhiban_local_backend.json`;
    let needsPersist: boolean = false;
    try {
      if (fileIo.accessSync(LocalBackend.dataPath)) {
        const raw: string = fileIo.readTextSync(LocalBackend.dataPath);
        const loaded: LocalData = JSON.parse(raw) as LocalData;
        if (loaded.version === 1 && loaded.users.length > 0) {
          LocalBackend.data = loaded;
        } else {
          LocalBackend.data = LocalBackend.seedData();
          needsPersist = true;
        }
      } else {
        LocalBackend.data = LocalBackend.seedData();
        needsPersist = true;
      }
    } catch (e) {
      LocalBackend.data = LocalBackend.seedData();
      needsPersist = true;
    }
    LocalBackend.ready = true;
    if (needsPersist) {
      try {
        LocalBackend.persist();
      } catch (e) {
        // The in-memory backend remains available if sandbox persistence fails.
      }
    }
  }

  static isReady(): boolean {
    return LocalBackend.ready;
  }

  static get(path: string): string {
    LocalBackend.ensureReady();
    const parsed: ParsedPath = LocalBackend.parsePath(path);
    const pathname: string = parsed.pathname;
    const query: QueryMap = parsed.query;

    if (pathname === '/auth/users') {
      return JSON.stringify(LocalBackend.data.users);
    }
    if (pathname === '/courses') {
      const userId: number = LocalBackend.queryNumber(query, 'user_id');
      const courseIds: number[] = [];
      for (const membership of LocalBackend.data.memberships) {
        if (membership.user_id === userId) {
          courseIds.push(membership.class_course_id);
        }
      }
      const result: ClassCourse[] = [];
      for (const course of LocalBackend.data.courses) {
        if (courseIds.indexOf(course.id) >= 0) {
          result.push(LocalBackend.courseWithTeacher(course));
        }
      }
      return JSON.stringify(result);
    }
    const statsMatch: RegExpMatchArray | null = pathname.match(/^\/courses\/(\d+)\/stats$/);
    if (statsMatch !== null) {
      const courseId: number = Number(statsMatch[1]);
      const userId: number = LocalBackend.queryNumber(query, 'user_id');
      LocalBackend.requireMembership(courseId, userId);
      const stats: CourseWorkspaceStats = {
        class_course_id: courseId,
        official_lesson_count: LocalBackend.officialLessonCount(courseId),
        personal_note_count: LocalBackend.personalNoteCount(courseId, userId),
        class_note_count: LocalBackend.classNoteCount(courseId)
      };
      return JSON.stringify(stats);
    }
    if (pathname === '/sessions') {
      const courseId: number = LocalBackend.queryNumber(query, 'class_course_id');
      const userId: number = LocalBackend.queryNumber(query, 'user_id', -1);
      const result: CourseSession[] = [];
      for (const session of LocalBackend.data.sessions) {
        if (session.class_course_id !== courseId) {
          continue;
        }
        if (userId > 0 && !LocalBackend.canViewSession(session, userId)) {
          continue;
        }
        result.push(LocalBackend.sessionWithOutlineMeta(session, userId));
      }
      result.sort((a: CourseSession, b: CourseSession): number => b.id - a.id);
      return JSON.stringify(result);
    }
    if (pathname === '/sessions/outlines/pending') {
      const courseId: number = LocalBackend.queryNumber(query, 'class_course_id');
      const result: Outline[] = [];
      for (const outline of LocalBackend.data.outlines) {
        if (outline.class_course_id === courseId && outline.owner_id === -1 &&
          (outline.status === 'draft' || outline.status === 'pending')) {
          const copy: Outline = LocalBackend.copyOutline(outline);
          const session: CourseSession | null = LocalBackend.findSession(outline.session_id);
          copy.session_title = session === null ? '' : session.title;
          result.push(copy);
        }
      }
      return JSON.stringify(result);
    }
    const transcriptMatch: RegExpMatchArray | null = pathname.match(/^\/sessions\/(\d+)\/transcript$/);
    if (transcriptMatch !== null) {
      const sessionId: number = Number(transcriptMatch[1]);
      const userId: number = LocalBackend.queryNumber(query, 'user_id', -1);
      const session: CourseSession = LocalBackend.requireSession(sessionId);
      if (userId > 0 && !LocalBackend.canViewSession(session, userId)) {
        throw new Error('无权查看该课时');
      }
      const result: TranscriptSegment[] = [];
      for (const segment of LocalBackend.data.transcripts) {
        if (segment.session_id === sessionId) {
          result.push(segment);
        }
      }
      result.sort((a: TranscriptSegment, b: TranscriptSegment): number => a.seq - b.seq);
      return JSON.stringify(result);
    }
    const outlineMatch: RegExpMatchArray | null = pathname.match(/^\/sessions\/(\d+)\/outline$/);
    if (outlineMatch !== null) {
      const sessionId: number = Number(outlineMatch[1]);
      const userId: number = LocalBackend.queryNumber(query, 'user_id', -1);
      const outline: Outline | null = LocalBackend.visibleOutline(sessionId, userId);
      if (outline === null) {
        throw new Error('提纲不存在');
      }
      return JSON.stringify(outline);
    }
    if (pathname === '/notes') {
      const courseId: number = LocalBackend.queryNumber(query, 'class_course_id');
      const userId: number = LocalBackend.queryNumber(query, 'user_id');
      const result: Note[] = [];
      for (const note of LocalBackend.data.notes) {
        if (note.class_course_id === courseId &&
          (note.owner_id === userId || note.visibility === 'shared')) {
          result.push(note);
        }
      }
      result.sort((a: Note, b: Note): number => b.id - a.id);
      return JSON.stringify(result);
    }
    if (pathname === '/chat/agents') {
      return JSON.stringify(AGENTS);
    }
    if (pathname === '/chat/sessions') {
      const courseId: number = LocalBackend.queryNumber(query, 'class_course_id');
      const userId: number = LocalBackend.queryNumber(query, 'user_id');
      const result: ChatSessionInfo[] = [];
      for (const session of LocalBackend.data.chatSessions) {
        if (session.class_course_id === courseId && session.user_id === userId) {
          result.push(session);
        }
      }
      result.sort((a: ChatSessionInfo, b: ChatSessionInfo): number => b.id - a.id);
      return JSON.stringify(result);
    }
    const messagesMatch: RegExpMatchArray | null = pathname.match(/^\/chat\/sessions\/(\d+)\/messages$/);
    if (messagesMatch !== null) {
      const chatId: number = Number(messagesMatch[1]);
      const result: ChatMessageInfo[] = [];
      for (const message of LocalBackend.data.chatMessages) {
        if (message.chat_session_id === chatId) {
          result.push(message);
        }
      }
      result.sort((a: ChatMessageInfo, b: ChatMessageInfo): number => a.id - b.id);
      return JSON.stringify(result);
    }
    if (pathname === '/analytics/classroom') {
      return LocalBackend.analytics(query);
    }
    throw new Error(`本地后端未实现 GET ${pathname}`);
  }

  static post(path: string, body?: object): string {
    LocalBackend.ensureReady();
    const parsed: ParsedPath = LocalBackend.parsePath(path);
    const pathname: string = parsed.pathname;
    const query: QueryMap = parsed.query;

    if (pathname === '/courses') {
      const input: CreateCourseBody = LocalBackend.body<CreateCourseBody>(body);
      const course: ClassCourse = {
        id: LocalBackend.nextCourseId(),
        name: input.name,
        class_name: input.class_name,
        teacher_id: input.teacher_id,
        invite_code: LocalBackend.inviteCode(),
        created_at: LocalBackend.now(),
        teacher_name: LocalBackend.userName(input.teacher_id)
      };
      LocalBackend.data.courses.push(course);
      LocalBackend.data.memberships.push({
        id: LocalBackend.nextMembershipId(), user_id: input.teacher_id, class_course_id: course.id
      });
      LocalBackend.persist();
      return JSON.stringify(course);
    }
    if (pathname === '/courses/join') {
      const input: JoinCourseBody = LocalBackend.body<JoinCourseBody>(body);
      let found: ClassCourse | null = null;
      for (const course of LocalBackend.data.courses) {
        if (course.invite_code === input.invite_code) {
          found = course;
          break;
        }
      }
      if (found === null) {
        throw new Error('邀请码无效');
      }
      if (!LocalBackend.hasMembership(found.id, input.user_id)) {
        LocalBackend.data.memberships.push({
          id: LocalBackend.nextMembershipId(), user_id: input.user_id, class_course_id: found.id
        });
        LocalBackend.persist();
      }
      return JSON.stringify(LocalBackend.courseWithTeacher(found));
    }
    if (pathname === '/sessions') {
      const input: CreateSessionBody = LocalBackend.body<CreateSessionBody>(body);
      const session: CourseSession = {
        id: LocalBackend.nextSessionId(),
        class_course_id: input.class_course_id,
        title: input.title,
        creator_id: input.creator_id,
        status: 'recording',
        created_at: LocalBackend.now()
      };
      LocalBackend.data.sessions.push(session);
      LocalBackend.persist();
      return JSON.stringify(session);
    }
    const finishMatch: RegExpMatchArray | null = pathname.match(/^\/sessions\/(\d+)\/finish$/);
    if (finishMatch !== null) {
      const session: CourseSession = LocalBackend.requireSession(Number(finishMatch[1]));
      session.status = 'done';
      LocalBackend.persist();
      return JSON.stringify(session);
    }
    const generateMatch: RegExpMatchArray | null = pathname.match(/^\/sessions\/(\d+)\/outline\/generate$/);
    if (generateMatch !== null) {
      const sessionId: number = Number(generateMatch[1]);
      const session: CourseSession = LocalBackend.requireSession(sessionId);
      const userId: number = LocalBackend.queryNumber(query, 'user_id', -1);
      let transcript: string = '';
      for (const segment of LocalBackend.data.transcripts) {
        if (segment.session_id === sessionId) {
          transcript += `${segment.text}\n`;
        }
      }
      if (transcript.trim() === '') {
        throw new Error('尚无转写文本');
      }
      const ownerId: number = LocalBackend.isTeacher(userId) ? -1 : userId;
      let outline: Outline | null = LocalBackend.findOutline(sessionId, ownerId, false);
      if (outline === null) {
        outline = {
          id: LocalBackend.nextOutlineId(), session_id: sessionId,
          class_course_id: session.class_course_id, owner_id: ownerId,
          markdown: LocalBackend.generateOutlineText(session.title, transcript),
          status: 'generated', updated_at: LocalBackend.now()
        };
        LocalBackend.data.outlines.push(outline);
      } else {
        outline.markdown = LocalBackend.generateOutlineText(session.title, transcript);
        outline.status = 'generated';
        outline.updated_at = LocalBackend.now();
      }
      LocalBackend.persist();
      return JSON.stringify(outline);
    }
    const reviewMatch: RegExpMatchArray | null = pathname.match(/^\/sessions\/(\d+)\/outline\/review$/);
    if (reviewMatch !== null) {
      const sessionId: number = Number(reviewMatch[1]);
      const input: ReviewOutlineBody = LocalBackend.body<ReviewOutlineBody>(body);
      const outline: Outline | null = LocalBackend.findOutline(sessionId, -1, false);
      if (outline === null) {
        throw new Error('提纲不存在');
      }
      if (!LocalBackend.isTeacher(input.user_id)) {
        throw new Error('仅教师可以审核提纲');
      }
      outline.status = input.action === 'publish' ? 'published' : 'rejected';
      outline.updated_at = LocalBackend.now();
      LocalBackend.persist();
      return JSON.stringify(outline);
    }
    if (pathname === '/notes') {
      const input: CreateNoteBody = LocalBackend.body<CreateNoteBody>(body);
      const note: Note = {
        id: LocalBackend.nextNoteId(), class_course_id: input.class_course_id,
        owner_id: input.owner_id, title: input.title, kind: input.kind,
        content: input.content, visibility: 'private', quality_status: 'none',
        quality_score: null, updated_at: LocalBackend.now()
      };
      LocalBackend.data.notes.push(note);
      LocalBackend.persist();
      return JSON.stringify(note);
    }
    const shareMatch: RegExpMatchArray | null = pathname.match(/^\/notes\/(\d+)\/(share|unshare)$/);
    if (shareMatch !== null) {
      const note: Note = LocalBackend.requireNote(Number(shareMatch[1]));
      if (shareMatch[2] === 'share') {
        note.visibility = 'shared';
        note.quality_status = 'accepted';
        note.quality_score = 8;
      } else {
        note.visibility = 'private';
        note.quality_status = 'none';
        note.quality_score = null;
      }
      note.updated_at = LocalBackend.now();
      LocalBackend.persist();
      return JSON.stringify(note);
    }
    if (pathname === '/chat/sessions') {
      const input: CreateChatBody = LocalBackend.body<CreateChatBody>(body);
      const chat: ChatSessionInfo = {
        id: LocalBackend.nextChatSessionId(), class_course_id: input.class_course_id,
        user_id: input.user_id, title: input.title, created_at: LocalBackend.now()
      };
      LocalBackend.data.chatSessions.push(chat);
      LocalBackend.persist();
      return JSON.stringify(chat);
    }
    if (pathname === '/practice/generate') {
      const input: GeneratePracticeBody = LocalBackend.body<GeneratePracticeBody>(body);
      LocalBackend.requireMembership(input.class_course_id, input.user_id);
      return JSON.stringify(LocalBackend.practice(input));
    }
    throw new Error(`本地后端未实现 POST ${pathname}`);
  }

  static put(path: string, body: object): string {
    LocalBackend.ensureReady();
    const parsed: ParsedPath = LocalBackend.parsePath(path);
    const noteMatch: RegExpMatchArray | null = parsed.pathname.match(/^\/notes\/(\d+)$/);
    if (noteMatch !== null) {
      const note: Note = LocalBackend.requireNote(Number(noteMatch[1]));
      const input: UpdateNoteBody = LocalBackend.body<UpdateNoteBody>(body);
      if (input.title !== undefined) {
        note.title = input.title;
      }
      if (input.content !== undefined) {
        note.content = input.content;
      }
      note.updated_at = LocalBackend.now();
      LocalBackend.persist();
      return JSON.stringify(note);
    }
    const outlineMatch: RegExpMatchArray | null = parsed.pathname.match(/^\/sessions\/(\d+)\/outline$/);
    if (outlineMatch !== null) {
      const sessionId: number = Number(outlineMatch[1]);
      const session: CourseSession = LocalBackend.requireSession(sessionId);
      const input: UpdateOutlineBody = LocalBackend.body<UpdateOutlineBody>(body);
      const userId: number = LocalBackend.queryNumber(parsed.query, 'user_id', -1);
      const ownerId: number = userId < 0 || LocalBackend.isTeacher(userId) ? -1 : userId;
      let outline: Outline | null = LocalBackend.findOutline(sessionId, ownerId, false);
      if (outline === null) {
        outline = {
          id: LocalBackend.nextOutlineId(), session_id: sessionId,
          class_course_id: session.class_course_id, owner_id: ownerId,
          markdown: input.markdown, status: 'draft', updated_at: LocalBackend.now()
        };
        LocalBackend.data.outlines.push(outline);
      } else {
        outline.markdown = input.markdown;
        outline.status = 'draft';
        outline.updated_at = LocalBackend.now();
      }
      LocalBackend.persist();
      return JSON.stringify(outline);
    }
    throw new Error(`本地后端未实现 PUT ${parsed.pathname}`);
  }

  static remove(path: string): string {
    LocalBackend.ensureReady();
    const parsed: ParsedPath = LocalBackend.parsePath(path);
    const noteMatch: RegExpMatchArray | null = parsed.pathname.match(/^\/notes\/(\d+)$/);
    if (noteMatch !== null) {
      const id: number = Number(noteMatch[1]);
      const userId: number = LocalBackend.queryNumber(parsed.query, 'user_id');
      const note: Note = LocalBackend.requireNote(id);
      if (note.owner_id !== userId) {
        throw new Error('只能删除自己的笔记');
      }
      LocalBackend.data.notes = LocalBackend.data.notes.filter((item: Note): boolean => item.id !== id);
      LocalBackend.persist();
      return JSON.stringify({ ok: true, id: id });
    }
    const chatMatch: RegExpMatchArray | null = parsed.pathname.match(/^\/chat\/sessions\/(\d+)$/);
    if (chatMatch !== null) {
      const id: number = Number(chatMatch[1]);
      const userId: number = LocalBackend.queryNumber(parsed.query, 'user_id');
      const chat: ChatSessionInfo = LocalBackend.requireChatSession(id);
      if (chat.user_id !== userId) {
        throw new Error('只能删除自己的会话');
      }
      LocalBackend.data.chatSessions = LocalBackend.data.chatSessions.filter(
        (item: ChatSessionInfo): boolean => item.id !== id);
      LocalBackend.data.chatMessages = LocalBackend.data.chatMessages.filter(
        (item: ChatMessageInfo): boolean => item.chat_session_id !== id);
      LocalBackend.data.questionLogs = LocalBackend.data.questionLogs.filter(
        (item: LocalQuestionLog): boolean => item.chat_session_id !== id);
      LocalBackend.persist();
      return JSON.stringify({ ok: true, id: id });
    }
    throw new Error(`本地后端未实现 DELETE ${parsed.pathname}`);
  }

  static uploadChunk(sessionId: number, seq: number, data: ArrayBuffer): string {
    LocalBackend.ensureReady();
    const session: CourseSession = LocalBackend.requireSession(sessionId);
    LocalBackend.data.transcripts = LocalBackend.data.transcripts.filter(
      (item: TranscriptSegment): boolean => !(item.session_id === sessionId && item.seq === seq));
    const sampleTexts: string[] = [
      '本段课堂内容正在讲解数据结构的核心概念与使用场景。',
      '老师强调要先理解操作条件，再分析时间复杂度和空间复杂度。',
      '这一知识点可以通过具体示例、边界情况和代码实现进行巩固。',
      '请同学们记录易错点，并在课后通过练习题检查理解情况。'
    ];
    const segment: TranscriptSegment = {
      id: LocalBackend.nextTranscriptId(), session_id: sessionId, seq: seq,
      start_ms: seq * 4000, end_ms: (seq + 1) * 4000,
      text: sampleTexts[seq % sampleTexts.length]
    };
    LocalBackend.data.transcripts.push(segment);
    session.status = 'transcribing';
    LocalBackend.persist();
    return JSON.stringify(segment);
  }

  static ask(chatSessionId: number, question: string, contextNote: string, mode: string): LocalAskResult {
    LocalBackend.ensureReady();
    const chat: ChatSessionInfo = LocalBackend.requireChatSession(chatSessionId);
    LocalBackend.data.chatMessages.push({
      id: LocalBackend.nextChatMessageId(), chat_session_id: chatSessionId,
      role: 'user', content: question, sources: '', created_at: LocalBackend.now()
    });
    const sources: string[] = LocalBackend.knowledgeSources(chat.class_course_id);
    const hit: boolean = LocalBackend.knowledgeHit(question, contextNote);
    const warning: string = hit ? '' : KB_WARNING;
    const turns: LocalAgentTurn[] = [];
    if (mode === 'mas') {
      for (const agent of AGENTS) {
        const content: string = LocalBackend.agentReply(agent.id, question, hit, contextNote);
        turns.push({ agent: agent, role: `assistant:${agent.id}`, content: content });
        LocalBackend.data.chatMessages.push({
          id: LocalBackend.nextChatMessageId(), chat_session_id: chatSessionId,
          role: `assistant:${agent.id}`, content: content,
          sources: JSON.stringify(sources), created_at: LocalBackend.now()
        });
      }
    } else {
      const content: string = LocalBackend.singleReply(question, hit, contextNote);
      turns.push({ agent: null, role: 'assistant', content: content });
      LocalBackend.data.chatMessages.push({
        id: LocalBackend.nextChatMessageId(), chat_session_id: chatSessionId,
        role: 'assistant', content: warning === '' ? content : `${warning}\n\n${content}`,
        sources: JSON.stringify(sources), created_at: LocalBackend.now()
      });
    }
    LocalBackend.data.questionLogs.push({
      id: LocalBackend.nextQuestionLogId(), class_course_id: chat.class_course_id,
      user_id: chat.user_id, chat_session_id: chatSessionId, question: question,
      keywords: LocalBackend.keywords(question), kb_missed: !hit, created_at: LocalBackend.now()
    });
    LocalBackend.persist();
    return { sources: sources, warning: warning, turns: turns };
  }

  static agents(): AiAgentInfo[] {
    return AGENTS;
  }

  private static seedData(): LocalData {
    const now: string = LocalBackend.now();
    const users: UserInfo[] = [
      { id: 1, name: '王老师', role: 'teacher' },
      { id: 2, name: '小明', role: 'student' },
      { id: 3, name: '小红', role: 'student' }
    ];
    const courses: ClassCourse[] = [
      {
        id: 1, name: '数据结构', class_name: '计科2301', teacher_id: 1,
        invite_code: '888888', created_at: now, teacher_name: '王老师'
      }
    ];
    const sessions: CourseSession[] = [
      {
        id: 1, class_course_id: 1, title: '第5讲 二叉树', creator_id: 1,
        status: 'done', created_at: now, outline_kind: 'official', outline_status: 'published'
      }
    ];
    const transcripts: TranscriptSegment[] = [
      { id: 1, session_id: 1, seq: 0, start_ms: 0, end_ms: 60000, text: '二叉树是每个节点最多有两个子节点的树形结构。' },
      { id: 2, session_id: 1, seq: 1, start_ms: 60000, end_ms: 120000, text: '二叉树遍历包括前序、中序和后序遍历。' },
      { id: 3, session_id: 1, seq: 2, start_ms: 120000, end_ms: 180000, text: '中序遍历顺序是左子树、根节点、右子树。' },
      { id: 4, session_id: 1, seq: 3, start_ms: 180000, end_ms: 240000, text: '二叉搜索树进行中序遍历可以得到有序序列。' },
      { id: 5, session_id: 1, seq: 4, start_ms: 240000, end_ms: 300000, text: '递归与非递归遍历实现都是本章重点。' }
    ];
    const outlines: Outline[] = [
      {
        id: 1, session_id: 1, class_course_id: 1, owner_id: -1,
        markdown: '# 二叉树\n\n## 基本概念\n- 每个节点最多有两个子节点\n- 分为左子树与右子树\n\n## 遍历\n- 前序：根、左、右\n- 中序：左、根、右\n- 后序：左、右、根\n\n> 重点：递归与非递归实现',
        status: 'published', updated_at: now, session_title: '第5讲 二叉树'
      }
    ];
    const notes: Note[] = [
      {
        id: 1, class_course_id: 1, owner_id: 2, title: '二叉树遍历笔记', kind: 'md',
        content: '# 二叉树遍历\n- 前序：根左右\n- 中序：左根右\n- 后序：左右根',
        visibility: 'private', quality_status: 'none', quality_score: null, updated_at: now
      }
    ];
    return {
      version: 1,
      users: users,
      courses: courses,
      memberships: [
        { id: 1, user_id: 1, class_course_id: 1 },
        { id: 2, user_id: 2, class_course_id: 1 },
        { id: 3, user_id: 3, class_course_id: 1 }
      ],
      sessions: sessions,
      transcripts: transcripts,
      outlines: outlines,
      notes: notes,
      chatSessions: [],
      chatMessages: [],
      questionLogs: []
    };
  }

  private static practice(input: GeneratePracticeBody): LocalPracticeResponse {
    const bank: LocalPracticeQuestion[] = LocalBackend.questionBank();
    const knowledgeSources: string[] = LocalBackend.knowledgeSources(input.class_course_id);
    const requestedTopic: string = LocalBackend.practiceTopic(input.topic, input.requirements);
    const requestedDifficulty: string = LocalBackend.practiceDifficulty(input.difficulty, input.requirements);
    const filtered: LocalPracticeQuestion[] = [];
    for (const question of bank) {
      const topicOk: boolean = requestedTopic === '综合' || question.topic === requestedTopic;
      const difficultyOk: boolean = requestedDifficulty === '综合' ||
        question.difficulty === requestedDifficulty;
      if (topicOk && difficultyOk) {
        filtered.push(question);
      }
    }
    const source: LocalPracticeQuestion[] = filtered.length > 0 ? filtered : bank;
    const result: LocalPracticeQuestion[] = [];
    const count: number = Math.max(1, Math.min(10, input.count));
    for (let i = 0; i < count; i++) {
      const base: LocalPracticeQuestion = source[i % source.length];
      const sourceName: string = knowledgeSources[i % knowledgeSources.length];
      result.push({
        id: i + 1,
        type: base.type,
        difficulty: requestedDifficulty === '综合' ? base.difficulty : requestedDifficulty,
        topic: requestedTopic === '综合' ? base.topic : requestedTopic,
        stem: LocalBackend.practiceStem(base.stem, input.mode, input.requirements,
          i >= source.length ? i + 1 : 0),
        options: base.options.slice(),
        answer: base.answer,
        explanation: LocalBackend.practiceExplanation(base.explanation, input.requirements),
        source: sourceName
      });
    }
    return { questions: result, knowledge_sources: knowledgeSources };
  }

  private static practiceTopic(topic: string, requirements: string): string {
    if (topic !== '综合') {
      return topic;
    }
    const supported: string[] = ['二叉树', '图', '排序'];
    for (const candidate of supported) {
      if (requirements.indexOf(candidate) >= 0) {
        return candidate;
      }
    }
    return topic;
  }

  private static practiceDifficulty(difficulty: string, requirements: string): string {
    if (difficulty !== '综合') {
      return difficulty;
    }
    if (requirements.indexOf('简单') >= 0 || requirements.indexOf('基础') >= 0) {
      return '基础';
    }
    if (requirements.indexOf('困难') >= 0 || requirements.indexOf('进阶') >= 0) {
      return '进阶';
    }
    if (requirements.indexOf('适中') >= 0 || requirements.indexOf('中等') >= 0) {
      return '适中';
    }
    return difficulty;
  }

  private static practiceStem(stem: string, mode: string, requirements: string,
    variant: number): string {
    let prefix: string = '';
    if (mode === '错题强化') {
      prefix = '易错辨析：';
    } else if (mode === '章节巩固') {
      prefix = '章节巩固：';
    }
    const variantText: string = variant > 0 ? `（变式 ${variant}）` : '';
    if (requirements.trim() === '') {
      return `${prefix}${stem}${variantText}`;
    }
    const compact: string = requirements.trim().substring(0, 36);
    return `${prefix}${stem}${variantText}\n要求侧重：${compact}`;
  }

  private static practiceExplanation(explanation: string, requirements: string): string {
    if (requirements.trim() === '') {
      return explanation;
    }
    return `${explanation}\n本题已结合你的出题要求生成。`;
  }

  private static questionBank(): LocalPracticeQuestion[] {
    return [
      {
        id: 1, type: '单选题', difficulty: '基础', topic: '二叉树',
        stem: '二叉树中序遍历的正确访问顺序是？',
        options: ['根、左、右', '左、根、右', '左、右、根', '按层访问'], answer: 1,
        explanation: '中序遍历依次访问左子树、根节点和右子树。', source: '提纲：第5讲 二叉树'
      },
      {
        id: 2, type: '单选题', difficulty: '适中', topic: '二叉树',
        stem: '二叉搜索树进行中序遍历通常得到什么结果？',
        options: ['层次序列', '随机序列', '关键字有序序列', '树高序列'], answer: 2,
        explanation: '二叉搜索树满足左小右大，因此中序遍历会产生有序序列。', source: '提纲：第5讲 二叉树'
      },
      {
        id: 3, type: '单选题', difficulty: '进阶', topic: '二叉树',
        stem: '后序遍历最适合下列哪一种操作？',
        options: ['复制树结构', '释放树中节点', '按层打印', '查找根节点'], answer: 1,
        explanation: '后序遍历先处理子树再处理根节点，适合安全释放整棵树。', source: '提纲：第5讲 二叉树'
      },
      {
        id: 4, type: '单选题', difficulty: '基础', topic: '图',
        stem: '无权图求单源最短路径通常优先采用哪种遍历？',
        options: ['深度优先搜索', '广度优先搜索', '拓扑排序', '关键路径'], answer: 1,
        explanation: '广度优先搜索按边数逐层扩展，首次到达时即得到最短路径。', source: '课程内置知识库'
      },
      {
        id: 5, type: '单选题', difficulty: '适中', topic: '排序',
        stem: '最坏情况下仍为 O(n log n) 的排序算法是？',
        options: ['快速排序', '冒泡排序', '归并排序', '插入排序'], answer: 2,
        explanation: '归并排序在最好、平均和最坏情况下均为 O(n log n)。', source: '课程内置知识库'
      }
    ];
  }

  private static analytics(query: QueryMap): string {
    const courseId: number = LocalBackend.queryNumber(query, 'class_course_id');
    const userId: number = LocalBackend.queryNumber(query, 'user_id');
    const course: ClassCourse = LocalBackend.requireCourse(courseId);
    if (course.teacher_id !== userId) {
      throw new Error('仅课程教师可查看课堂洞察');
    }
    const counts: Map<string, number> = new Map<string, number>();
    const missed: Map<string, number> = new Map<string, number>();
    const examples: Map<string, string[]> = new Map<string, string[]>();
    let totalMissed: number = 0;
    let total: number = 0;
    for (const log of LocalBackend.data.questionLogs) {
      if (log.class_course_id !== courseId) {
        continue;
      }
      total++;
      if (log.kb_missed) {
        totalMissed++;
      }
      for (const keyword of log.keywords) {
        counts.set(keyword, (counts.get(keyword) ?? 0) + 1);
        if (log.kb_missed) {
          missed.set(keyword, (missed.get(keyword) ?? 0) + 1);
        }
        const list: string[] = examples.get(keyword) ?? [];
        if (list.length < 3 && list.indexOf(log.question) < 0) {
          list.push(log.question);
          examples.set(keyword, list);
        }
      }
    }
    const keys: string[] = [];
    counts.forEach((value: number, key: string): void => {
      keys.push(key);
    });
    keys.sort((a: string, b: string): number => (counts.get(b) ?? 0) - (counts.get(a) ?? 0));
    const maxCount: number = keys.length === 0 ? 0 : (counts.get(keys[0]) ?? 0);
    const insights: KeywordInsight[] = [];
    for (let i = 0; i < keys.length && i < 8; i++) {
      const key: string = keys[i];
      const count: number = counts.get(key) ?? 0;
      const missedCount: number = missed.get(key) ?? 0;
      const heat: number = maxCount === 0 ? 0 : Math.max(8, Math.round(count * 100 / maxCount));
      insights.push({
        keyword: key, count: count, examples: examples.get(key) ?? [], missed_count: missedCount,
        heat: heat, level: heat >= 75 || missedCount >= 3 ? '高' : (heat >= 40 || missedCount >= 1 ? '中' : '低')
      });
    }
    return JSON.stringify({
      class_course_id: courseId, updated_at: LocalBackend.now(), total_questions: total,
      missed_count: totalMissed, top_keywords: insights, hot_zones: insights.slice(0, 6)
    });
  }

  private static knowledgeSources(courseId: number): string[] {
    const result: string[] = [];
    for (const outline of LocalBackend.data.outlines) {
      if (outline.class_course_id === courseId && outline.status === 'published') {
        const session: CourseSession | null = LocalBackend.findSession(outline.session_id);
        const source: string = session === null ? '课程提纲' : `提纲：${session.title}`;
        if (result.indexOf(source) < 0) {
          result.push(source);
        }
      }
    }
    for (const note of LocalBackend.data.notes) {
      if (note.class_course_id === courseId && note.visibility === 'shared') {
        result.push(`共享笔记：${note.title}`);
      }
    }
    return result.length > 0 ? result : ['课程内置知识库'];
  }

  private static knowledgeHit(question: string, contextNote: string): boolean {
    const combined: string = `${question}\n${contextNote}`;
    const known: string[] = ['二叉树', '遍历', '前序', '中序', '后序', '数据结构', '递归', '排序', '图'];
    for (const keyword of known) {
      if (combined.indexOf(keyword) >= 0) {
        return true;
      }
    }
    return contextNote.trim() !== '';
  }

  private static singleReply(question: string, hit: boolean, contextNote: string): string {
    if (question.indexOf('中序') >= 0 || question.indexOf('遍历') >= 0) {
      return '中序遍历的顺序是左子树、根节点、右子树。对二叉搜索树执行中序遍历，可以得到关键字有序序列。建议手动画一棵小树，再分别写出前序、中序和后序序列进行对比。';
    }
    if (question.indexOf('二叉树') >= 0) {
      return '二叉树是每个节点最多有两个子节点的树形结构，两个子节点分别称为左子节点和右子节点。学习时应重点掌握三种深度优先遍历，以及递归和非递归实现。';
    }
    if (contextNote.trim() !== '') {
      return `结合你携带的笔记，可以先提取定义、条件和结论，再用一个反例检查边界。当前问题是“${question}”，建议把笔记中的相关段落整理成三点后再作答。`;
    }
    if (!hit) {
      return `当前离线知识库没有直接命中“${question}”。可以先把问题拆成定义、适用条件、典型操作和复杂度四部分，再回到课程资料核对。`;
    }
    return '根据当前课程知识库，建议先明确概念定义和使用条件，再通过一个具体例子验证操作过程，最后总结时间复杂度与常见易错点。';
  }

  private static agentReply(agentId: string, question: string, hit: boolean, contextNote: string): string {
    if (agentId === 'analyst') {
      return `先把条件理清楚。针对“${question}”，需要区分结构定义、操作顺序和适用前提。以二叉树为例，中序遍历固定为左、根、右，但得到有序序列还要求它是二叉搜索树。`;
    }
    if (agentId === 'skeptic') {
      return '换个条件还成立吗？不要把“二叉树中序遍历”和“结果一定有序”直接画等号。普通二叉树没有关键字大小约束，只有二叉搜索树才保证中序结果有序。';
    }
    if (agentId === 'connector') {
      return '可以把遍历想成整理书架：先整理左边区域，再处理当前书格，最后整理右边区域。这个类比对应中序遍历，也能直接映射到递归调用顺序。';
    }
    const noteHint: string = contextNote.trim() === '' ? '' : '同时可以把当前笔记中的定义补充到结论旁边。';
    return `我们把观点收一下：先确认对象类型，再套用遍历规则，最后检查结论是否依赖额外条件。${noteHint}下一步建议画一棵普通二叉树和一棵二叉搜索树分别验证。`;
  }

  private static keywords(question: string): string[] {
    const candidates: string[] = ['二叉树', '遍历', '中序', '前序', '后序', '递归', '排序', '图', '复杂度'];
    const result: string[] = [];
    for (const item of candidates) {
      if (question.indexOf(item) >= 0) {
        result.push(item);
      }
    }
    if (result.length === 0) {
      result.push('其他问题');
    }
    return result;
  }

  private static generateOutlineText(title: string, transcript: string): string {
    return `# ${title}\n\n## 课堂主题\n- 数据结构核心概念与使用场景\n- 操作条件与复杂度分析\n\n## 课堂转写摘要\n${transcript.trim()}\n\n## 复习建议\n- 对照示例梳理操作步骤\n- 记录边界条件和易错点\n- 通过选择题检查理解`; 
  }

  private static officialLessonCount(courseId: number): number {
    const ids: number[] = [];
    for (const outline of LocalBackend.data.outlines) {
      if (outline.class_course_id === courseId && outline.owner_id === -1 &&
        outline.status === 'published' && ids.indexOf(outline.session_id) < 0) {
        ids.push(outline.session_id);
      }
    }
    return ids.length;
  }

  private static personalNoteCount(courseId: number, userId: number): number {
    let count: number = 0;
    for (const note of LocalBackend.data.notes) {
      if (note.class_course_id === courseId && note.owner_id === userId) {
        count++;
      }
    }
    return count;
  }

  private static classNoteCount(courseId: number): number {
    let count: number = 0;
    for (const note of LocalBackend.data.notes) {
      if (note.class_course_id === courseId && note.visibility === 'shared') {
        count++;
      }
    }
    return count;
  }

  private static canViewSession(session: CourseSession, userId: number): boolean {
    return session.creator_id === userId || LocalBackend.findOutline(session.id, -1, true) !== null;
  }

  private static sessionWithOutlineMeta(session: CourseSession, userId: number): CourseSession {
    const result: CourseSession = {
      id: session.id, class_course_id: session.class_course_id, title: session.title,
      creator_id: session.creator_id, status: session.status, created_at: session.created_at,
      outline_kind: '', outline_status: ''
    };
    const official: Outline | null = LocalBackend.findOutline(session.id, -1, true);
    const personal: Outline | null = LocalBackend.findOutline(session.id, userId, false);
    if (official !== null) {
      result.outline_kind = 'official';
      result.outline_status = official.status;
    } else if (personal !== null && personal.status !== 'generated') {
      result.outline_kind = 'personal';
      result.outline_status = personal.status;
    } else if (LocalBackend.isTeacher(userId)) {
      const draft: Outline | null = LocalBackend.findOutline(session.id, -1, false);
      if (draft !== null) {
        result.outline_kind = 'official';
        result.outline_status = draft.status;
      }
    } else if (session.creator_id === userId) {
      result.outline_kind = 'self';
      result.outline_status = session.status;
    }
    return result;
  }

  private static visibleOutline(sessionId: number, userId: number): Outline | null {
    if (userId < 0 || LocalBackend.isTeacher(userId)) {
      return LocalBackend.findOutline(sessionId, -1, false);
    }
    const personal: Outline | null = LocalBackend.findOutline(sessionId, userId, false);
    if (personal !== null && personal.status !== 'generated') {
      return personal;
    }
    return LocalBackend.findOutline(sessionId, -1, true);
  }

  private static findOutline(sessionId: number, ownerId: number, publishedOnly: boolean): Outline | null {
    for (const outline of LocalBackend.data.outlines) {
      if (outline.session_id === sessionId && outline.owner_id === ownerId &&
        (!publishedOnly || outline.status === 'published')) {
        return outline;
      }
    }
    return null;
  }

  private static copyOutline(outline: Outline): Outline {
    return {
      id: outline.id, session_id: outline.session_id, class_course_id: outline.class_course_id,
      owner_id: outline.owner_id, markdown: outline.markdown, status: outline.status,
      updated_at: outline.updated_at, session_title: outline.session_title
    };
  }

  private static courseWithTeacher(course: ClassCourse): ClassCourse {
    return {
      id: course.id, name: course.name, class_name: course.class_name,
      teacher_id: course.teacher_id, invite_code: course.invite_code,
      created_at: course.created_at, teacher_name: LocalBackend.userName(course.teacher_id)
    };
  }

  private static parsePath(path: string): ParsedPath {
    const index: number = path.indexOf('?');
    const pathname: string = index < 0 ? path : path.substring(0, index);
    const query: QueryMap = {};
    if (index >= 0 && index + 1 < path.length) {
      const pairs: string[] = path.substring(index + 1).split('&');
      for (const pair of pairs) {
        const equalIndex: number = pair.indexOf('=');
        const key: string = decodeURIComponent(equalIndex < 0 ? pair : pair.substring(0, equalIndex));
        const value: string = decodeURIComponent(equalIndex < 0 ? '' : pair.substring(equalIndex + 1));
        if (key === 'user_id') {
          query.user_id = value;
        } else if (key === 'class_course_id') {
          query.class_course_id = value;
        }
      }
    }
    return { pathname: pathname, query: query };
  }

  private static queryNumber(query: QueryMap, key: string, fallback: number = 0): number {
    let raw: string | undefined = undefined;
    if (key === 'user_id') {
      raw = query.user_id;
    } else if (key === 'class_course_id') {
      raw = query.class_course_id;
    }
    if (raw === undefined || raw === '') {
      return fallback;
    }
    const value: number = Number(raw);
    return Number.isFinite(value) ? value : fallback;
  }

  private static body<T>(body: object | undefined): T {
    if (body === undefined) {
      throw new Error('请求体不能为空');
    }
    return JSON.parse(JSON.stringify(body)) as T;
  }

  private static requireMembership(courseId: number, userId: number): void {
    LocalBackend.requireCourse(courseId);
    if (!LocalBackend.hasMembership(courseId, userId)) {
      throw new Error('尚未加入该课程');
    }
  }

  private static hasMembership(courseId: number, userId: number): boolean {
    for (const item of LocalBackend.data.memberships) {
      if (item.class_course_id === courseId && item.user_id === userId) {
        return true;
      }
    }
    return false;
  }

  private static requireCourse(id: number): ClassCourse {
    for (const item of LocalBackend.data.courses) {
      if (item.id === id) {
        return item;
      }
    }
    throw new Error('课程不存在');
  }

  private static findSession(id: number): CourseSession | null {
    for (const item of LocalBackend.data.sessions) {
      if (item.id === id) {
        return item;
      }
    }
    return null;
  }

  private static requireSession(id: number): CourseSession {
    const item: CourseSession | null = LocalBackend.findSession(id);
    if (item === null) {
      throw new Error('课时不存在');
    }
    return item;
  }

  private static requireNote(id: number): Note {
    for (const item of LocalBackend.data.notes) {
      if (item.id === id) {
        return item;
      }
    }
    throw new Error('笔记不存在');
  }

  private static requireChatSession(id: number): ChatSessionInfo {
    for (const item of LocalBackend.data.chatSessions) {
      if (item.id === id) {
        return item;
      }
    }
    throw new Error('会话不存在');
  }

  private static isTeacher(userId: number): boolean {
    for (const user of LocalBackend.data.users) {
      if (user.id === userId) {
        return user.role === 'teacher';
      }
    }
    return false;
  }

  private static userName(userId: number): string {
    for (const user of LocalBackend.data.users) {
      if (user.id === userId) {
        return user.name;
      }
    }
    return '';
  }

  private static inviteCode(): string {
    let code: string = '';
    do {
      code = `${Math.floor(100000 + Math.random() * 900000)}`;
    } while (LocalBackend.data.courses.some((course: ClassCourse): boolean => course.invite_code === code));
    return code;
  }

  private static ensureReady(): void {
    if (!LocalBackend.ready) {
      throw new Error('本地后端尚未启动');
    }
  }

  private static persist(): void {
    if (LocalBackend.dataPath === '') {
      return;
    }
    const file: fileIo.File = fileIo.openSync(
      LocalBackend.dataPath,
      fileIo.OpenMode.CREATE | fileIo.OpenMode.WRITE_ONLY | fileIo.OpenMode.TRUNC);
    try {
      fileIo.writeSync(file.fd, JSON.stringify(LocalBackend.data));
    } finally {
      fileIo.closeSync(file);
    }
  }

  private static now(): string {
    return new Date().toISOString();
  }

  private static maxId(values: number[]): number {
    let result: number = 0;
    for (const value of values) {
      if (value > result) {
        result = value;
      }
    }
    return result;
  }

  private static nextCourseId(): number {
    return LocalBackend.maxId(LocalBackend.data.courses.map((item: ClassCourse): number => item.id)) + 1;
  }

  private static nextMembershipId(): number {
    return LocalBackend.maxId(LocalBackend.data.memberships.map((item: LocalMembership): number => item.id)) + 1;
  }

  private static nextSessionId(): number {
    return LocalBackend.maxId(LocalBackend.data.sessions.map((item: CourseSession): number => item.id)) + 1;
  }

  private static nextTranscriptId(): number {
    return LocalBackend.maxId(LocalBackend.data.transcripts.map((item: TranscriptSegment): number => item.id)) + 1;
  }

  private static nextOutlineId(): number {
    return LocalBackend.maxId(LocalBackend.data.outlines.map((item: Outline): number => item.id)) + 1;
  }

  private static nextNoteId(): number {
    return LocalBackend.maxId(LocalBackend.data.notes.map((item: Note): number => item.id)) + 1;
  }

  private static nextChatSessionId(): number {
    return LocalBackend.maxId(LocalBackend.data.chatSessions.map((item: ChatSessionInfo): number => item.id)) + 1;
  }

  private static nextChatMessageId(): number {
    return LocalBackend.maxId(LocalBackend.data.chatMessages.map((item: ChatMessageInfo): number => item.id)) + 1;
  }

  private static nextQuestionLogId(): number {
    return LocalBackend.maxId(LocalBackend.data.questionLogs.map((item: LocalQuestionLog): number => item.id)) + 1;
  }
}
