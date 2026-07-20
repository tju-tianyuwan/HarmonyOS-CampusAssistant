from datetime import datetime

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from pydantic import BaseModel
from sqlmodel import Session, select

from ..db import get_db
from ..models import ClassCourse, CourseSession, Outline, TranscriptSegment, User
from ..services import rag
from ..services.asr import get_asr_provider
from ..services.llm import chat

router = APIRouter(prefix="/sessions", tags=["sessions"])

OUTLINE_SYSTEM = (
    "你是课堂笔记助手。请将课堂转写文本整理为结构化 Markdown 提纲："
    "分章节列出知识点，标注例题与考试重点。只输出 Markdown，不要额外说明。"
)


class CreateSession(BaseModel):
    class_course_id: int
    title: str
    creator_id: int


@router.get("")
def list_sessions(class_course_id: int, user_id: int | None = None, db: Session = Depends(get_db)):
    sessions = db.exec(
        select(CourseSession)
        .where(CourseSession.class_course_id == class_course_id)
        .order_by(CourseSession.created_at.desc())
    ).all()
    if user_id is None:
        return sessions

    result = []
    for s in sessions:
        if _can_view_session(db, s, user_id):
            result.append(_session_with_outline_meta(db, s, user_id))
    return result


def _session_with_outline_meta(db: Session, s: CourseSession, user_id: int):
    user = db.get(User, user_id)
    official_published = _get_official_outline(db, s.id, published_only=True)
    official = _get_official_outline(db, s.id, published_only=False)
    personal = _get_user_outline(db, s.id, user_id, saved_only=True)
    data = s.model_dump()
    if official_published:
        data["outline_kind"] = "official"
        data["outline_status"] = official_published.status
    elif personal:
        data["outline_kind"] = "personal"
        data["outline_status"] = personal.status
    elif official and user and user.role == "teacher":
        data["outline_kind"] = "official"
        data["outline_status"] = official.status
    elif s.creator_id == user_id:
        data["outline_kind"] = "self"
        data["outline_status"] = s.status
    else:
        data["outline_kind"] = ""
        data["outline_status"] = ""
    return data


def _can_view_session(db: Session, s: CourseSession, user_id: int) -> bool:
    if s.creator_id == user_id:
        return True
    official = _get_official_outline(db, s.id, published_only=True)
    return official is not None


def _get_official_outline(db: Session, session_id: int, published_only: bool):
    if published_only:
        outline = db.exec(
            select(Outline).where(
                Outline.session_id == session_id,
                Outline.owner_id == -1,
                Outline.status == "published",
            )
        ).first()
        if outline:
            return outline
        return db.exec(
            select(Outline).where(Outline.session_id == session_id, Outline.status == "published")
        ).first()
    return db.exec(
        select(Outline).where(Outline.session_id == session_id, Outline.owner_id == -1)
    ).first()


def _get_user_outline(db: Session, session_id: int, user_id: int, saved_only: bool):
    stmt = select(Outline).where(Outline.session_id == session_id, Outline.owner_id == user_id)
    if saved_only:
        stmt = stmt.where(Outline.status != "generated")
    return db.exec(stmt).first()


def _outline_owner_for_user(db: Session, session: CourseSession, user_id: int) -> int:
    user = db.get(User, user_id)
    if user and user.role == "teacher":
        return -1
    return user_id


@router.post("")
def create_session(body: CreateSession, db: Session = Depends(get_db)):
    s = CourseSession(**body.model_dump())
    db.add(s)
    db.commit()
    db.refresh(s)
    return s


@router.post("/{session_id}/chunks/{seq}")
async def upload_chunk(session_id: int, seq: int, file: UploadFile = File(...), db: Session = Depends(get_db)):
    """上传音频分片 → 云端 ASR（当前 Mock）→ 返回并保存转写分段"""
    s = db.get(CourseSession, session_id)
    if not s:
        raise HTTPException(404, "课时不存在")
    audio = await file.read()
    result = await get_asr_provider().transcribe_chunk(audio, seq)
    old = db.exec(
        select(TranscriptSegment).where(TranscriptSegment.session_id == session_id, TranscriptSegment.seq == seq)
    ).first()
    if old:
        db.delete(old)
    seg = TranscriptSegment(session_id=session_id, seq=seq, start_ms=result.start_ms, end_ms=result.end_ms, text=result.text)
    s.status = "transcribing"
    db.add(seg)
    db.commit()
    db.refresh(seg)
    return seg


@router.post("/{session_id}/finish")
def finish_session(session_id: int, db: Session = Depends(get_db)):
    s = db.get(CourseSession, session_id)
    if not s:
        raise HTTPException(404, "课时不存在")
    s.status = "done"
    db.commit()
    db.refresh(s)
    return s


@router.get("/{session_id}/transcript")
def get_transcript(session_id: int, user_id: int | None = None, db: Session = Depends(get_db)):
    s = db.get(CourseSession, session_id)
    if not s:
        raise HTTPException(404, "课时不存在")
    if user_id is not None and not _can_view_session(db, s, user_id):
        raise HTTPException(403, "无权查看该课时")
    return db.exec(
        select(TranscriptSegment).where(TranscriptSegment.session_id == session_id).order_by(TranscriptSegment.seq)
    ).all()


@router.post("/{session_id}/outline/generate")
async def generate_outline(session_id: int, user_id: int = -1, db: Session = Depends(get_db)):
    s = db.get(CourseSession, session_id)
    if not s:
        raise HTTPException(404, "课时不存在")
    segs = db.exec(
        select(TranscriptSegment).where(TranscriptSegment.session_id == session_id).order_by(TranscriptSegment.seq)
    ).all()
    if not segs:
        raise HTTPException(400, "尚无转写文本")
    text = "\n".join(x.text for x in segs)
    md = await chat(OUTLINE_SYSTEM, text)
    owner_id = _outline_owner_for_user(db, s, user_id) if user_id >= 0 else -1
    outline = db.exec(
        select(Outline).where(Outline.session_id == session_id, Outline.owner_id == owner_id)
    ).first()
    if outline:
        outline.markdown = md
        outline.status = "generated"
        outline.updated_at = datetime.utcnow()
    else:
        outline = Outline(
            session_id=session_id, class_course_id=s.class_course_id,
            owner_id=owner_id, markdown=md, status="generated",
        )
        db.add(outline)
    db.commit()
    db.refresh(outline)
    return outline


@router.get("/{session_id}/outline")
def get_outline(session_id: int, user_id: int | None = None, db: Session = Depends(get_db)):
    if user_id is None:
        outline = _get_official_outline(db, session_id, published_only=False)
        if not outline:
            outline = db.exec(select(Outline).where(Outline.session_id == session_id)).first()
    else:
        user = db.get(User, user_id)
        if user and user.role == "teacher":
            outline = _get_official_outline(db, session_id, published_only=False)
        else:
            outline = _get_user_outline(db, session_id, user_id, saved_only=True)
            if not outline:
                outline = _get_official_outline(db, session_id, published_only=True)
    if not outline:
        raise HTTPException(404, "提纲不存在")
    return outline


class PublishBody(BaseModel):
    user_id: int
    action: str = "publish"  # publish | reject


class OutlineUpdate(BaseModel):
    markdown: str


@router.put("/{session_id}/outline")
def update_outline(session_id: int, body: OutlineUpdate, user_id: int = -1, db: Session = Depends(get_db)):
    """保存个人提纲或官方草稿；只有发布接口会写入知识库。"""
    s = db.get(CourseSession, session_id)
    if not s:
        raise HTTPException(404, "课时不存在")
    owner_id = _outline_owner_for_user(db, s, user_id) if user_id >= 0 else -1
    outline = db.exec(
        select(Outline).where(Outline.session_id == session_id, Outline.owner_id == owner_id)
    ).first()
    if not outline:
        outline = Outline(
            session_id=session_id, class_course_id=s.class_course_id,
            owner_id=owner_id, markdown=body.markdown, status="draft",
        )
        db.add(outline)
    else:
        outline.markdown = body.markdown
        outline.status = "draft"
    outline.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(outline)
    return outline


@router.post("/{session_id}/outline/review")
def review_outline(session_id: int, body: PublishBody, db: Session = Depends(get_db)):
    """教师审核：发布 → 写入该集合知识库；退回 → rejected"""
    outline = _get_official_outline(db, session_id, published_only=False)
    if not outline:
        raise HTTPException(404, "提纲不存在")
    user = db.get(User, body.user_id)
    cc = db.get(ClassCourse, outline.class_course_id)
    if not user or user.role != "teacher" or cc.teacher_id != user.id:
        raise HTTPException(403, "仅本课程教师可审核")
    if body.action == "publish":
        outline.status = "published"
        s = db.get(CourseSession, session_id)
        rag.add_document(outline.class_course_id, f"outline_{outline.id}", outline.markdown, source=f"提纲：{s.title}")
    else:
        outline.status = "rejected"
    outline.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(outline)
    return outline


@router.get("/outlines/pending")
def pending_outlines(class_course_id: int, db: Session = Depends(get_db)):
    """教师审核页：该集合所有草稿/待审提纲"""
    outlines = db.exec(
        select(Outline).where(
            Outline.class_course_id == class_course_id,
            Outline.owner_id == -1,
            Outline.status.in_(["draft", "pending"]),
        )
    ).all()
    result = []
    for o in outlines:
        s = db.get(CourseSession, o.session_id)
        result.append({**o.model_dump(), "session_title": s.title if s else ""})
    return result
