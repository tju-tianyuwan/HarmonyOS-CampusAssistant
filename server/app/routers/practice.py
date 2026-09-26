from typing import Any

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel, Field
from sqlmodel import Session, select
from starlette.concurrency import run_in_threadpool

from ..db import get_db
from ..models import ClassCourse, CourseSession, Membership, User
from ..services import rag
from ..services.security import current_user, same_user, member
from ..services.practice import PracticeGenerationError, generate_choice_questions
from ..services.practice_context import practice_documents, topic_labels

router = APIRouter(prefix="/practice", tags=["practice"])


class GeneratePracticeBody(BaseModel):
    class_course_id: int
    session_id: int | None = Field(default=None, gt=0)
    user_id: int
    count: int = Field(default=5, ge=1, le=10)
    mode: str = Field(default="智能组卷", max_length=30)
    topic: str = Field(default="综合", max_length=80)
    difficulty: str = Field(default="综合", max_length=20)
    requirements: str = Field(default="", max_length=500)


class PracticeQuestionOut(BaseModel):
    id: int
    type: str
    difficulty: str
    topic: str
    stem: str
    options: list[str]
    answer: int
    explanation: str
    source: str


class PracticeGenerationOut(BaseModel):
    questions: list[PracticeQuestionOut]
    knowledge_sources: list[str]


def _knowledge_for_request(body: GeneratePracticeBody, db: Session, actor: User) -> list[dict[str, str]]:
    docs = practice_documents(body.class_course_id, body.session_id, db, actor)
    allowed = {doc.id for doc in docs}
    query_parts = [body.requirements.strip()]
    if body.topic != "综合":
        query_parts.append(body.topic)
    if body.mode != "智能组卷":
        query_parts.append(body.mode)
    query_text = " ".join(part for part in query_parts if part)

    hits = rag.query(body.class_course_id, query_text, top_k=8, db=db) if query_text else []
    hits.extend({"text": chunk, "source": doc.source, "doc_id": doc.id}
                for doc in docs for chunk in rag._split(doc.content))

    unique: list[dict[str, str]] = []
    seen: set[str] = set()
    for hit in hits:
        if hit.get("doc_id") not in allowed:
            continue
        text = str(hit.get("text", "")).strip()
        if not text or text in seen:
            continue
        seen.add(text)
        unique.append({"text": text, "source": str(hit.get("source", "课程知识库"))})
        if len(unique) == 8:
            break
    return unique


@router.get("/context")
def practice_context(class_course_id: int, session_id: int | None = None,
                     db: Session = Depends(get_db), actor: User = Depends(current_user)):
    course = member(db, actor, class_course_id)
    docs = practice_documents(class_course_id, session_id, db, actor)
    topics: dict[str, int] = {}
    for doc in docs:
        for label in topic_labels(doc.content, doc.source):
            topics[label] = topics.get(label, 0) + 1
    lesson = db.get(CourseSession, session_id) if session_id else None
    return {"class_course_id": course.id, "course_name": course.name,
            "session_id": session_id, "session_title": lesson.title if lesson else "",
            "knowledge_count": len(docs),
            "topics": [{"name": name, "source_count": count} for name, count in list(topics.items())[:60]],
            "knowledge_sources": list(dict.fromkeys(doc.source for doc in docs))}


@router.post("/generate", response_model=PracticeGenerationOut)
async def generate_practice(body: GeneratePracticeBody, db: Session = Depends(get_db),
                            actor: User = Depends(current_user)) -> dict[str, Any]:
    same_user(actor, body.user_id)
    member(db, actor, body.class_course_id)
    course = db.get(ClassCourse, body.class_course_id)
    if not course:
        raise HTTPException(404, "课程不存在")
    user = db.get(User, body.user_id)
    if not user:
        raise HTTPException(404, "用户不存在")
    membership = db.exec(
        select(Membership).where(
            Membership.class_course_id == body.class_course_id,
            Membership.user_id == body.user_id,
        )
    ).first()
    if not membership:
        raise HTTPException(403, "尚未加入该课程")

    knowledge = await run_in_threadpool(_knowledge_for_request, body, db, actor)
    if not knowledge:
        raise HTTPException(409, "当前课次暂无可用于出题的内容" if body.session_id else "当前课程知识库暂无可用于出题的内容")

    try:
        questions = await generate_choice_questions(
            course_name=course.name,
            mode=body.mode,
            topic=body.topic,
            difficulty=body.difficulty,
            requirements=body.requirements.strip(),
            count=body.count,
            knowledge=knowledge,
        )
    except PracticeGenerationError as exc:
        raise HTTPException(502, f"AI 题目生成失败：{exc}") from exc

    sources = list(dict.fromkeys(question["source"] for question in questions))
    return {"questions": questions, "knowledge_sources": sources}
