import os

from fastapi import FastAPI
from fastapi.middleware.cors import CORSMiddleware
from sqlmodel import Session, select

from .config import settings
from .db import engine, init_db
from .models import ClassCourse, CourseSession, Membership, Note, TranscriptSegment, User
from .routers import auth, chat, courses, notes, sessions

app = FastAPI(title="智慧伴学 Demo API")
app.add_middleware(
    CORSMiddleware, allow_origins=["*"], allow_methods=["*"], allow_headers=["*"]
)

for r in (auth.router, courses.router, sessions.router, notes.router, chat.router):
    app.include_router(r, prefix="/api/v1")


@app.get("/health")
def health():
    return {"ok": True, "asr_provider": settings.asr_provider, "llm_configured": bool(settings.llm_api_key)}


def seed():
    """Demo 预置数据：1 教师 + 2 学生 + 1 示例集合 + 1 节已转写课时"""
    with Session(engine) as db:
        if db.exec(select(User)).first():
            return
        teacher = User(name="王老师", role="teacher")
        s1 = User(name="小明", role="student")
        s2 = User(name="小红", role="student")
        db.add_all([teacher, s1, s2])
        db.commit()
        cc = ClassCourse(name="数据结构", class_name="计科2301", teacher_id=teacher.id, invite_code="888888")
        db.add(cc)
        db.commit()
        db.add_all([Membership(user_id=u.id, class_course_id=cc.id) for u in (teacher, s1, s2)])
        cs = CourseSession(class_course_id=cc.id, title="第5讲 二叉树", creator_id=teacher.id, status="done")
        db.add(cs)
        db.commit()
        demo_texts = [
            "同学们好，今天我们学习数据结构中的二叉树。",
            "二叉树是每个节点最多有两个子节点的树形结构，分别称为左子树和右子树。",
            "二叉树的遍历方式主要有三种：前序遍历、中序遍历和后序遍历。",
            "中序遍历的顺序是：左子树、根节点、右子树，对二叉搜索树进行中序遍历可以得到有序序列。",
            "大家注意，三种遍历的递归与非递归实现是期末考试的重点内容。",
        ]
        for i, t in enumerate(demo_texts):
            db.add(TranscriptSegment(session_id=cs.id, seq=i, start_ms=i * 60000, end_ms=(i + 1) * 60000, text=t))
        db.add(
            Note(
                class_course_id=cc.id, owner_id=s1.id, title="二叉树遍历笔记", kind="md",
                content="# 二叉树遍历\n- 前序：根左右\n- 中序：左根右\n- 后序：左右根",
            )
        )
        db.commit()


@app.on_event("startup")
def on_startup():
    os.makedirs(settings.data_dir, exist_ok=True)
    init_db()
    seed()
