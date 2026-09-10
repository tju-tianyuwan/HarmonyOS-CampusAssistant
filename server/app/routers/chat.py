import json
import logging

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel, Field
from sqlmodel import Session, select
from starlette.concurrency import run_in_threadpool

from ..db import get_db, engine, write_lock
from ..models import ChatMessage, ChatSession, ClassCourse, QuestionLog, User
from ..services.analytics import rebuild_keyword_stats, record_question
from ..services import rag
from ..services.security import current_user, same_user, member
from ..services.llm import chat_stream
from ..services.mas import (
    build_agent_system,
    build_agent_user,
    public_agents,
    role_for_agent,
    select_agents,
)

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
    question: str = Field(min_length=1, max_length=4000)
    context_note: str = Field(default="", max_length=200000)
    mode: str = "single"
    agent_ids: list[str] = Field(default_factory=list)


@router.get("/agents")
def list_agents():
    return public_agents()


@router.get("/sessions")
def list_chat_sessions(class_course_id: int, user_id: int, db: Session = Depends(get_db),
                       user: User = Depends(current_user)):
    same_user(user, user_id)
    member(db, user, class_course_id)
    return db.exec(
        select(ChatSession)
        .where(ChatSession.class_course_id == class_course_id, ChatSession.user_id == user_id)
        .order_by(ChatSession.created_at.desc())
    ).all()


@router.post("/sessions")
def create_chat_session(body: CreateChat, db: Session = Depends(get_db), user: User = Depends(current_user)):
    same_user(user, body.user_id)
    member(db, user, body.class_course_id)
    cs = ChatSession(**body.model_dump())
    db.add(cs)
    db.commit()
    db.refresh(cs)
    return cs


@router.get("/sessions/{chat_session_id}/messages")
def list_messages(chat_session_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    cs = db.get(ChatSession, chat_session_id)
    if not cs:
        raise HTTPException(404, "会话不存在")
    same_user(user, cs.user_id)
    member(db, user, cs.class_course_id)
    return db.exec(
        select(ChatMessage).where(ChatMessage.chat_session_id == chat_session_id).order_by(ChatMessage.created_at)
    ).all()


@router.delete("/sessions/{chat_session_id}")
def delete_chat_session(chat_session_id: int, user_id: int, db: Session = Depends(get_db),
                        user: User = Depends(current_user)):
    same_user(user, user_id)
    cs = db.get(ChatSession, chat_session_id)
    if not cs:
        raise HTTPException(404, "会话不存在")
    if cs.user_id != user_id:
        raise HTTPException(403, "只能删除自己的会话")
    class_course_id = cs.class_course_id

    with write_lock:
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
async def ask(body: AskBody, db: Session = Depends(get_db), user: User = Depends(current_user)):
    """课程问答。单助手或 MAS 圆桌均通过 SSE 流式返回。"""
    cs = db.get(ChatSession, body.chat_session_id)
    if not cs:
        raise HTTPException(404, "会话不存在")
    same_user(user, cs.user_id)
    member(db, user, cs.class_course_id)
    chat_session_id = cs.id
    class_course_id = cs.class_course_id
    user_id = cs.user_id

    db.add(ChatMessage(chat_session_id=chat_session_id, role="user", content=body.question))
    db.commit()

    hits = await run_in_threadpool(rag.query, class_course_id, body.question, db=db)
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
    metadata = {"sources": sources, "retrieval_mode": hits[0].get("retrieval_mode", "none") if hits else "none",
                "warnings": list(dict.fromkeys(h.get("warning") for h in hits if h.get("warning")))}

    def persist(role, content):
        with write_lock, Session(engine) as saved:
            if not saved.get(ChatSession, chat_session_id):
                return False
            saved.add(ChatMessage(chat_session_id=chat_session_id, role=role, content=content,
                                  sources=json.dumps(sources, ensure_ascii=False)))
            saved.commit()
        return True

    async def gen_single():
        yield f"event: sources\ndata: {json.dumps(sources, ensure_ascii=False)}\n\n"
        for warning in metadata["warnings"]:
            yield f"event: warning\ndata: {json.dumps(warning, ensure_ascii=False)}\n\n"
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
            if not persist("assistant", full):
                return
        except Exception:
            logger.exception("AI stream failed for chat session %s", chat_session_id)
            yield f"event: error\ndata: {json.dumps('AI 服务请求失败，请稍后重试。', ensure_ascii=False)}\n\n"
            return
        yield f"event: done\ndata: {json.dumps(metadata, ensure_ascii=False)}\n\n"

    async def gen_mas():
        yield f"event: sources\ndata: {json.dumps(sources, ensure_ascii=False)}\n\n"
        for warning in metadata["warnings"]:
            yield f"event: warning\ndata: {json.dumps(warning, ensure_ascii=False)}\n\n"
        if not hits:
            yield f"event: warning\ndata: {json.dumps(KB_WARNING, ensure_ascii=False)}\n\n"

        course_context = "\n---\n".join(h["text"] for h in hits)
        if body.context_note.strip():
            memory = body.context_note.strip()
        else:
            memory = ""
        discussion: list[tuple[str, str]] = []

        try:
            for agent in select_agents(body.agent_ids):
                yield f"event: agent\ndata: {json.dumps(agent.public_dict(), ensure_ascii=False)}\n\n"
                system = build_agent_system(agent, course_context, memory, bool(hits))
                user_prompt = build_agent_user(body.question, discussion)
                full = ""
                async for delta in chat_stream(system, user_prompt):
                    full += delta
                    yield f"data: {json.dumps(delta, ensure_ascii=False)}\n\n"

                discussion.append((agent.name, full))
                if not persist(role_for_agent(agent), full):
                    return
                yield f"event: agent_done\ndata: {json.dumps(agent.id, ensure_ascii=False)}\n\n"
        except Exception:
            logger.exception("MAS stream failed for chat session %s", chat_session_id)
            yield f"event: error\ndata: {json.dumps('AI 圆桌讨论失败，请稍后重试。', ensure_ascii=False)}\n\n"
            return
        yield f"event: done\ndata: {json.dumps(metadata, ensure_ascii=False)}\n\n"

    use_mas = body.mode == "mas" and asker is not None and asker.role == "student"

    return StreamingResponse(
        gen_mas() if use_mas else gen_single(),
        media_type="text/event-stream",
        headers={"Cache-Control": "no-cache", "X-Accel-Buffering": "no"},
    )
