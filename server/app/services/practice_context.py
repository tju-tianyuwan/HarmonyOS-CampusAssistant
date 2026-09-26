"""Read practice metadata from the same authorized documents used for generation."""
import re
from sqlmodel import Session
from ..models import CourseSession, Note, Outline, SessionResource, User
from . import rag


def practice_documents(course_id: int, session_id: int | None, db: Session, actor: User):
    if session_id is not None:
        from ..routers.sessions import session_access
        from fastapi import HTTPException
        lesson = db.get(CourseSession, session_id)
        if lesson is None or lesson.class_course_id != course_id:
            raise HTTPException(404, "课时不属于当前课程")
        session_access(db, actor, session_id)
    docs = rag.documents(course_id, db)
    if session_id is None:
        return docs
    scoped = []
    for doc in docs:
        ref = doc.id.split(":", 1)[-1]
        for prefix, model in (("outline_", Outline), ("note_", Note), ("resource_", SessionResource)):
            if ref.startswith(prefix) and ref[len(prefix):].isdigit():
                row = db.get(model, int(ref[len(prefix):]))
                if row and row.class_course_id == course_id and row.session_id == session_id:
                    scoped.append(doc)
                break
    return scoped


def topic_labels(markdown: str, source: str) -> list[str]:
    labels = []
    fenced = False
    for line in markdown.splitlines():
        if re.match(r"^\s*(```|~~~)", line):
            fenced = not fenced
        if fenced:
            continue
        match = re.match(r"^\s{0,3}#{1,6}\s+(.+?)\s*#*\s*$", line)
        if not match:
            continue
        label = re.sub(r"[*`_]", "", match.group(1))
        label = re.sub(r"^(?:第[一二三四五六七八九十百\d]+[章节讲]\s*|[（(]?[一二三四五六七八九十\d]+[）)、.．]\s*)", "", label).strip()
        if label and len(label) <= 80 and label not in labels and label not in {
            "综合", "课程提纲", "课堂提纲", "AI 提纲", "总结", "小结", "目录", "例题", "练习", "学习目标", "考试重点"
        }:
            labels.append(label)
    if not labels:
        label = re.sub(r"^(?:提纲|共享笔记|资料)[：:]\s*", "", source).strip()
        if label and len(label) <= 80 and label != "综合":
            labels.append(label)
    return labels
