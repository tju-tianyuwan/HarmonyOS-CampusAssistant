import json
import logging

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from sqlmodel import Session, select

from ..db import get_db, engine
from ..models import ChatMessage, ChatSession, ClassCourse, QuestionLog, User
from ..services.analytics import rebuild_keyword_stats, record_question
from ..services import rag
from ..services.llm import chat_stream

router = APIRouter(prefix="/chat", tags=["chat"])
logger = logging.getLogger(__name__)

QA_SYSTEM_TMPL = (
    "你是课程学习助手，只能依据下方「课程知识库片段」回答问题，禁止使用外部知识编造。"
    "若片段与问题无关，必须回答：“本课程资料中未找到相关内容。”\n\n课程知识库片段：\n{context}"
)

KB_WARNING = "知识库中暂时未包含该知识点，以下内容可能有误，请结合课程资料核对。"
FALLBACK_SYSTEM = (
    "你是课程学习助手。当前课程知识库没有命中与问题直接相关的内容。"
    "请基于通用知识给出简洁回答，不要声称答案来自本课程知识库；"
    "对不确定的内容明确说明。"
)


class CreateChat(BaseModel):
    class_course_id: int
    user_id: int
    title: str = "新会话"


class AskBody(BaseModel):
    chat_session_id: int
    question: str
    context_note: str = ""  # 「携带当前笔记作为上下文」时客户端传入


@router.get("/sessions")
def list_chat_sessions(class_course_id: int, user_id: int, db: Session = Depends(get_db)):
    return db.exec(
        select(ChatSession)
        .where(ChatSession.class_course_id == class_course_id, ChatSession.user_id == user_id)
        .order_by(ChatSession.created_at.desc())
    ).all()


@router.post("/sessions")
def create_chat_session(body: CreateChat, db: Session = Depends(get_db)):
    cs = ChatSession(**body.model_dump())
    db.add(cs)
    db.commit()
    db.refresh(cs)
    return cs


@router.get("/sessions/{chat_session_id}/messages")
def list_messages(chat_session_id: int, db: Session = Depends(get_db)):
    return db.exec(
        select(ChatMessage).where(ChatMessage.chat_session_id == chat_session_id).order_by(ChatMessage.created_at)
    ).all()


@router.delete("/sessions/{chat_session_id}")
def delete_chat_session(chat_session_id: int, user_id: int, db: Session = Depends(get_db)):
    cs = db.get(ChatSession, chat_session_id)
    if not cs:
        raise HTTPException(404, "会话不存在")
    if cs.user_id != user_id:
        raise HTTPException(403, "只能删除自己的会话")
    class_course_id = cs.class_course_id

    messages = db.exec(
        select(ChatMessage).where(ChatMessage.chat_session_id == chat_session_id)
    ).all()
    logs = db.exec(
        select(QuestionLog).where(QuestionLog.chat_session_id == chat_session_id)
    ).all()
    for message in messages:
        db.delete(message)
    for log in logs:
        db.delete(log)
    db.delete(cs)
    db.flush()
    rebuild_keyword_stats(db, class_course_id)
    db.commit()
    return {"ok": True, "id": chat_session_id}


@router.post("/ask")
async def ask(body: AskBody, db: Session = Depends(get_db)):
    """集合限定问答，SSE 流式返回。事件：sources（引用）→ delta*N → done"""
    cs = db.get(ChatSession, body.chat_session_id)
    if not cs:
        raise HTTPException(404, "会话不存在")
    chat_session_id = cs.id
    class_course_id = cs.class_course_id
    user_id = cs.user_id

    db.add(ChatMessage(chat_session_id=chat_session_id, role="user", content=body.question))
    db.commit()

    hits = rag.query(class_course_id, body.question)
    asker = db.get(User, user_id)
    if asker and asker.role == "student":
        course = db.get(ClassCourse, class_course_id)
        try:
            await record_question(
                db,
                class_course_id,
                user_id,
                chat_session_id,
                body.question,
                len(hits),
                course.name if course else "",
            )
        except Exception:
            db.rollback()
    sources = [h["source"] for h in hits]

    async def gen():
        yield f"event: sources\ndata: {json.dumps(sources, ensure_ascii=False)}\n\n"
        full = ""
        try:
            if not hits:
                yield f"event: warning\ndata: {json.dumps(KB_WARNING, ensure_ascii=False)}\n\n"
                full = KB_WARNING + "\n\n"
                system = FALLBACK_SYSTEM
                if body.context_note.strip():
                    system += "\n\n可参考的学生当前笔记（不等同于课程知识库）：\n" + body.context_note
                async for delta in chat_stream(system, body.question):
                    full += delta
                    yield f"data: {json.dumps(delta, ensure_ascii=False)}\n\n"
            else:
                context = "\n---\n".join(h["text"] for h in hits)
                if body.context_note:
                    context += "\n---\n[学生当前笔记]\n" + body.context_note
                system = QA_SYSTEM_TMPL.format(context=context)
                async for delta in chat_stream(system, body.question):
                    full += delta
                    yield f"data: {json.dumps(delta, ensure_ascii=False)}\n\n"
            with Session(engine) as db2:
                db2.add(
                    ChatMessage(
                        chat_session_id=chat_session_id, role="assistant", content=full,
                        sources=json.dumps(sources, ensure_ascii=False),
                    )
                )
                db2.commit()
        except Exception:
            logger.exception("AI stream failed for chat session %s", chat_session_id)
            yield f"event: error\ndata: {json.dumps('AI 服务请求失败，请稍后重试。', ensure_ascii=False)}\n\n"
            return
        yield "event: done\ndata: {}\n\n"

    return StreamingResponse(
        gen(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )
