from datetime import date, datetime
from typing import Optional

from sqlmodel import Field, SQLModel


class User(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    name: str
    role: str = "student"  # teacher | student


class ClassCourse(SQLModel, table=True):
    """课程集合：班级+课程，知识库隔离的基本单位"""
    id: Optional[int] = Field(default=None, primary_key=True)
    name: str  # 课程名，如「数据结构」
    class_name: str  # 班级名，如「计科2301」
    teacher_id: int = Field(foreign_key="user.id")
    invite_code: str = Field(index=True)
    created_at: datetime = Field(default_factory=datetime.utcnow)


class Membership(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="user.id")
    class_course_id: int = Field(foreign_key="classcourse.id")


class TimetableSettings(SQLModel, table=True):
    user_id: int = Field(primary_key=True, foreign_key="user.id")
    semester_start: date


class TimetableEntry(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="user.id", index=True)
    class_course_id: int = Field(foreign_key="classcourse.id", index=True)
    weekday: int
    start_section: int
    end_section: int
    start_week: int = 1
    end_week: int = 20
    week_type: str = "all"
    location: str = ""


class CourseSchedule(SQLModel, table=True):
    """Teacher-owned recurring time slot, inherited through course membership."""
    id: Optional[int] = Field(default=None, primary_key=True)
    class_course_id: int = Field(foreign_key="classcourse.id", index=True)
    semester_start: date
    weekday: int
    start_section: int
    end_section: int
    start_week: int = 1
    end_week: int = 20
    week_type: str = "all"
    location: str = ""


class CourseSession(SQLModel, table=True):
    """一次课时"""
    id: Optional[int] = Field(default=None, primary_key=True)
    class_course_id: int = Field(foreign_key="classcourse.id", index=True)
    title: str
    ai_title: str = ""
    creator_id: int = Field(foreign_key="user.id")
    status: str = "recording"  # recording | transcribing | done
    created_at: datetime = Field(default_factory=datetime.utcnow)


class TranscriptSegment(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    session_id: int = Field(foreign_key="coursesession.id", index=True)
    seq: int  # 分片序号
    start_ms: int
    end_ms: int
    text: str


class Outline(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    session_id: int = Field(foreign_key="coursesession.id", index=True)
    class_course_id: int = Field(index=True)
    owner_id: int = Field(default=-1, index=True)  # -1 means official course outline
    markdown: str
    status: str = "draft"  # generated | draft | pending | published | rejected
    updated_at: datetime = Field(default_factory=datetime.utcnow)


class Note(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    class_course_id: int = Field(index=True)
    session_id: Optional[int] = Field(default=None, foreign_key="coursesession.id", index=True)
    owner_id: int = Field(foreign_key="user.id")
    title: str
    kind: str = "md"  # md | handwriting
    content: str = ""  # md 文本；手写笔记存矢量 JSON
    visibility: str = "private"  # private | shared
    quality_status: str = "none"  # none | evaluating | accepted | rejected
    quality_score: Optional[float] = None
    updated_at: datetime = Field(default_factory=datetime.utcnow)


class ChatSession(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    class_course_id: int = Field(index=True)
    user_id: int = Field(foreign_key="user.id")
    title: str = "新会话"
    created_at: datetime = Field(default_factory=datetime.utcnow)


class ChatMessage(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    chat_session_id: int = Field(foreign_key="chatsession.id", index=True)
    role: str  # user | assistant
    content: str
    sources: str = ""  # JSON 数组：引用来源片段
    created_at: datetime = Field(default_factory=datetime.utcnow)


class QuestionLog(SQLModel, table=True):
    """学生提问日志：用于教师端课堂疑问洞察，不参与 RAG 检索。"""
    id: Optional[int] = Field(default=None, primary_key=True)
    class_course_id: int = Field(index=True)
    user_id: int = Field(foreign_key="user.id", index=True)
    chat_session_id: int = Field(foreign_key="chatsession.id", index=True)
    question: str
    keywords: str = ""  # JSON 数组：本地规则 + LLM 归一化后的关键词
    kb_hit_count: int = 0
    kb_missed: bool = Field(default=False, index=True)
    created_at: datetime = Field(default_factory=datetime.utcnow)


class KeywordStat(SQLModel, table=True):
    """按课程聚合的关键词计数表。"""
    id: Optional[int] = Field(default=None, primary_key=True)
    class_course_id: int = Field(index=True)
    keyword: str = Field(index=True)
    count: int = 0
    last_seen_at: datetime = Field(default_factory=datetime.utcnow)


class Account(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    user_id: int = Field(foreign_key="user.id", unique=True)
    login_key: str = Field(unique=True, index=True)
    account_type: str
    password_hash: str
    email: str = ""
    school_name: str = ""
    student_number: str = ""
    verification_status: str = "pending"


class AuthSession(SQLModel, table=True):
    token_hash: str = Field(primary_key=True)
    user_id: int = Field(foreign_key="user.id", index=True)
    expires_at: datetime


class EmailCode(SQLModel, table=True):
    email: str = Field(primary_key=True)
    code_hash: str
    expires_at: datetime
    sent_at: datetime = Field(default_factory=datetime.utcnow)
    attempts: int = 0


class AuthRateLimit(SQLModel, table=True):
    key: str = Field(primary_key=True)
    count: int = 0
    expires_at: datetime


class AccountCode(SQLModel, table=True):
    key: str = Field(primary_key=True)
    user_id: int = Field(foreign_key="user.id", index=True)
    email: str
    purpose: str
    code_hash: str
    credential_version: str
    expires_at: datetime
    sent_at: datetime = Field(default_factory=datetime.utcnow)
    attempts: int = 0


class PersonalWorkspace(SQLModel, table=True):
    user_id: int = Field(primary_key=True, foreign_key="user.id")
    class_course_id: int = Field(foreign_key="classcourse.id", unique=True)


class KnowledgeDocument(SQLModel, table=True):
    id: str = Field(primary_key=True)
    class_course_id: int = Field(index=True)
    source: str
    content: str
    kind: str = "manual"
    version: str
    embedding_profile: str = ""
    updated_at: datetime = Field(default_factory=datetime.utcnow)


class SessionResource(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    session_id: int = Field(foreign_key="coursesession.id", index=True)
    class_course_id: int = Field(foreign_key="classcourse.id", index=True)
    uploader_id: int = Field(foreign_key="user.id")
    filename: str
    content: str
    created_at: datetime = Field(default_factory=datetime.utcnow)


class DocumentJob(SQLModel, table=True):
    id: str = Field(primary_key=True)
    class_course_id: int = Field(index=True)
    user_id: int = Field(index=True)
    filename: str
    status: str = Field(default="queued", index=True)
    progress: int = 0
    error: str = ""
    chunks: int = 0
    created_at: datetime = Field(default_factory=datetime.utcnow)
    updated_at: datetime = Field(default_factory=datetime.utcnow)


class MeetingRoom(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    class_course_id: int = Field(foreign_key="classcourse.id", index=True)
    creator_id: int = Field(foreign_key="user.id")
    name: str
    room_type: str = Field(default="ai_meeting", index=True)  # ai_meeting | group_chat
    agent_mode: str = "multi"  # multi | single
    participant_limit: int = 20
    enabled: bool = True
    status: str = "active"
    minutes: str = ""
    processed_message_id: int = 0
    buffer_seconds: int = 2
    last_activity: datetime = Field(default_factory=datetime.utcnow)
    idle_prompted: bool = False
    created_at: datetime = Field(default_factory=datetime.utcnow)


class MeetingMember(SQLModel, table=True):
    room_id: int = Field(primary_key=True, foreign_key="meetingroom.id")
    user_id: int = Field(primary_key=True, foreign_key="user.id")


class MeetingExclusion(SQLModel, table=True):
    room_id: int = Field(primary_key=True, foreign_key="meetingroom.id")
    user_id: int = Field(primary_key=True, foreign_key="user.id")


class MeetingMessage(SQLModel, table=True):
    id: Optional[int] = Field(default=None, primary_key=True)
    room_id: int = Field(foreign_key="meetingroom.id", index=True)
    sender_id: Optional[int] = Field(default=None, foreign_key="user.id")
    sender_name: str
    role: str = "user"
    content: str
    sources: str = "[]"
    created_at: datetime = Field(default_factory=datetime.utcnow)
