import asyncio
import json
from contextlib import suppress
from datetime import datetime
from typing import Literal

from fastapi import APIRouter, Depends, File, HTTPException, Path, Response, UploadFile, WebSocket, WebSocketDisconnect
from fastapi.security import HTTPAuthorizationCredentials
from filelock import Timeout as LockTimeout
from pydantic import BaseModel, Field
from sqlmodel import Session, select
from starlette.concurrency import run_in_threadpool

from ..db import get_db, write_lock
from ..config import settings
from ..models import ClassCourse, CourseSession, Note, Outline, SessionResource, TranscriptSegment, User
from ..services import rag
from ..services.asr import ASRError, get_asr_provider
from ..services.asr.local import LocalASRProvider
from ..services.asr.huawei_realtime import HuaweiRealtimeStream, RealtimeTranscript
from ..services.locking import process_lock
from ..services.llm import chat
from ..services.documents import extract
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


@router.get("/recording-config")
def recording_config(user: User = Depends(current_user)):
    return {"realtime": settings.asr_provider == "huawei_sis_realtime", "sample_rate": 16000,
            "channels": 1, "sample_width": 2, "window_ms": 60000, "frame_bytes": 6400}


@router.websocket("/{session_id}/realtime/{seq}")
async def realtime_audio(websocket: WebSocket, session_id: int, seq: int, db: Session = Depends(get_db)):
    """Continuous audio in, interim text out; commit/ack only after Huawei END.

    A window is at most 60 s and remains on the device until its durable ack.
    Replaying a committed sequence returns its stored row without calling SIS.
    """
    await websocket.accept()
    lock = None
    acquired = False
    try:
        scheme, _, token = websocket.headers.get("authorization", "").partition(" ")
        credentials = HTTPAuthorizationCredentials(scheme=scheme, credentials=token) if scheme.lower() == "bearer" and token else None
        user = current_user(credentials, db)
        if user.role != "teacher":
            raise HTTPException(403, "学生不能上传课堂录音")
        if seq < 0:
            raise HTTPException(422, "录音序号无效")
        session = session_access(db, user, session_id, edit=True)
        lock = process_lock(f"realtime-session-{session_id}")
        try:
            lock.acquire(timeout=0)
            acquired = True
        except LockTimeout:
            raise HTTPException(409, "该课时已有实时录音连接，请稍后重试")
        old = db.exec(select(TranscriptSegment).where(TranscriptSegment.session_id == session_id,
                                                      TranscriptSegment.seq == seq)).first()
        if old:
            await websocket.send_json({"type": "committed", "segment": old.model_dump()})
            return
        if session.status == "done":
            raise HTTPException(409, "课时已结束")
        if settings.asr_provider != "huawei_sis_realtime":
            raise HTTPException(409, "服务端未启用华为云实时识别")
        previous = db.exec(select(TranscriptSegment).where(TranscriptSegment.session_id == session_id)
                           .order_by(TranscriptSegment.seq.desc())).first()
        if seq != (previous.seq + 1 if previous else 0):
            raise HTTPException(409, "请先补传前面的录音，避免丢失课堂内容")
        start_ms = previous.end_ms if previous else 0
        db.rollback()  # Never retain a SQLite read transaction across the network wait.
        transcript = RealtimeTranscript()
        byte_count = 0
        stopping = False
        async with HuaweiRealtimeStream() as cloud:
            await websocket.send_json({"type": "ready", "seq": seq, "start_ms": start_ms})

            async def upload():
                nonlocal byte_count, stopping
                started = asyncio.get_running_loop().time()
                while True:
                    message = await asyncio.wait_for(websocket.receive(), 20)
                    if message["type"] == "websocket.disconnect":
                        raise WebSocketDisconnect()
                    audio = message.get("bytes")
                    if audio is not None:
                        if not audio or len(audio) % 2 or len(audio) > 6400:
                            raise ASRError("音频帧须为不超过 6400 字节的 16 位 PCM")
                        byte_count += len(audio)
                        if byte_count > 1920000:
                            raise ASRError("实时录音窗口超过 60 秒，请分段重连")
                        # Bound replay speed and memory use even for a misbehaving client.
                        delay = byte_count / 64000 - (asyncio.get_running_loop().time() - started)
                        if delay > 0:
                            await asyncio.sleep(delay)
                        await cloud.send_audio(audio)
                    else:
                        raw = message.get("text", "")
                        if len(raw) > 256 or json.loads(raw).get("type") != "stop" or not byte_count:
                            raise ASRError("实时录音结束消息无效或音频为空")
                        stopping = True
                        await cloud.end()
                        return

            async def receive():
                while True:
                    event = await cloud.receive(timeout=90)
                    kind = event.get("resp_type")
                    if kind == "RESULT":
                        transcript.update(event)
                        await websocket.send_json({"type": "partial", "seq": seq,
                                                   "text": transcript.text(interim=True), "start_ms": start_ms})
                    elif kind == "END":
                        if not stopping:
                            raise ASRError("云端提前结束识别，已保留录音供重试")
                        if transcript.interim:
                            raise ASRError("云端未确认最后一句识别结果，已保留录音供重试")
                        return

            sender = asyncio.create_task(upload())
            receiver = asyncio.create_task(receive())
            try:
                done, _ = await asyncio.wait((sender, receiver), return_when=asyncio.FIRST_COMPLETED)
                for task in done:
                    task.result()
                if receiver in done and not sender.done():
                    raise ASRError("云端提前关闭录音连接，请重试")
                await sender
                await asyncio.wait_for(receiver, 25)
            finally:
                for task in (sender, receiver):
                    task.cancel()
                await asyncio.gather(sender, receiver, return_exceptions=True)
        with write_lock:
            db.expire_all()
            user = current_user(credentials, db)
            session = session_access(db, user, session_id, edit=True)
            if session.status == "done":
                raise HTTPException(409, "课时已结束，录音尚未保存")
            segment = TranscriptSegment(session_id=session_id, seq=seq, start_ms=start_ms,
                                        end_ms=start_ms + round(byte_count / 32), text=transcript.text())
            db.add(segment)
            session.status = "transcribing"
            db.add(session)
            db.commit()
            db.refresh(segment)
        await websocket.send_json({"type": "committed", "segment": segment.model_dump()})
    except WebSocketDisconnect:
        pass
    except (HTTPException, ASRError, asyncio.TimeoutError, ValueError, KeyError, TypeError) as exc:
        detail = exc.detail if isinstance(exc, HTTPException) else str(exc) if isinstance(exc, ASRError) else "实时录音连接超时或数据无效，缓存已保留"
        with suppress(RuntimeError, WebSocketDisconnect):
            await websocket.send_json({"type": "error", "message": detail,
                                       "status": exc.status_code if isinstance(exc, HTTPException) else 502})
    except Exception:
        # Never forward cloud exception strings (which may contain signed headers).
        with suppress(RuntimeError, WebSocketDisconnect):
            await websocket.send_json({"type": "error", "message": "实时识别连接失败，录音缓存已保留，请重试", "status": 502})
    finally:
        if acquired:
            lock.release()
        with suppress(RuntimeError, WebSocketDisconnect):
            await websocket.close()


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
        resources = db.exec(select(SessionResource.id).where(SessionResource.session_id == session.id)).all()
        personal_notes = db.exec(select(Note).where(Note.session_id == session.id,
                                                    Note.owner_id == user.id)).all()
        result.append({**session.model_dump(), "outline_kind": kind,
                       "outline_status": selected.status if selected else session.status,
                       "resource_count": len(resources),
                       "personal_notes": [{"id": note.id, "title": note.title, "kind": note.kind}
                                          for note in personal_notes]})
    return result


@router.get("/materials")
def course_materials(class_course_id: int, response: Response, db: Session = Depends(get_db),
                     user: User = Depends(current_user)):
    manager(db, user, class_course_id)
    if user.role != "teacher":
        raise HTTPException(403, "仅课程教师可查看教学资料汇总")
    response.headers["Cache-Control"] = "no-store"
    result = []
    outlines = db.exec(select(Outline, CourseSession).join(
        CourseSession, CourseSession.id == Outline.session_id).where(
        Outline.class_course_id == class_course_id, CourseSession.class_course_id == class_course_id,
        Outline.owner_id == -1)).all()
    for outline, session in outlines:
        result.append({"id": outline.id, "kind": "outline", "session_id": session.id,
                       "session_title": session.ai_title or session.title, "title": session.title,
                       "status": outline.status, "chars": len(outline.markdown),
                       "updated_at": outline.updated_at})
    resources = db.exec(select(SessionResource, CourseSession).join(
        CourseSession, CourseSession.id == SessionResource.session_id).where(
        SessionResource.class_course_id == class_course_id, CourseSession.class_course_id == class_course_id)).all()
    for resource, session in resources:
        result.append({"id": resource.id, "kind": "resource", "session_id": session.id,
                       "session_title": session.ai_title or session.title, "title": resource.filename,
                       "status": "uploaded", "chars": len(resource.content), "updated_at": resource.created_at})
    return sorted(result, key=lambda item: (item["updated_at"], item["id"]), reverse=True)


@router.post("")
def create_session(body: CreateSession, db: Session = Depends(get_db), user: User = Depends(current_user)):
    if user.role != "teacher":
        raise HTTPException(403, "学生不能创建录音课次")
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
    if user.role != "teacher":
        raise HTTPException(403, "学生不能上传课堂录音")
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
        heading = next((line.lstrip("# ").strip() for line in markdown.splitlines()
                        if line.strip().startswith("#") and line.lstrip("# ").strip()), "")
        if heading:
            session.ai_title = heading[:80]
            db.add(session)
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


@router.get("/{session_id}/resources")
def list_resources(session_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    session_access(db, user, session_id)
    rows = db.exec(select(SessionResource).where(SessionResource.session_id == session_id)
                   .order_by(SessionResource.created_at.desc())).all()
    return [{"id": row.id, "session_id": row.session_id, "filename": row.filename,
             "chars": len(row.content), "created_at": row.created_at} for row in rows]


@router.get("/{session_id}/resources/{resource_id}")
def resource_detail(session_id: int, resource_id: int, db: Session = Depends(get_db),
                    user: User = Depends(current_user)):
    session_access(db, user, session_id)
    row = db.get(SessionResource, resource_id)
    if not row or row.session_id != session_id:
        raise HTTPException(404, "课程资料不存在")
    return row


@router.post("/{session_id}/resources")
async def upload_resource(session_id: int, file: UploadFile = File(...), db: Session = Depends(get_db),
                          user: User = Depends(current_user)):
    session = session_access(db, user, session_id)
    manager(db, user, session.class_course_id)
    from pathlib import Path as FilePath
    from ..config import settings
    filename = FilePath((file.filename or "").replace("\\", "/")).name[:200]
    data = await file.read(settings.document_max_bytes + 1)
    if not data or len(data) > settings.document_max_bytes:
        raise HTTPException(413, "文件为空或超过上传限制")
    content = await run_in_threadpool(extract, filename, data)
    with write_lock:
        row = SessionResource(session_id=session.id, class_course_id=session.class_course_id,
                              uploader_id=user.id, filename=filename, content=content)
        db.add(row)
        db.flush()
        rag.add_document(session.class_course_id, f"resource_{row.id}", content,
                         source=f"课程资料：{filename}", db=db)
        db.commit()
        db.refresh(row)
    return row


class ResourceUpdate(BaseModel):
    content: str = Field(min_length=1, max_length=500000)


@router.put("/{session_id}/resources/{resource_id}")
def update_resource(session_id: int, resource_id: int, body: ResourceUpdate,
                    db: Session = Depends(get_db), user: User = Depends(current_user)):
    session = session_access(db, user, session_id)
    manager(db, user, session.class_course_id)
    if not body.content.strip():
        raise HTTPException(422, "资料内容不能为空")
    with write_lock:
        row = db.get(SessionResource, resource_id)
        if not row or row.session_id != session_id or row.class_course_id != session.class_course_id:
            raise HTTPException(404, "课程资料不存在")
        row.content = body.content
        rag.add_document(session.class_course_id, f"resource_{row.id}", row.content,
                         source=f"课程资料：{row.filename}", db=db)
        db.add(row)
        db.commit()
        db.refresh(row)
    return row


@router.delete("/{session_id}/resources/{resource_id}")
def delete_resource(session_id: int, resource_id: int, db: Session = Depends(get_db),
                    user: User = Depends(current_user)):
    session = session_access(db, user, session_id)
    manager(db, user, session.class_course_id)
    with write_lock:
        row = db.get(SessionResource, resource_id)
        if not row or row.session_id != session_id:
            raise HTTPException(404, "课程资料不存在")
        rag.delete_document(session.class_course_id, f"resource_{row.id}", db=db)
        db.delete(row)
        db.commit()
    return {"ok": True}


@router.get("/outlines")
def course_outlines(class_course_id: int, db: Session = Depends(get_db),
                    user: User = Depends(current_user)):
    manager(db, user, class_course_id)
    if user.role != "teacher":
        raise HTTPException(403, "仅课程教师可查看课程提纲")
    rows = db.exec(select(Outline).where(
        Outline.class_course_id == class_course_id,
        Outline.owner_id == -1,
    ).order_by(Outline.updated_at.desc())).all()
    result = []
    for outline in rows:
        session = db.get(CourseSession, outline.session_id)
        if session and session.class_course_id == class_course_id:
            result.append({**outline.model_dump(), "session_title": session.title,
                           "session_created_at": session.created_at.isoformat()})
    return result


@router.get("/outlines/pending")
def pending_outlines(class_course_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    manager(db, user, class_course_id)
    rows = db.exec(select(Outline).where(Outline.class_course_id == class_course_id, Outline.owner_id == -1,
                                        Outline.status.in_(["draft", "generated", "pending"]))).all()
    return [{**row.model_dump(), "session_title": db.get(CourseSession, row.session_id).title} for row in rows]
