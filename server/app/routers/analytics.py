import json
from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlmodel import Session, select

from ..db import get_db
from ..models import ClassCourse, KeywordStat, QuestionLog, User
from ..services.security import current_user, same_user, manager

router = APIRouter(prefix="/analytics", tags=["analytics"])


class KeywordInsight(BaseModel):
    keyword: str
    count: int
    examples: list[str] = []
    missed_count: int = 0
    heat: int = 0
    level: str = "低"


class ClassroomAnalytics(BaseModel):
    class_course_id: int
    updated_at: str
    total_questions: int
    missed_count: int
    top_keywords: list[KeywordInsight]
    hot_zones: list[KeywordInsight]


def _parse_keywords(raw: str) -> list[str]:
    try:
        data = json.loads(raw)
    except json.JSONDecodeError:
        return []
    if not isinstance(data, list):
        return []
    return [str(x) for x in data]


def _level(heat: int, missed_count: int) -> str:
    if heat >= 75 or missed_count >= 3:
        return "高"
    if heat >= 40 or missed_count >= 1:
        return "中"
    return "低"


@router.get("/classroom", response_model=ClassroomAnalytics)
def classroom_analytics(class_course_id: int, user_id: int, limit: int = 8, db: Session = Depends(get_db),
                        user: User = Depends(current_user)):
    """教师端课堂疑问洞察：高频关键词、典例、知识库未命中和疑惑热区。"""
    same_user(user, user_id)
    cc = manager(db, user, class_course_id)
    if not cc:
        raise HTTPException(404, "课程不存在")
    if cc.teacher_id != user_id:
        raise HTTPException(403, "仅本课程教师可查看课堂疑问")

    safe_limit = max(1, min(limit, 12))
    stats = db.exec(
        select(KeywordStat)
        .where(KeywordStat.class_course_id == class_course_id)
        .order_by(KeywordStat.count.desc(), KeywordStat.last_seen_at.desc())
        .limit(safe_limit)
    ).all()
    logs = db.exec(
        select(QuestionLog)
        .where(QuestionLog.class_course_id == class_course_id)
        .order_by(QuestionLog.created_at.desc())
    ).all()
    total_questions = len(logs)
    total_missed = sum(1 for item in logs if item.kb_missed)
    max_count = max((item.count for item in stats), default=0)

    insights: list[KeywordInsight] = []
    for stat in stats:
        examples: list[str] = []
        keyword_missed = 0
        for log in logs:
            keywords = _parse_keywords(log.keywords)
            if stat.keyword not in keywords:
                continue
            if log.kb_missed:
                keyword_missed += 1
            if len(examples) < 3 and log.question not in examples:
                examples.append(log.question)
        heat = 0 if max_count == 0 else max(8, round(stat.count * 100 / max_count))
        insights.append(
            KeywordInsight(
                keyword=stat.keyword,
                count=stat.count,
                examples=examples,
                missed_count=keyword_missed,
                heat=heat,
                level=_level(heat, keyword_missed),
            )
        )

    hot_zones = sorted(insights, key=lambda x: (x.heat, x.missed_count, x.count), reverse=True)[:6]
    return ClassroomAnalytics(
        class_course_id=class_course_id,
        updated_at=datetime.utcnow().isoformat(),
        total_questions=total_questions,
        missed_count=total_missed,
        top_keywords=insights,
        hot_zones=hot_zones,
    )
