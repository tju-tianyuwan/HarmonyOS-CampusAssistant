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


async def process(room_id: int, force: bool = False, ending: bool = False):
    async with locks.setdefault(room_id, asyncio.Lock()), async_process_lock(f"meeting-{room_id}"):
        with Session(engine) as db:
            room = db.get(MeetingRoom, room_id)
            if not room or room.status == "ended" or (not room.enabled and not ending):
                return
            pending = db.exec(select(MeetingMessage).where(MeetingMessage.room_id == room_id,
                MeetingMessage.role == "user", MeetingMessage.id > room.processed_message_id)
                .order_by(MeetingMessage.id).limit(8)).all()
            age = (datetime.utcnow() - room.last_activity).total_seconds()
            if not force and pending and len(pending) < 8 and age < room.buffer_seconds:
                return
            if not pending:
                if ending:
                    room.status = "ended"
                    db.commit()
                elif not room.idle_prompted and age >= settings.meeting_idle_seconds:
                    db.add(MeetingMessage(room_id=room_id, sender_name=MAS_AGENTS[0].name,
                                         role="agent", content="这一轮还有哪个概念需要一起核对？"))
                    room.idle_prompted = True
                    db.commit()
                return
            cursor = room.processed_message_id
            question = "\n".join(f"{row.sender_name}：{row.content}" for row in pending)
            hits = await run_in_threadpool(rag.query, room.class_course_id, question[:4000], db=db)
            context = "\n".join(hit["text"] for hit in hits)
            requested = [agent for agent in MAS_AGENTS if f"@{agent.name}" in question]
            if not requested:
                choice = await chat('为课堂讨论选择最多两个角色，只输出 JSON 数组，可选 analyst、skeptic、connector、synthesizer。', question)
                try:
                    ids = json.loads(choice)
                    requested = [agent for agent in MAS_AGENTS if agent.id in ids] if isinstance(ids, list) else []
                except ValueError:
                    requested = []
            agents = (requested or list(MAS_AGENTS[:2]))[:2]
            discussion = []
            for agent in agents:
                answer = await chat(build_agent_system(agent, context, room.minutes[-12000:], bool(hits)),
                                    build_agent_user(question, discussion))
                discussion.append((agent.name, answer))
            summary = await chat("你是课堂会议记录员。输出 Markdown 增量纪要，记录结论、分歧和下一步，不编造。",
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
                    room.buffer_seconds = max(room.buffer_seconds, 5)
                if ending:
                    newer = db.exec(select(MeetingMessage).where(MeetingMessage.room_id == room_id,
                        MeetingMessage.role == "user", MeetingMessage.id > room.processed_message_id)).first()
                    if not newer:
                        room.status = "ended"
                db.commit()


async def worker():
    while True:
        try:
            with Session(engine) as db:
                rooms = db.exec(select(MeetingRoom).where(
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
