import json
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlmodel import Session, select

from ..db import get_db
from ..models import Note
from ..services import rag
from ..services.llm import chat

router = APIRouter(prefix="/notes", tags=["notes"])

EVAL_SYSTEM = (
    "你是课堂笔记质量评估器。对给定笔记按 相关性/正确性/结构性 三维打分（0-10），"
    '只输出 JSON：{"relevance":n,"correctness":n,"structure":n,"pass":true/false}。'
    "三项均 ≥6 判定 pass 为 true。"
)


class NoteBody(BaseModel):
    class_course_id: int
    owner_id: int
    title: str
    kind: str = "md"  # md | handwriting
    content: str = ""


class NoteUpdate(BaseModel):
    title: str | None = None
    content: str | None = None


@router.get("")
def list_notes(class_course_id: int, user_id: int, db: Session = Depends(get_db)):
    """自己的全部笔记 + 他人共享的笔记"""
    notes = db.exec(select(Note).where(Note.class_course_id == class_course_id)).all()
    return [n for n in notes if n.owner_id == user_id or n.visibility == "shared"]


@router.post("")
def create_note(body: NoteBody, db: Session = Depends(get_db)):
    n = Note(**body.model_dump())
    db.add(n)
    db.commit()
    db.refresh(n)
    return n


@router.put("/{note_id}")
def update_note(note_id: int, body: NoteUpdate, db: Session = Depends(get_db)):
    n = db.get(Note, note_id)
    if not n:
        raise HTTPException(404, "笔记不存在")
    if body.title is not None:
        n.title = body.title
    if body.content is not None:
        n.content = body.content
    n.updated_at = datetime.utcnow()
    db.commit()
    db.refresh(n)
    return n


@router.post("/{note_id}/share")
async def share_note(note_id: int, db: Session = Depends(get_db)):
    """共享 → LLM 质量评估 → 通过则入该集合知识库（仅 MD 笔记）"""
    n = db.get(Note, note_id)
    if not n:
        raise HTTPException(404, "笔记不存在")
    n.visibility = "shared"
    if n.kind == "md" and n.content.strip():
        n.quality_status = "evaluating"
        db.commit()
        raw = await chat(EVAL_SYSTEM, n.content)
        try:
            verdict = json.loads(raw.strip().removeprefix("```json").removesuffix("```").strip())
        except (json.JSONDecodeError, AttributeError):
            verdict = {"pass": False}
        if verdict.get("pass"):
            n.quality_status = "accepted"
            n.quality_score = (
                verdict.get("relevance", 0) + verdict.get("correctness", 0) + verdict.get("structure", 0)
            ) / 3
            rag.add_document(n.class_course_id, f"note_{n.id}", n.content, source=f"共享笔记：{n.title}")
        else:
            n.quality_status = "rejected"
    db.commit()
    db.refresh(n)
    return n


@router.post("/{note_id}/unshare")
def unshare_note(note_id: int, db: Session = Depends(get_db)):
    n = db.get(Note, note_id)
    if not n:
        raise HTTPException(404, "笔记不存在")
    n.visibility = "private"
    db.commit()
    db.refresh(n)
    return n
