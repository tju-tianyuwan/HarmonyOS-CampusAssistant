import json
import re
import secrets
import smtplib
import unicodedata
from datetime import datetime, timedelta
from email.message import EmailMessage
from typing import Literal

from fastapi import APIRouter, Depends, HTTPException, Request
from pydantic import BaseModel, Field
from sqlalchemy.exc import IntegrityError
from sqlmodel import Session, select

from ..config import settings
from ..db import get_db, write_lock
from ..models import Account, AccountCode, AuthRateLimit, AuthSession, ClassCourse, EmailCode, Membership, PersonalWorkspace, User
from ..services.security import bearer, current_user, hash_password, token_hash, verify_password

router = APIRouter(prefix="/auth", tags=["auth"])
DUMMY_HASH = hash_password("invalid-account-password")


class Identity(BaseModel):
    account_type: Literal["personal", "school"] = "personal"
    email: str = Field(default="", max_length=254)
    school_name: str = Field(default="", max_length=100)
    student_number: str = Field(default="", max_length=40)


class Credentials(Identity):
    password: str = Field(min_length=1, max_length=128)


class Registration(Credentials):
    name: str = Field(min_length=1, max_length=40)
    password: str = Field(min_length=8, max_length=128)
    code: str = Field(default="", max_length=6)
    role: Literal["teacher", "student"] = "student"


class CodeRequest(BaseModel):
    email: str = Field(max_length=254)


def email_address(value: str) -> str:
    value = value.strip().casefold()
    if not re.fullmatch(r"[^\s@]+@[^\s@]+\.[^\s@]+", value) or "\r" in value or "\n" in value:
        raise HTTPException(422, "请输入有效邮箱")
    return value


def identity(body: Identity) -> str:
    if body.account_type == "personal":
        return "email:" + email_address(body.email)
    school = unicodedata.normalize("NFKC", body.school_name).strip().casefold()
    number = unicodedata.normalize("NFKC", body.student_number).strip().casefold()
    if len(school) < 2 or len(number) < 2:
        raise HTTPException(422, "请输入学校名称和学号")
    return "school:" + json.dumps([school, number], ensure_ascii=False)


def throttle(db: Session, key: str, limit: int, seconds: int) -> None:
    with write_lock:
        now = datetime.utcnow()
        row = db.get(AuthRateLimit, key)
        if row is None:
            row = AuthRateLimit(key=key, expires_at=now + timedelta(seconds=seconds))
        if row.expires_at <= now:
            row.count = 0
            row.expires_at = now + timedelta(seconds=seconds)
        if row.count >= limit:
            raise HTTPException(429, "操作过于频繁，请稍后再试", headers={"Retry-After": str(seconds)})
        row.count += 1
        db.add(row)
        db.commit()


def public_user(db: Session, user: User) -> dict:
    account = db.exec(select(Account).where(Account.user_id == user.id)).first()
    workspace = db.get(PersonalWorkspace, user.id)
    return {**user.model_dump(), "account_type": account.account_type if account else "legacy",
            "email": account.email if account else "", "school_name": account.school_name if account else "",
            "student_number": account.student_number if account else "",
            "school_verification_status": account.verification_status if account else "pending",
            "personal_workspace_id": workspace.class_course_id if workspace else None}


def issue_session(db: Session, user: User) -> dict:
    token = secrets.token_urlsafe(32)
    seconds = settings.auth_session_hours * 3600
    db.add(AuthSession(token_hash=token_hash(token), user_id=user.id,
                       expires_at=datetime.utcnow() + timedelta(seconds=seconds)))
    db.commit()
    return {"access_token": token, "token_type": "bearer", "expires_in": seconds, "user": public_user(db, user)}


@router.post("/verification-code")
def send_code(body: CodeRequest, request: Request, db: Session = Depends(get_db)):
    email = email_address(body.email)
    if not settings.smtp_host or not settings.smtp_from_email:
        raise HTTPException(503, "服务器尚未配置验证码邮件服务")
    throttle(db, "email:" + email, 5, 3600)
    throttle(db, "mail-ip:" + request.client.host, 30, 3600)
    with write_lock:
        old = db.get(EmailCode, email)
        now = datetime.utcnow()
        if old and (now - old.sent_at).total_seconds() < 60:
            raise HTTPException(429, "请等待 60 秒再发送验证码")
        code = f"{secrets.randbelow(1000000):06d}"
        mail = EmailMessage()
        mail["From"], mail["To"], mail["Subject"] = settings.smtp_from_email, email, "智伴注册验证码"
        mail.set_content(f"注册验证码：{code}，10 分钟内有效。")
        try:
            factory = smtplib.SMTP_SSL if settings.smtp_ssl else smtplib.SMTP
            with factory(settings.smtp_host, settings.smtp_port, timeout=10) as smtp:
                if settings.smtp_starttls and not settings.smtp_ssl:
                    smtp.starttls()
                if settings.smtp_username:
                    smtp.login(settings.smtp_username, settings.smtp_password)
                smtp.send_message(mail)
        except (OSError, smtplib.SMTPException) as exc:
            raise HTTPException(502, "验证码邮件发送失败，请稍后重试") from exc
        row = old or EmailCode(email=email, code_hash="", expires_at=now)
        row.code_hash, row.expires_at, row.sent_at, row.attempts = hash_password(code), now + timedelta(minutes=10), now, 0
        db.add(row)
        db.commit()
    return {"message": "验证码已发送", "expires_in": 600, "retry_after": 60}


@router.post("/register")
def register(body: Registration, request: Request, db: Session = Depends(get_db)):
    key = identity(body)
    if not body.name.strip():
        raise HTTPException(422, "请输入姓名")
    throttle(db, "register:" + request.client.host, 20, 3600)
    with write_lock:
        if db.exec(select(Account).where(Account.login_key == key)).first():
            raise HTTPException(409, "账号已存在")
        if body.account_type == "personal":
            code = db.get(EmailCode, email_address(body.email))
            if not code or code.expires_at <= datetime.utcnow() or code.attempts >= 5:
                raise HTTPException(400, "验证码无效或已过期")
            if not verify_password(body.code, code.code_hash):
                code.attempts += 1
                db.commit()
                raise HTTPException(400, "验证码错误")
            db.delete(code)
        user = User(name=body.name.strip(), role=body.role)
        db.add(user)
        db.flush()
        db.add(Account(user_id=user.id, login_key=key, password_hash=hash_password(body.password),
                       account_type=body.account_type, email=email_address(body.email) if body.account_type == "personal" else "",
                       school_name=body.school_name.strip(), student_number=body.student_number.strip()))
        if body.account_type == "personal":
            course = ClassCourse(name="我的知识空间", class_name="个人空间", teacher_id=user.id,
                                 invite_code="P-" + secrets.token_hex(16))
            db.add(course)
            db.flush()
            db.add(PersonalWorkspace(user_id=user.id, class_course_id=course.id))
            db.add(Membership(user_id=user.id, class_course_id=course.id))
        try:
            db.commit()
        except IntegrityError as exc:
            db.rollback()
            raise HTTPException(409, "账号已存在") from exc
        return issue_session(db, user)


@router.post("/login")
def login(body: Credentials, request: Request, db: Session = Depends(get_db)):
    key = identity(body)
    throttle(db, "login:" + request.client.host, 60, 300)
    throttle(db, "login-account:" + token_hash(key), 20, 300)
    with write_lock:
        account = db.exec(select(Account).where(Account.login_key == key)).first()
        valid = verify_password(body.password, account.password_hash if account else DUMMY_HASH)
        if not account or not valid:
            raise HTTPException(401, "账号或密码错误")
        return issue_session(db, db.get(User, account.user_id))


@router.get("/me")
def me(user: User = Depends(current_user), db: Session = Depends(get_db)):
    return public_user(db, user)


@router.get("/users")
def list_users(user: User = Depends(current_user), db: Session = Depends(get_db)):
    return [public_user(db, user)]


@router.post("/logout")
def logout(user: User = Depends(current_user), credentials=Depends(bearer), db: Session = Depends(get_db)):
    row = db.get(AuthSession, token_hash(credentials.credentials))
    if row:
        db.delete(row)
        db.commit()
    return {"ok": True}


class ResetPassword(Identity):
    code: str = Field(pattern=r"^\d{6}$")
    new_password: str = Field(min_length=8, max_length=128)


class ChangePassword(BaseModel):
    current_password: str = Field(min_length=1, max_length=128)
    new_password: str = Field(min_length=8, max_length=128)


class RecoveryEmail(BaseModel):
    email: str = Field(max_length=254)
    current_password: str = Field(min_length=1, max_length=128)


class ConfirmRecoveryEmail(RecoveryEmail):
    code: str = Field(pattern=r"^\d{6}$")


def account_for(db, user):
    account = db.exec(select(Account).where(Account.user_id == user.id)).first()
    if not account:
        raise HTTPException(409, "请先由管理员绑定登录账号")
    return account


def deliver_account_code(email, code, purpose):
    if not settings.smtp_host or not settings.smtp_from_email:
        raise HTTPException(503, "服务器尚未配置验证码邮件服务")
    label = "重置密码" if purpose == "reset" else "绑定找回邮箱"
    mail = EmailMessage()
    mail["From"], mail["To"], mail["Subject"] = settings.smtp_from_email, email, f"智伴{label}验证码"
    mail.set_content(f"{label}验证码：{code}，10 分钟内有效。如非本人操作，请忽略。")
    try:
        factory = smtplib.SMTP_SSL if settings.smtp_ssl else smtplib.SMTP
        with factory(settings.smtp_host, settings.smtp_port, timeout=10) as smtp:
            if settings.smtp_starttls and not settings.smtp_ssl:
                smtp.starttls()
            if settings.smtp_username:
                smtp.login(settings.smtp_username, settings.smtp_password)
            smtp.send_message(mail)
    except (OSError, smtplib.SMTPException) as exc:
        raise HTTPException(502, "验证码邮件发送失败，请稍后重试") from exc


def make_account_code(db, account, email, purpose):
    key = f"{purpose}:{account.user_id}"
    old = db.get(AccountCode, key)
    now = datetime.utcnow()
    if old and (now - old.sent_at).total_seconds() < 60:
        raise HTTPException(429, "请等待 60 秒再发送验证码")
    code = f"{secrets.randbelow(1000000):06d}"
    deliver_account_code(email, code, purpose)
    row = old or AccountCode(key=key, user_id=account.user_id, email=email, purpose=purpose,
                              code_hash="", credential_version="", expires_at=now)
    row.email, row.code_hash = email, hash_password(code)
    row.credential_version = token_hash(account.password_hash)
    row.sent_at, row.expires_at, row.attempts = now, now + timedelta(minutes=10), 0
    db.add(row)
    db.commit()


def consume_account_code(db, account, code, purpose, email):
    row = db.get(AccountCode, f"{purpose}:{account.user_id}") if account else None
    valid = row and row.email == email and row.expires_at > datetime.utcnow() and row.attempts < 5
    if not valid or row.credential_version != token_hash(account.password_hash):
        raise HTTPException(400, "验证码无效或已过期")
    if not verify_password(code, row.code_hash):
        row.attempts += 1
        db.commit()
        raise HTTPException(400, "验证码无效或已过期")
    db.delete(row)


def revoke_account_access(db, account):
    for row in db.exec(select(AuthSession).where(AuthSession.user_id == account.user_id)).all():
        db.delete(row)
    for row in db.exec(select(AccountCode).where(AccountCode.user_id == account.user_id)).all():
        db.delete(row)


@router.post("/password-reset/code")
def reset_code(body: Identity, request: Request, db: Session = Depends(get_db)):
    key = identity(body)
    throttle(db, "reset-ip:" + request.client.host, 20, 3600)
    throttle(db, "reset-account:" + token_hash(key), 5, 3600)
    with write_lock:
        account = db.exec(select(Account).where(Account.login_key == key)).first()
        if account and account.email:
            make_account_code(db, account, account.email, "reset")
    return {"message": "若账号已绑定邮箱，验证码将发送到该邮箱", "retry_after": 60}


@router.post("/password-reset")
def reset_password(body: ResetPassword, request: Request, db: Session = Depends(get_db)):
    key = identity(body)
    throttle(db, "reset-confirm:" + request.client.host, 30, 300)
    with write_lock:
        account = db.exec(select(Account).where(Account.login_key == key)).first()
        consume_account_code(db, account, body.code, "reset", account.email if account else "")
        account.password_hash = hash_password(body.new_password)
        revoke_account_access(db, account)
        db.commit()
    return {"message": "密码已重置，请重新登录"}


@router.post("/password")
def change_password(body: ChangePassword, db: Session = Depends(get_db), user: User = Depends(current_user)):
    throttle(db, f"password:{user.id}", 10, 300)
    with write_lock:
        account = account_for(db, user)
        if not verify_password(body.current_password, account.password_hash):
            raise HTTPException(400, "当前密码不正确")
        if body.current_password == body.new_password:
            raise HTTPException(422, "新密码不能与当前密码相同")
        account.password_hash = hash_password(body.new_password)
        revoke_account_access(db, account)
        db.commit()
    return {"message": "密码已修改，所有设备需重新登录"}


@router.post("/recovery-email/code")
def recovery_email_code(body: RecoveryEmail, db: Session = Depends(get_db), user: User = Depends(current_user)):
    email = email_address(body.email)
    throttle(db, f"bind-email:{user.id}", 5, 3600)
    throttle(db, "bind-destination:" + token_hash(email), 5, 3600)
    with write_lock:
        account = account_for(db, user)
        if account.account_type != "school":
            raise HTTPException(409, "个人账号使用注册邮箱找回密码")
        if not verify_password(body.current_password, account.password_hash):
            raise HTTPException(400, "当前密码不正确")
        make_account_code(db, account, email, "bind")
    return {"message": "验证码已发送", "retry_after": 60}


@router.post("/recovery-email")
def confirm_recovery_email(body: ConfirmRecoveryEmail, db: Session = Depends(get_db), user: User = Depends(current_user)):
    email = email_address(body.email)
    throttle(db, f"bind-confirm:{user.id}", 10, 300)
    with write_lock:
        account = account_for(db, user)
        if account.account_type != "school" or not verify_password(body.current_password, account.password_hash):
            raise HTTPException(400, "账号类型或当前密码不正确")
        consume_account_code(db, account, body.code, "bind", email)
        account.email = email
        stale = db.get(AccountCode, f"reset:{user.id}")
        if stale:
            db.delete(stale)
        db.commit()
    return public_user(db, user)
