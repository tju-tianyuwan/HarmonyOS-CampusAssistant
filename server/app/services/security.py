"""Password hashing, bearer sessions, and resource authorization."""
import hashlib
import hmac
import secrets
from datetime import datetime

from fastapi import Depends, HTTPException
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlmodel import Session, select

from ..db import get_db
from ..models import AuthSession, ClassCourse, Membership, PersonalWorkspace, User

bearer = HTTPBearer(auto_error=False)


def hash_password(value: str) -> str:
    salt = secrets.token_hex(16)
    digest = hashlib.pbkdf2_hmac("sha256", value.encode(), salt.encode(), 600000).hex()
    return f"{salt}:{digest}"


def verify_password(value: str, stored: str) -> bool:
    try:
        salt, expected = stored.split(":")
        actual = hashlib.pbkdf2_hmac("sha256", value.encode(), salt.encode(), 600000).hex()
        return hmac.compare_digest(actual, expected)
    except (ValueError, TypeError):
        return False


def token_hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def current_user(credentials: HTTPAuthorizationCredentials | None = Depends(bearer),
                 db: Session = Depends(get_db)) -> User:
    session = db.get(AuthSession, token_hash(credentials.credentials)) if credentials else None
    user = db.get(User, session.user_id) if session and session.expires_at > datetime.utcnow() else None
    if user is None:
        raise HTTPException(401, "请登录或重新登录", headers={"WWW-Authenticate": "Bearer"})
    return user


def same_user(user: User, requested: int | None) -> int:
    if requested is not None and requested != user.id:
        raise HTTPException(403, "不能以其他用户身份操作")
    return user.id


def member(db: Session, user: User, course_id: int) -> ClassCourse:
    course = db.get(ClassCourse, course_id)
    if course is None:
        raise HTTPException(404, "课程不存在")
    if db.exec(select(Membership).where(Membership.class_course_id == course_id,
                                       Membership.user_id == user.id)).first() is None:
        raise HTTPException(403, "尚未加入该课程")
    return course


def is_manager(db: Session, user: User, course: ClassCourse) -> bool:
    workspace = db.get(PersonalWorkspace, user.id)
    return (course.teacher_id == user.id and user.role == "teacher") or (
        workspace is not None and workspace.class_course_id == course.id)


def manager(db: Session, user: User, course_id: int) -> ClassCourse:
    course = member(db, user, course_id)
    if not is_manager(db, user, course):
        raise HTTPException(403, "仅本课程教师或私人空间所有者可操作")
    return course
