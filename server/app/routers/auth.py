from fastapi import APIRouter, Depends
from sqlmodel import Session, select

from ..db import get_db
from ..models import User

router = APIRouter(prefix="/auth", tags=["auth"])


@router.get("/users")
def list_users(db: Session = Depends(get_db)):
    """Demo 预置账号列表，客户端选择身份直接登录"""
    return db.exec(select(User)).all()
