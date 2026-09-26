"""Durable message cursor: agent replies and minutes commit together before advancing."""
import asyncio
import json
import logging
from datetime import datetime

from sqlmodel import Session, select
from starlette.concurrency import run_in_threadpool

from ..config import settings
from ..db import engine, write_lock
from ..models import MeetingMessage, MeetingRoom
from . import rag
from .llm import chat
from .mas import MAS_AGENTS, build_agent_system, build_agent_user
from .locking import async_process_lock

locks: dict[int, asyncio.Lock] = {}
logger = logging.getLogger(__name__)

DISPATCH_SYSTEM = """[MEETING_DISPATCHER]
你负责协调 AI学习小组的学习讨论。根据小组成员的最新发言，从下列角色中选择最适合回复的一至两个角色：
- analyst：组员A，学习引导者，负责引导提问、推进理解和梳理重点
- skeptic：组员B，智多星/思辨者，负责严谨推导和答疑
- connector：组员C，学习者/提问者，负责暴露基础疑问和易错点
- synthesizer：组员D，监督记录者，负责查漏补缺和特殊案例
只输出 JSON 字符串数组，不要解释。"""

MINUTES_SYSTEM = (
    "你是 AI学习小组的学习整理助手。根据本轮小组成员和 AI 学伴的发言，输出简短的 Markdown 阶段学习总结，"
    "记录学习主题、知识点、不同理解、未解决的疑问和复习建议，不编造未发生的内容。"
    "使用自然的伴学表达，帮助学生理解和复习。"
)

FINAL_MINUTES_SYSTEM = (
    "你是 AI学习小组的学习整理助手。将输入的阶段学习记录整理成 Markdown 学习总结。"
    "依次包含学习主题、核心知识点、不同理解、易错点、待解决的问题和复习建议；合并重复内容，不编造。"
    "使用自然的伴学表达，帮助学生理解和复习。"
)

CONTEXT_LIMIT_MESSAGE = "本次讨论已经很久了，我们休息一下吧。"
SINGLE_AGENT_SYSTEM = """你是课程 AI学习小组助手。基于课程资料和最近讨论，用中文直接回应 @AI 的问题。
回答应简洁、准确；课程资料没有直接依据时要明确说明，不要冒充教师。"""


def _mentioned_agents(question: str):
    return [agent for agent in MAS_AGENTS if f"@{agent.name}" in question]


async def _select_agents(question: str):
    choice = await chat(DISPATCH_SYSTEM, question)
    try:
        ids = json.loads(choice)
        selected = [agent for agent in MAS_AGENTS if agent.id in ids] if isinstance(ids, list) else []
    except (TypeError, ValueError):
        selected = []
    return (selected or list(MAS_AGENTS[:2]))[:2]


async def _finish(room: MeetingRoom, db: Session) -> None:
    if room.minutes.strip():
        formatted = await chat(FINAL_MINUTES_SYSTEM, room.minutes[-settings.meeting_minutes_limit:])
    else:
        formatted = ""
    with write_lock:
        db.expire_all()
        db.refresh(room)
        pending = db.exec(select(MeetingMessage).where(
            MeetingMessage.room_id == room.id,
            MeetingMessage.role == "user",
            MeetingMessage.id > room.processed_message_id,
        )).first()
        if room.status != "ending" or pending:
            return
        if formatted.strip():
            room.minutes = formatted.strip()
        room.status = "ended"
        db.commit()


async def _prompt_idle(room: MeetingRoom, db: Session) -> None:
    last_user = db.exec(select(MeetingMessage).where(
        MeetingMessage.room_id == room.id, MeetingMessage.role == "user"
    ).order_by(MeetingMessage.id.desc())).first()
    last_agent = db.exec(select(MeetingMessage).where(
        MeetingMessage.room_id == room.id, MeetingMessage.role == "agent"
    ).order_by(MeetingMessage.id.desc())).first()
    if not last_user:
        return
    prompt = (
        f"上一次真人发言：{last_user.content}\n"
        f"上一条 Agent 回复：{last_agent.content if last_agent else '（无）'}\n\n"
        "学习小组暂时安静下来。请以 AI 学伴身份用一个简短问题引导大家继续思考，不要直接重复已有答案。"
    )
    answer = await chat(build_agent_system(MAS_AGENTS[0], "", room.minutes[-12000:], False), prompt)
    observed_activity = room.last_activity
    with write_lock:
        db.expire_all()
        db.refresh(room)
        pending = db.exec(select(MeetingMessage).where(
            MeetingMessage.room_id == room.id,
            MeetingMessage.role == "user",
            MeetingMessage.id > room.processed_message_id,
        )).first()
        if room.status != "active" or room.idle_prompted or room.last_activity != observed_activity or pending:
            return
        db.add(MeetingMessage(room_id=room.id, sender_name=MAS_AGENTS[0].name,
                              role="agent", content=answer))
        room.idle_prompted = True
        db.commit()


async def process(room_id: int, force: bool = False, ending: bool = False):
    async with locks.setdefault(room_id, asyncio.Lock()), async_process_lock(f"meeting-{room_id}"):
        with Session(engine) as db:
            room = db.get(MeetingRoom, room_id)
            if not room or room.room_type != "ai_meeting" or room.status == "ended" or (
                    not room.enabled and not ending):
                return
            pending = db.exec(select(MeetingMessage).where(MeetingMessage.room_id == room_id,
                MeetingMessage.role == "user", MeetingMessage.id > room.processed_message_id)
                .order_by(MeetingMessage.id).limit(8)).all()
            # Legacy rows use naive UTC; imported rows may carry an explicit offset.
            now = datetime.now(room.last_activity.tzinfo) if room.last_activity.tzinfo else datetime.utcnow()
            age = (now - room.last_activity).total_seconds()
            if not force and pending and len(pending) < 8 and age < room.buffer_seconds:
                return
            if not pending:
                if ending:
                    await _finish(room, db)
                elif room.agent_mode == "multi" and not room.idle_prompted and age >= settings.meeting_idle_seconds:
                    await _prompt_idle(room, db)
                return
            cursor = room.processed_message_id
            question = "\n".join(f"{row.sender_name}：{row.content}" for row in pending)
            hits = await run_in_threadpool(rag.query, room.class_course_id, question[:4000], db=db)
            context = "\n".join(hit["text"] for hit in hits)
            discussion = []
            if room.agent_mode == "single":
                mentioned = "@AI" in question or "@ai" in question
                if mentioned:
                    prompt = (f"课程资料：\n{context or '（无直接命中）'}\n\n"
                              f"最近讨论：\n{room.minutes[-12000:] or '（无）'}\n\n"
                              f"本轮消息：\n{question}")
                    discussion.append(("AI助手", await chat(SINGLE_AGENT_SYSTEM, prompt)))
            else:
                requested = _mentioned_agents(question)
                agents = requested[:2] if requested else await _select_agents(question)
                for agent in agents:
                    answer = await chat(build_agent_system(agent, context, room.minutes[-12000:], bool(hits)),
                                        build_agent_user(question, discussion))
                    discussion.append((agent.name, answer))
            summary = await chat(MINUTES_SYSTEM,
                                 question + "\n" + "\n".join(f"{name}：{text}" for name, text in discussion))
            # Network calls above may fail; no cursor or messages have been committed yet.
            with write_lock:
                db.expire_all()
                db.refresh(room)
                if room.processed_message_id != cursor or room.status == "ended" or (not room.enabled and not ending):
                    return
                for name, answer in discussion:
                    db.add(MeetingMessage(room_id=room_id, sender_name=name, role="agent", content=answer,
                                          sources=json.dumps([hit["source"] for hit in hits], ensure_ascii=False)))
                room.minutes += "\n\n" + summary
                room.processed_message_id = pending[-1].id
                if len(room.minutes) > settings.meeting_minutes_limit:
                    if room.buffer_seconds < 5:
                        db.add(MeetingMessage(room_id=room_id, sender_name=MAS_AGENTS[0].name,
                                              role="agent", content=CONTEXT_LIMIT_MESSAGE))
                    room.buffer_seconds = 5
                room.last_activity = datetime.utcnow()
                db.commit()


async def worker():
    while True:
        try:
            with Session(engine) as db:
                rooms = db.exec(select(MeetingRoom).where(
                    MeetingRoom.room_type == "ai_meeting",
                    ((MeetingRoom.status == "active") & (MeetingRoom.enabled == True)) |
                    (MeetingRoom.status == "ending"))).all()
                work = [(room.id, room.status == "ending") for room in rooms]
            semaphore = asyncio.Semaphore(max(1, settings.meeting_workers))
            async def run(room_id, ending):
                async with semaphore:
                    try:
                        await process(room_id, ending=ending, force=ending)
                    except Exception:
                        logger.exception("Meeting processing failed for %s; pending messages retained", room_id)
            await asyncio.gather(*(run(room_id, ending) for room_id, ending in work))
        except asyncio.CancelledError:
            raise
        except Exception:
            logger.exception("Meeting worker failed")
        await asyncio.sleep(1)
