import random
import string

from fastapi import APIRouter, Depends, HTTPException
from pydantic import BaseModel
from sqlmodel import Session, select

from ..db import get_db
from ..models import ClassCourse, Membership, User

router = APIRouter(prefix="/courses", tags=["courses"])


class CreateCourse(BaseModel):
    name: str
    class_name: str
    teacher_id: int


class JoinCourse(BaseModel):
    user_id: int
    invite_code: str


@router.get("")
def list_courses(user_id: int, db: Session = Depends(get_db)):
    """用户已加入的课程集合"""
    mids = db.exec(select(Membership.class_course_id).where(Membership.user_id == user_id)).all()
    if not mids:
        return []
    courses = db.exec(select(ClassCourse).where(ClassCourse.id.in_(mids))).all()
    result = []
    for c in courses:
        teacher = db.get(User, c.teacher_id)
        result.append({**c.model_dump(), "teacher_name": teacher.name if teacher else ""})
    return result


@router.post("")
def create_course(body: CreateCourse, db: Session = Depends(get_db)):
    teacher = db.get(User, body.teacher_id)
    if not teacher or teacher.role != "teacher":
        raise HTTPException(403, "仅教师可创建课程集合")
    code = "".join(random.choices(string.digits, k=6))
    cc = ClassCourse(name=body.name, class_name=body.class_name, teacher_id=body.teacher_id, invite_code=code)
    db.add(cc)
    db.commit()
    db.refresh(cc)
    db.add(Membership(user_id=body.teacher_id, class_course_id=cc.id))
    db.commit()
    db.refresh(cc)
    return cc


@router.post("/join")
def join_course(body: JoinCourse, db: Session = Depends(get_db)):
    cc = db.exec(select(ClassCourse).where(ClassCourse.invite_code == body.invite_code)).first()
    if not cc:
        raise HTTPException(404, "邀请码无效")
    exists = db.exec(
        select(Membership).where(Membership.user_id == body.user_id, Membership.class_course_id == cc.id)
    ).first()
    if not exists:
        db.add(Membership(user_id=body.user_id, class_course_id=cc.id))
        db.commit()
        db.refresh(cc)
    return cc
