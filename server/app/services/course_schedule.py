from datetime import date, timedelta
from typing import Literal

from fastapi import HTTPException
from pydantic import BaseModel, Field, model_validator
from sqlmodel import select

from ..models import ClassCourse, CourseSchedule, PersonalWorkspace
from .security import member


class ScheduleSlot(BaseModel):
    weekday: int = Field(ge=1, le=7)
    start_section: int = Field(ge=1, le=12)
    end_section: int = Field(ge=1, le=12)
    start_week: int = Field(default=1, ge=1, le=30)
    end_week: int = Field(default=20, ge=1, le=30)
    week_type: Literal["all", "odd", "even"] = "all"
    location: str = Field(default="", max_length=100)

    @model_validator(mode="after")
    def validate_range(self):
        if self.start_section > self.end_section or self.start_week > self.end_week:
            raise ValueError("结束节次和周次不能早于开始")
        if not active_weeks(self):
            raise ValueError("所选周次范围内没有符合单双周的上课日期")
        self.location = self.location.strip()
        return self


class ScheduleBody(BaseModel):
    semester_start: date
    slots: list[ScheduleSlot] = Field(max_length=40)

    @model_validator(mode="after")
    def validate_start(self):
        if self.semester_start.weekday() != 0:
            raise ValueError("学期第 1 周必须从周一开始")
        return self


def default_start():
    today = date.today()
    return today - timedelta(days=today.weekday())


def active_weeks(slot):
    return {week for week in range(slot.start_week, slot.end_week + 1)
            if slot.week_type == "all" or week % 2 == (1 if slot.week_type == "odd" else 0)}


def active_dates(slot):
    return {slot.semester_start + timedelta(weeks=week - 1, days=slot.weekday - 1)
            for week in active_weeks(slot)}


def overlaps(left, right):
    return (left.weekday == right.weekday
            and left.start_section <= right.end_section
            and right.start_section <= left.end_section
            and bool(active_dates(left) & active_dates(right)))


def schedule_teacher(db, user, course_id):
    course = member(db, user, course_id)
    personal = db.exec(select(PersonalWorkspace).where(PersonalWorkspace.class_course_id == course_id)).first()
    if user.role != "teacher" or course.teacher_id != user.id or personal:
        raise HTTPException(403, "仅本课程教师可安排上课时间")
    return course


def replace_schedule(db, course, body):
    rows = [CourseSchedule(class_course_id=course.id, semester_start=body.semester_start,
                           **slot.model_dump()) for slot in body.slots]
    others = db.exec(select(CourseSchedule).join(ClassCourse).where(
        ClassCourse.teacher_id == course.teacher_id, ClassCourse.id != course.id)).all()
    for index, row in enumerate(rows):
        if any(overlaps(row, other) for other in rows[:index]):
            raise HTTPException(409, "本课程的上课时间重复，请调整节次或周次")
        if any(overlaps(row, other) for other in others):
            raise HTTPException(409, "与您其他课程的上课时间冲突，请调整节次或周次")
    # Validate the entire replacement before touching the published schedule.
    for old in db.exec(select(CourseSchedule).where(CourseSchedule.class_course_id == course.id)).all():
        db.delete(old)
    db.flush()
    db.add_all(rows)


def read_schedule(db, course_id):
    rows = db.exec(select(CourseSchedule).where(CourseSchedule.class_course_id == course_id)
                   .order_by(CourseSchedule.weekday, CourseSchedule.start_section, CourseSchedule.id)).all()
    return {"semester_start": rows[0].semester_start if rows else default_start(),
            "slots": [ScheduleSlot.model_validate(row, from_attributes=True) for row in rows]}
