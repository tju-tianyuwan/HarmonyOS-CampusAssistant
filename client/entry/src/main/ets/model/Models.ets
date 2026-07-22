/**
 * 数据模型：与服务端 JSON 字段一一对应（snake_case）。
 */
export interface UserInfo {
  id: number;
  name: string;
  role: string; // teacher | student
}

export interface ClassCourse {
  id: number;
  name: string;
  class_name: string;
  teacher_id: number;
  invite_code: string;
  created_at: string;
  teacher_name?: string;
}

export interface CourseSession {
  id: number;
  class_course_id: number;
  title: string;
  creator_id: number;
  status: string; // recording | transcribing | done
  created_at: string;
  outline_kind?: string; // official | personal | self | ''
  outline_status?: string;
}

export interface TranscriptSegment {
  id: number;
  session_id: number;
  seq: number;
  start_ms: number;
  end_ms: number;
  text: string;
}

export interface Outline {
  id: number;
  session_id: number;
  class_course_id: number;
  owner_id: number;
  markdown: string;
  status: string; // generated | draft | pending | published | rejected
  updated_at: string;
  session_title?: string;
}

export interface Note {
  id: number;
  class_course_id: number;
  owner_id: number;
  title: string;
  kind: string; // md | handwriting
  content: string;
  visibility: string; // private | shared
  quality_status: string; // none | evaluating | accepted | rejected
  quality_score: number | null;
  updated_at: string;
}

export interface ChatSessionInfo {
  id: number;
  class_course_id: number;
  user_id: number;
  title: string;
  created_at: string;
}

export interface ChatMessageInfo {
  id: number;
  chat_session_id: number;
  role: string; // user | assistant
  content: string;
  sources: string; // JSON 数组字符串
  created_at: string;
}

/** 手写笔迹：矢量存储，p=压力(0~1)，预留倾角/速度字段升级笔锋 */
export interface StrokePoint {
  x: number;
  y: number;
  p: number;
}

export interface Stroke {
  points: StrokePoint[];
  width: number;
  color: string;
  eraser: boolean;
}

export interface HandwritingDoc {
  strokes: Stroke[];
}

/** 问答界面的本地消息模型（含流式中间态） */
export const KB_FALLBACK_WARNING: string =
  '知识库中暂时未包含该知识点，以下内容可能有误，请结合课程资料核对。';

export interface UiChatMessage {
  role: string;
  content: string;
  sources: string[];
  warning: string;
  streaming: boolean;
}

export interface KeywordInsight {
  keyword: string;
  count: number;
  examples: string[];
  missed_count: number;
  heat: number;
  level: string;
}

export interface ClassroomAnalytics {
  class_course_id: number;
  updated_at: string;
  total_questions: number;
  missed_count: number;
  top_keywords: KeywordInsight[];
  hot_zones: KeywordInsight[];
}
