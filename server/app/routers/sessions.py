from datetime import datetime
from typing import Literal

from fastapi import APIRouter, Depends, File, HTTPException, Path, UploadFile
from pydantic import BaseModel, Field
from sqlmodel import Session, select
from starlette.concurrency import run_in_threadpool

from ..db import get_db, write_lock
from ..models import ClassCourse, CourseSession, Outline, TranscriptSegment, User
from ..services import rag
from ..services.asr import ASRError, get_asr_provider
from ..services.asr.local import LocalASRProvider
from ..services.llm import chat
from ..services.security import current_user, is_manager, manager, member, same_user

router = APIRouter(prefix="/sessions", tags=["sessions"])
OUTLINE_SYSTEM = "你是课堂笔记助手。将转写整理为结构化 Markdown 提纲，保留概念、例题和考试重点，不编造。"


def session_access(db: Session, user: User, session_id: int, edit: bool = False) -> CourseSession:
    session = db.get(CourseSession, session_id)
    if not session:
        raise HTTPException(404, "课时不存在")
    course = member(db, user, session.class_course_id)
    if session.creator_id != user.id and not is_manager(db, user, course):
        published = find_outline(db, session_id, -1)
        personal = find_outline(db, session_id, user.id)
        if edit or ((not published or published.status != "published") and not personal):
            raise HTTPException(403, "无权操作该课时")
    return session


def find_outline(db: Session, session_id: int, owner_id: int):
    return db.exec(select(Outline).where(Outline.session_id == session_id, Outline.owner_id == owner_id)).first()


def outline_owner(db: Session, user: User, course_id: int) -> int:
    return -1 if is_manager(db, user, member(db, user, course_id)) else user.id


def snapshot(outline):
    return outline.model_dump() if outline else None


class CreateSession(BaseModel):
    class_course_id: int
    title: str = Field(min_length=1, max_length=200)
    creator_id: int


@router.get("")
def list_sessions(class_course_id: int, user_id: int | None = None, db: Session = Depends(get_db),
                  user: User = Depends(current_user)):
    same_user(user, user_id)
    course = member(db, user, class_course_id)
    result = []
    for session in db.exec(select(CourseSession).where(CourseSession.class_course_id == class_course_id)
                           .order_by(CourseSession.created_at.desc())).all():
        official, personal = find_outline(db, session.id, -1), find_outline(db, session.id, user.id)
        manages = is_manager(db, user, course)
        published = official is not None and official.status == "published"
        if session.creator_id != user.id and not manages and not published and not personal:
            continue
        kind = "official" if published or (official and manages) else "personal" if personal else "self"
        selected = official if kind == "official" else personal
        result.append({**session.model_dump(), "outline_kind": kind,
                       "outline_status": selected.status if selected else session.status})
    return result


@router.post("")
def create_session(body: CreateSession, db: Session = Depends(get_db), user: User = Depends(current_user)):
    same_user(user, body.creator_id)
    member(db, user, body.class_course_id)
    session = CourseSession(**body.model_dump())
    db.add(session)
    db.commit()
    db.refresh(session)
    return session


@router.post("/{session_id}/chunks/{seq}")
async def upload_chunk(session_id: int, seq: int = Path(ge=0), file: UploadFile = File(...),
                       db: Session = Depends(get_db), user: User = Depends(current_user)):
    session = session_access(db, user, session_id, edit=True)
    def existing():
        return db.exec(select(TranscriptSegment).where(TranscriptSegment.session_id == session_id,
                                                       TranscriptSegment.seq == seq)).first()
    old = existing()
    if old:
        return old
    if session.status == "done":
        raise HTTPException(409, "课时已结束")
    audio = await file.read(3 * 1024 * 1024 + 1)
    if len(audio) > 3 * 1024 * 1024:
        raise HTTPException(413, "分片不能超过 3 MiB")
    if not audio:
        raise HTTPException(400, "音频不能为空")
    try:
        provider = get_asr_provider()
        if isinstance(provider, LocalASRProvider):
            course = db.get(ClassCourse, session.class_course_id)
            outlines = db.exec(select(Outline).where(Outline.class_course_id == session.class_course_id,
                               Outline.owner_id == -1, Outline.status == "published").limit(5)).all()
            terms = "\n".join(line for outline in outlines for line in outline.markdown.splitlines() if line.startswith("#"))[:700]
            result = await provider.transcribe_chunk(audio, seq, prompt=f"课程：{course.name}。课时：{session.title}。{terms}")
        else:
            result = await provider.transcribe_chunk(audio, seq)
    except ASRError as exc:
        raise HTTPException(502, str(exc)) from exc
    with write_lock:
        db.expire_all()
        old = existing()
        if old:
            return old
        db.refresh(session)
        if session.status == "done":
            raise HTTPException(409, "课时已结束")
        segment = TranscriptSegment(session_id=session_id, seq=seq, start_ms=result.start_ms,
                                    end_ms=result.end_ms, text=result.text)
        session.status = "transcribing"
        db.add(segment)
        db.commit()
        db.refresh(segment)
    return segment


@router.post("/{session_id}/finish")
def finish_session(session_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    session = session_access(db, user, session_id, edit=True)
    with write_lock:
        session.status = "done"
        db.commit()
        db.refresh(session)
    return session


@router.delete("/{session_id}")
def discard_empty_session(session_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    session = session_access(db, user, session_id, edit=True)
    with write_lock:
        if db.exec(select(TranscriptSegment).where(TranscriptSegment.session_id == session_id)).first():
            raise HTTPException(409, "已有转写的课时不能作为空录音丢弃")
        if db.exec(select(Outline).where(Outline.session_id == session_id)).first():
            raise HTTPException(409, "已有提纲的课时不能丢弃")
        db.delete(session)
        db.commit()
    return {"ok": True}


@router.get("/{session_id}/transcript")
def get_transcript(session_id: int, user_id: int | None = None, db: Session = Depends(get_db),
                   user: User = Depends(current_user)):
    same_user(user, user_id)
    session_access(db, user, session_id)
    return db.exec(select(TranscriptSegment).where(TranscriptSegment.session_id == session_id)
                   .order_by(TranscriptSegment.seq)).all()


@router.post("/{session_id}/outline/generate")
async def generate_outline(session_id: int, user_id: int | None = None, db: Session = Depends(get_db),
                           user: User = Depends(current_user)):
    same_user(user, user_id)
    session = session_access(db, user, session_id)
    owner = outline_owner(db, user, session.class_course_id)
    old = snapshot(find_outline(db, session_id, owner))
    segments = db.exec(select(TranscriptSegment).where(TranscriptSegment.session_id == session_id)
                       .order_by(TranscriptSegment.seq)).all()
    texts = [(row.id, row.seq, row.text) for row in segments]
    if not texts:
        raise HTTPException(400, "尚无转写文本")
    markdown = await chat(OUTLINE_SYSTEM, "\n".join(row.text for row in segments))
    with write_lock:
        db.expire_all()
        outline = find_outline(db, session_id, owner)
        latest = db.exec(select(TranscriptSegment).where(TranscriptSegment.session_id == session_id)
                         .order_by(TranscriptSegment.seq)).all()
        if snapshot(outline) != old or [(row.id, row.seq, row.text) for row in latest] != texts:
            raise HTTPException(409, "生成期间提纲或转写已改变，请重试")
        if not outline:
            outline = Outline(session_id=session_id, class_course_id=session.class_course_id,
                              owner_id=owner, markdown=markdown)
        outline.markdown, outline.status, outline.updated_at = markdown, "generated", datetime.utcnow()
        db.add(outline)
        db.flush()
        rag.delete_document(session.class_course_id, f"outline_{outline.id}", db=db)
        db.commit()
        db.refresh(outline)
    return outline


@router.get("/{session_id}/outline")
def get_outline(session_id: int, user_id: int | None = None, db: Session = Depends(get_db),
                user: User = Depends(current_user)):
    same_user(user, user_id)
    session = session_access(db, user, session_id)
    owner = outline_owner(db, user, session.class_course_id)
    outline = find_outline(db, session_id, owner)
    if owner != -1 and not outline:
        outline = find_outline(db, session_id, -1)
        if outline and outline.status != "published":
            outline = None
    if not outline:
        raise HTTPException(404, "提纲不存在")
    return outline


class OutlineUpdate(BaseModel):
    markdown: str = Field(min_length=1, max_length=200000)


@router.put("/{session_id}/outline")
def update_outline(session_id: int, body: OutlineUpdate, user_id: int | None = None,
                   db: Session = Depends(get_db), user: User = Depends(current_user)):
    same_user(user, user_id)
    session = session_access(db, user, session_id)
    owner = outline_owner(db, user, session.class_course_id)
    with write_lock:
        outline = find_outline(db, session_id, owner)
        if not outline:
            outline = Outline(session_id=session_id, class_course_id=session.class_course_id,
                              owner_id=owner, markdown=body.markdown)
        outline.markdown, outline.status, outline.updated_at = body.markdown, "draft", datetime.utcnow()
        db.add(outline)
        db.flush()
        rag.delete_document(outline.class_course_id, f"outline_{outline.id}", db=db)
        db.commit()
        db.refresh(outline)
    return outline


class PublishBody(BaseModel):
    user_id: int
    action: Literal["publish", "reject"] = "publish"


@router.post("/{session_id}/outline/review")
def review_outline(session_id: int, body: PublishBody, db: Session = Depends(get_db),
                   user: User = Depends(current_user)):
    same_user(user, body.user_id)
    session = session_access(db, user, session_id)
    manager(db, user, session.class_course_id)
    with write_lock:
        outline = find_outline(db, session_id, -1)
        if not outline:
            raise HTTPException(404, "官方提纲不存在")
        outline.status = "published" if body.action == "publish" else "rejected"
        if body.action == "publish":
            rag.add_document(outline.class_course_id, f"outline_{outline.id}", outline.markdown,
                             source=f"提纲：{session.title}", db=db)
        else:
            rag.delete_document(outline.class_course_id, f"outline_{outline.id}", db=db)
        outline.updated_at = datetime.utcnow()
        db.commit()
        db.refresh(outline)
    return outline


@router.get("/outlines/pending")
def pending_outlines(class_course_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    manager(db, user, class_course_id)
    rows = db.exec(select(Outline).where(Outline.class_course_id == class_course_id, Outline.owner_id == -1,
                                        Outline.status.in_(["draft", "generated", "pending"]))).all()
    return [{**row.model_dump(), "session_title": db.get(CourseSession, row.session_id).title} for row in rows]
