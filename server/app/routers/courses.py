import secrets
import string

from fastapi import APIRouter, Depends, HTTPException, Response
from pydantic import BaseModel
from sqlalchemy import func
from sqlmodel import Session, select

from ..db import get_db, write_lock
from ..models import ClassCourse, CourseSession, Membership, Note, Outline, PersonalWorkspace, User
from ..services.security import current_user, same_user, member
from ..services.course_schedule import ScheduleBody, read_schedule, replace_schedule, schedule_teacher

router = APIRouter(prefix="/courses", tags=["courses"])


class CreateCourse(BaseModel):
    name: str
    class_name: str
    teacher_id: int
    schedule: ScheduleBody


class JoinCourse(BaseModel):
    user_id: int
    invite_code: str


class CourseWorkspaceStats(BaseModel):
    class_course_id: int
    official_lesson_count: int
    personal_note_count: int
    class_note_count: int


@router.get("")
def list_courses(user_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    """用户已加入的课程集合"""
    same_user(user, user_id)
    mids = db.exec(select(Membership.class_course_id).where(Membership.user_id == user_id)).all()
    if not mids:
        return []
    courses = db.exec(select(ClassCourse).where(ClassCourse.id.in_(mids))).all()
    result = []
    for c in courses:
        teacher = db.get(User, c.teacher_id)
        personal = db.exec(select(PersonalWorkspace).where(PersonalWorkspace.class_course_id == c.id)).first()
        result.append({**c.model_dump(), "teacher_name": teacher.name if teacher else "",
                       "is_personal": personal is not None, "invite_code": "" if personal else c.invite_code})
    return result


@router.get("/{class_course_id}/stats", response_model=CourseWorkspaceStats)
def course_workspace_stats(
    class_course_id: int,
    user_id: int,
    response: Response,
    db: Session = Depends(get_db),
    user: User = Depends(current_user),
):
    """课程工作台统计；所有数据严格限定在当前课程数据域。"""
    response.headers["Cache-Control"] = "no-store"
    same_user(user, user_id)
    cc = db.get(ClassCourse, class_course_id)
    if not cc:
        raise HTTPException(404, "课程不存在")
    membership = db.exec(
        select(Membership).where(
            Membership.class_course_id == class_course_id,
            Membership.user_id == user_id,
        )
    ).first()
    if not membership:
        raise HTTPException(403, "尚未加入该课程")

    official_lesson_count = db.exec(
        select(func.count(func.distinct(CourseSession.id)))
        .join(Outline, Outline.session_id == CourseSession.id)
        .where(
            CourseSession.class_course_id == class_course_id,
            Outline.class_course_id == class_course_id,
            Outline.owner_id == -1,
            Outline.status == "published",
        )
    ).one()
    personal_note_count = db.exec(
        select(func.count(Note.id)).where(
            Note.class_course_id == class_course_id,
            Note.owner_id == user_id,
        )
    ).one()
    class_note_count = db.exec(
        select(func.count(Note.id)).where(
            Note.class_course_id == class_course_id,
            Note.visibility == "shared",
        )
    ).one()

    return CourseWorkspaceStats(
        class_course_id=class_course_id,
        official_lesson_count=int(official_lesson_count or 0),
        personal_note_count=int(personal_note_count or 0),
        class_note_count=int(class_note_count or 0),
    )


@router.post("")
def create_course(body: CreateCourse, db: Session = Depends(get_db), user: User = Depends(current_user)):
    same_user(user, body.teacher_id)
    teacher = db.get(User, body.teacher_id)
    if not teacher or teacher.role != "teacher":
        raise HTTPException(403, "仅教师可创建课程集合")
    if not body.schedule.slots:
        raise HTTPException(422, "请至少安排一个上课时段")
    with write_lock:
        for _ in range(100):
            code = "".join(secrets.choice(string.digits) for _ in range(6))
            if not db.exec(select(ClassCourse).where(ClassCourse.invite_code == code)).first():
                break
        else:
            raise HTTPException(503, "邀请码生成失败，请重试")
        cc = ClassCourse(name=body.name, class_name=body.class_name, teacher_id=body.teacher_id, invite_code=code)
        db.add(cc)
        db.flush()
        db.add(Membership(user_id=body.teacher_id, class_course_id=cc.id))
        replace_schedule(db, cc, body.schedule)
        db.commit()
    db.refresh(cc)
    return cc


@router.get("/{class_course_id}/schedule")
def get_course_schedule(class_course_id: int, response: Response,
                        db: Session = Depends(get_db), user: User = Depends(current_user)):
    member(db, user, class_course_id)
    response.headers["Cache-Control"] = "no-store"
    return read_schedule(db, class_course_id)


@router.put("/{class_course_id}/schedule")
def update_course_schedule(class_course_id: int, body: ScheduleBody,
                           db: Session = Depends(get_db), user: User = Depends(current_user)):
    with write_lock:
        course = schedule_teacher(db, user, class_course_id)
        replace_schedule(db, course, body)
        db.commit()
        return read_schedule(db, class_course_id)


@router.post("/join")
def join_course(body: JoinCourse, db: Session = Depends(get_db), user: User = Depends(current_user)):
    same_user(user, body.user_id)
    cc = db.exec(select(ClassCourse).where(ClassCourse.invite_code == body.invite_code)).first()
    if not cc or db.exec(select(PersonalWorkspace).where(PersonalWorkspace.class_course_id == cc.id)).first():
        raise HTTPException(404, "邀请码无效")
    exists = db.exec(
        select(Membership).where(Membership.user_id == body.user_id, Membership.class_course_id == cc.id)
    ).first()
    if not exists:
        db.add(Membership(user_id=body.user_id, class_course_id=cc.id))
        db.commit()
        db.refresh(cc)
    return cc
