import json
from datetime import datetime
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlmodel import Session, select
from starlette.concurrency import run_in_threadpool

from ..db import get_db, write_lock
from ..models import Note, User
from ..services import rag
from ..services.llm import chat
from ..services.security import current_user, same_user, member

router = APIRouter(prefix="/notes", tags=["notes"])
EVAL_SYSTEM = ('你是课堂笔记质量评估器，按相关性、正确性、结构性打分（0-10），只输出 JSON：'
               '{"relevance":8,"correctness":8,"structure":8}。三项均不低于6才通过。')


class NoteBody(BaseModel):
    class_course_id: int
    owner_id: int
    title: str = Field(min_length=1, max_length=200)
    kind: Literal["md", "handwriting"] = "md"
    content: str = Field(default="", max_length=2000000)


class NoteUpdate(BaseModel):
    title: str | None = Field(default=None, min_length=1, max_length=200)
    content: str | None = Field(default=None, max_length=2000000)


def owned(db: Session, user: User, note_id: int) -> Note:
    note = db.get(Note, note_id)
    if not note:
        raise HTTPException(404, "笔记不存在")
    same_user(user, note.owner_id)
    member(db, user, note.class_course_id)
    return note


@router.get("")
def list_notes(class_course_id: int, user_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    same_user(user, user_id)
    member(db, user, class_course_id)
    notes = db.exec(select(Note).where(Note.class_course_id == class_course_id)).all()
    return [n for n in notes if n.owner_id == user.id or n.visibility == "shared"]


@router.post("")
def create_note(body: NoteBody, db: Session = Depends(get_db), user: User = Depends(current_user)):
    same_user(user, body.owner_id)
    member(db, user, body.class_course_id)
    note = Note(**body.model_dump())
    db.add(note)
    db.commit()
    db.refresh(note)
    return note


@router.put("/{note_id}")
def update_note(note_id: int, body: NoteUpdate, db: Session = Depends(get_db), user: User = Depends(current_user)):
    with write_lock:
        note = owned(db, user, note_id)
        for key, value in body.model_dump(exclude_none=True).items():
            setattr(note, key, value)
        note.updated_at = datetime.utcnow()
        note.quality_status, note.quality_score = "none", None
        rag.delete_document(note.class_course_id, f"note_{note.id}", db=db)
        db.commit()
        db.refresh(note)
    return note


@router.delete("/{note_id}")
def delete_note(note_id: int, user_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    same_user(user, user_id)
    with write_lock:
        note = owned(db, user, note_id)
        rag.delete_document(note.class_course_id, f"note_{note.id}", db=db)
        db.delete(note)
        db.commit()
    return {"ok": True, "id": note_id}


@router.post("/{note_id}/share")
async def share_note(note_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    with write_lock:
        note = owned(db, user, note_id)
        note.visibility = "shared"
        note.quality_status, note.quality_score = "evaluating" if note.kind == "md" else "none", None
        note.updated_at = datetime.utcnow()
        rag.delete_document(note.class_course_id, f"note_{note.id}", db=db)
        db.commit()
        db.refresh(note)
        version, content = note.updated_at, note.content
    if note.kind != "md" or not content.strip():
        note.quality_status = "none"
        db.commit()
        return note
    try:
        raw = await chat(EVAL_SYSTEM, content)
        verdict = json.loads(raw.strip().removeprefix("```json").removesuffix("```").strip())
    except Exception:
        verdict = {}
    scores = [verdict.get(key) for key in ("relevance", "correctness", "structure")] if isinstance(verdict, dict) else []
    accepted = len(scores) == 3 and all(type(score) in (int, float) and 6 <= score <= 10 for score in scores)
    def save():
        with write_lock:
            db.expire_all()
            latest = db.get(Note, note_id)
            if not latest or latest.updated_at != version or latest.content != content or latest.visibility != "shared":
                raise HTTPException(409, "评估期间笔记已修改或取消共享")
            latest.quality_status = "accepted" if accepted else "rejected"
            if accepted:
                latest.quality_score = sum(scores) / 3
                rag.add_document(latest.class_course_id, f"note_{latest.id}", latest.content,
                                 source=f"共享笔记：{latest.title}", db=db)
            db.commit()
            db.refresh(latest)
            return latest
    try:
        return await run_in_threadpool(save)
    except Exception:
        with write_lock:
            db.rollback()
            latest = db.get(Note, note_id)
            if latest and latest.updated_at == version and latest.quality_status == "evaluating":
                latest.quality_status = "none"
                db.commit()
        raise


@router.post("/{note_id}/unshare")
def unshare_note(note_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    with write_lock:
        note = owned(db, user, note_id)
        rag.delete_document(note.class_course_id, f"note_{note.id}", db=db)
        note.visibility, note.quality_status, note.quality_score = "private", "none", None
        note.updated_at = datetime.utcnow()
        db.commit()
        db.refresh(note)
    return note
