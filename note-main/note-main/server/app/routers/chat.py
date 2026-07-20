import json

from fastapi import APIRouter, Depends, HTTPException
from fastapi.responses import StreamingResponse
from pydantic import BaseModel
from sqlmodel import Session, select

from ..db import get_db, engine
from ..models import ChatMessage, ChatSession
from ..services import rag
from ..services.llm import chat_stream

router = APIRouter(prefix="/chat", tags=["chat"])

QA_SYSTEM_TMPL = (
    "你是课程学习助手，只能依据下方「课程知识库片段」回答问题，禁止使用外部知识编造。"
    "若片段与问题无关，必须回答：“本课程资料中未找到相关内容。”\n\n课程知识库片段：\n{context}"
)

NO_KB_REPLY = "本课程资料中未找到相关内容。"


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


@router.post("/ask")
async def ask(body: AskBody, db: Session = Depends(get_db)):
    """集合限定问答，SSE 流式返回。事件：sources（引用）→ delta*N → done"""
    cs = db.get(ChatSession, body.chat_session_id)
    if not cs:
        raise HTTPException(404, "会话不存在")
    class_course_id = cs.class_course_id

    db.add(ChatMessage(chat_session_id=cs.id, role="user", content=body.question))
    db.commit()

    hits = rag.query(class_course_id, body.question)
    sources = [h["source"] for h in hits]

    async def gen():
        yield f"event: sources\ndata: {json.dumps(sources, ensure_ascii=False)}\n\n"
        full = ""
        if not hits and not body.context_note:
            full = NO_KB_REPLY
            yield f"data: {json.dumps(full, ensure_ascii=False)}\n\n"
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
                    chat_session_id=cs.id, role="assistant", content=full,
                    sources=json.dumps(sources, ensure_ascii=False),
                )
            )
            db2.commit()
        yield "event: done\ndata: {}\n\n"

    return StreamingResponse(gen(), media_type="text/event-stream")
