from fastapi import APIRouter, Depends, HTTPException, Response
from sqlmodel import Session, select

from ..db import get_db
from ..models import CourseSchedule, Membership, User
from ..services.course_schedule import default_start
from ..services.security import current_user

router = APIRouter(prefix="/timetable", tags=["timetable"])


@router.get("")
def get_timetable(response: Response, db: Session = Depends(get_db), user: User = Depends(current_user)):
    response.headers["Cache-Control"] = "no-store"
    rows = db.exec(select(CourseSchedule).join(
        Membership, Membership.class_course_id == CourseSchedule.class_course_id
    ).where(Membership.user_id == user.id).distinct()
        .order_by(CourseSchedule.weekday, CourseSchedule.start_section, CourseSchedule.id)).all()
    starts = sorted({row.semester_start for row in rows})
    return {"semester_start": starts[0] if starts else default_start(),
            "configured": bool(rows), "multiple_semesters": len(starts) > 1, "entries": rows}


# Old clients must not continue creating personal copies of official course times.
@router.put("/settings")
@router.post("/entries")
@router.put("/entries/{entry_id}")
@router.delete("/entries/{entry_id}")
def reject_personal_schedule(user: User = Depends(current_user)):
    raise HTTPException(403, "上课时间由课程教师统一安排，请刷新课表或更新客户端")
