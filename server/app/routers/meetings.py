from datetime import datetime

from fastapi import APIRouter, Depends, HTTPException, Query
from fastapi.responses import Response
from pydantic import BaseModel, Field
from sqlmodel import Session, select

from ..db import get_db, write_lock
from ..models import MeetingExclusion, MeetingMember, MeetingMessage, MeetingRoom, Membership, User
from ..services.security import current_user, member, is_manager
from ..services import meetings

router = APIRouter(prefix="/meetings", tags=["meetings"])


class CreateRoom(BaseModel):
    class_course_id: int
    name: str = Field(min_length=1, max_length=80)
    participant_limit: int = Field(default=20, ge=2, le=200)


class SettingsBody(BaseModel):
    participant_limit: int = Field(ge=2, le=200)
    enabled: bool


class SendBody(BaseModel):
    content: str = Field(min_length=1, max_length=4000)
    immediate: bool = False


class MemberBody(BaseModel):
    user_id: int


def access(db: Session, user: User, room_id: int, manage=False, joined=True):
    room = db.get(MeetingRoom, room_id)
    if not room:
        raise HTTPException(404, "聊天室不存在")
    course = member(db, user, room.class_course_id)
    if manage and room.creator_id != user.id and not is_manager(db, user, course):
        raise HTTPException(403, "仅创建者或课程管理员可设置会议")
    if joined and not db.get(MeetingMember, (room.id, user.id)) and not (
            manage and (room.creator_id == user.id or is_manager(db, user, course))):
        raise HTTPException(403, "请先加入聊天室")
    return room


@router.get("")
def list_rooms(class_course_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    member(db, user, class_course_id)
    return [{**room.model_dump(exclude={"minutes"}),
             "joined": db.get(MeetingMember, (room.id, user.id)) is not None}
            for room in db.exec(select(MeetingRoom).where(MeetingRoom.class_course_id == class_course_id)).all()]


@router.post("")
def create(body: CreateRoom, db: Session = Depends(get_db), user: User = Depends(current_user)):
    member(db, user, body.class_course_id)
    room = MeetingRoom(**body.model_dump(), creator_id=user.id)
    db.add(room)
    db.flush()
    db.add(MeetingMember(room_id=room.id, user_id=user.id))
    db.commit()
    db.refresh(room)
    return room


@router.post("/{room_id}/join")
def join(room_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    with write_lock:
        room = access(db, user, room_id, joined=False)
        if not db.get(MeetingMember, (room_id, user.id)):
            if room.status != "active":
                raise HTTPException(409, "会议已关闭，不能加入")
            if db.get(MeetingExclusion, (room_id, user.id)):
                raise HTTPException(403, "你已被移出会议，请联系管理员重新邀请")
            count = len(db.exec(select(MeetingMember).where(MeetingMember.room_id == room_id)).all())
            if count >= room.participant_limit:
                raise HTTPException(409, "聊天室人数已满")
            db.add(MeetingMember(room_id=room_id, user_id=user.id))
            db.commit()
    return {"ok": True}


@router.get("/{room_id}/members")
def members(room_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    room = access(db, user, room_id, manage=True, joined=False)
    participants = set(db.exec(select(MeetingMember.user_id).where(MeetingMember.room_id == room_id)).all())
    excluded = set(db.exec(select(MeetingExclusion.user_id).where(MeetingExclusion.room_id == room_id)).all())
    people = db.exec(select(User).join(Membership, Membership.user_id == User.id)
                     .where(Membership.class_course_id == room.class_course_id)).all()
    return [{"id": person.id, "name": person.name, "role": person.role,
             "joined": person.id in participants, "removed": person.id in excluded}
            for person in people]


@router.post("/{room_id}/members")
def add_member(room_id: int, body: MemberBody, db: Session = Depends(get_db), user: User = Depends(current_user)):
    with write_lock:
        room = access(db, user, room_id, manage=True, joined=False)
        if room.status != "active":
            raise HTTPException(409, "会议已关闭，不能添加成员")
        person = db.get(User, body.user_id)
        if not person:
            raise HTTPException(404, "用户不存在")
        member(db, person, room.class_course_id)
        if not db.get(MeetingMember, (room_id, person.id)):
            count = len(db.exec(select(MeetingMember).where(MeetingMember.room_id == room_id)).all())
            if count >= room.participant_limit:
                raise HTTPException(409, "聊天室人数已满")
            db.add(MeetingMember(room_id=room_id, user_id=person.id))
        exclusion = db.get(MeetingExclusion, (room_id, person.id))
        if exclusion:
            db.delete(exclusion)
        db.commit()
    return {"ok": True}


@router.delete("/{room_id}/members/{user_id}")
def remove_member(room_id: int, user_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    with write_lock:
        room = access(db, user, room_id, manage=True, joined=False)
        course = member(db, user, room.class_course_id)
        if room.status != "active":
            raise HTTPException(409, "会议已关闭，不能移除成员")
        if user_id in (room.creator_id, course.teacher_id, user.id):
            raise HTTPException(409, "不能移除主持人、课程管理员或自己")
        participant = db.get(MeetingMember, (room_id, user_id))
        if not participant:
            raise HTTPException(404, "成员已不在会议中")
        db.delete(participant)
        if not db.get(MeetingExclusion, (room_id, user_id)):
            db.add(MeetingExclusion(room_id=room_id, user_id=user_id))
        db.commit()
    return {"ok": True}


@router.post("/{room_id}/leave")
def leave(room_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    with write_lock:
        room = access(db, user, room_id, joined=False)
        if room.creator_id == user.id and room.status != "ended":
            raise HTTPException(409, "主持人请先转交主持权或结束会议")
        participant = db.get(MeetingMember, (room_id, user.id))
        if participant:
            db.delete(participant)
            db.commit()
    return {"ok": True}


@router.post("/{room_id}/owner")
def transfer_owner(room_id: int, body: MemberBody, db: Session = Depends(get_db), user: User = Depends(current_user)):
    with write_lock:
        room = access(db, user, room_id, manage=True, joined=False)
        if room.status != "active":
            raise HTTPException(409, "会议已关闭，不能转交主持权")
        person = db.get(User, body.user_id)
        if not person or not db.get(MeetingMember, (room_id, body.user_id)):
            raise HTTPException(409, "新主持人必须是当前会议成员")
        member(db, person, room.class_course_id)
        room.creator_id = body.user_id
        db.commit()
    return {"ok": True}


@router.get("/{room_id}")
def detail(room_id: int, after: int = Query(default=0, ge=0), db: Session = Depends(get_db),
           user: User = Depends(current_user)):
    room = access(db, user, room_id)
    participants = db.exec(select(User).join(MeetingMember, MeetingMember.user_id == User.id)
                           .where(MeetingMember.room_id == room_id)).all()
    messages = db.exec(select(MeetingMessage).where(MeetingMessage.room_id == room_id, MeetingMessage.id > after)
                       .order_by(MeetingMessage.id).limit(100)).all()
    return {"room": room, "members": participants, "messages": messages,
            "cursor": messages[-1].id if messages else after}


@router.get("/{room_id}/minutes/export")
def export_minutes(room_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    room = access(db, user, room_id)
    if not room.minutes.strip(): raise HTTPException(409, "暂无可导出的会议纪要")
    content = f"# {room.name}\n\n创建时间：{room.created_at.isoformat()}\n\n状态：{room.status}\n\n{room.minutes.strip()}\n"
    return Response(content, media_type="text/markdown; charset=utf-8",
                    headers={"Content-Disposition": f'attachment; filename="meeting-{room.id}.md"'})


@router.post("/{room_id}/messages")
async def send(room_id: int, body: SendBody, db: Session = Depends(get_db), user: User = Depends(current_user)):
    with write_lock:
        room = access(db, user, room_id)
        if room.status != "active":
            raise HTTPException(409, "会议已结束")
        if not body.content.strip():
            raise HTTPException(422, "消息不能为空")
        message = MeetingMessage(room_id=room_id, sender_id=user.id, sender_name=user.name, content=body.content)
        db.add(message)
        room.last_activity, room.idle_prompted = datetime.utcnow(), False
        db.commit()
        db.refresh(message)
        result = message.model_dump()
    if body.immediate or "@" in body.content:
        try:
            await meetings.process(room_id, force=True)
        except Exception:
            # The human message is already durable: report success so clients do not duplicate it.
            pass
    return result


@router.put("/{room_id}")
def configure(room_id: int, body: SettingsBody, db: Session = Depends(get_db), user: User = Depends(current_user)):
    with write_lock:
        room = access(db, user, room_id, manage=True)
        count = len(db.exec(select(MeetingMember).where(MeetingMember.room_id == room_id)).all())
        if body.participant_limit < count:
            raise HTTPException(409, "人数上限不能低于当前人数")
        room.participant_limit, room.enabled = body.participant_limit, body.enabled
        db.commit()
        db.refresh(room)
    return room


@router.post("/{room_id}/end")
async def end(room_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    with write_lock:
        room = access(db, user, room_id, manage=True)
        if room.status == "ended":
            return room
        room.status = "ending"
        db.commit()
    try:
        # Close admission first so a busy room can drain to a stable final cursor.
        while True:
            await meetings.process(room_id, force=True, ending=True)
            db.expire_all()
            if db.get(MeetingRoom, room_id).status == "ended":
                break
    except Exception as exc:
        raise HTTPException(502, "纪要生成失败，会议和待处理消息已保留，请重试") from exc
    db.expire_all()
    return db.get(MeetingRoom, room_id)
