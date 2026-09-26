"""Isolated emulator fixture, no cloud calls or changes to smartstudy.db.

Run from server: python -m tests.realtime_device_server
Only binds loopback:8012; the emulator reaches the host at 10.0.2.2:8012.
"""
import asyncio
import os
import tempfile
from datetime import datetime, timedelta
from pathlib import Path

fixture_dir = tempfile.TemporaryDirectory(prefix="campus-realtime-device-")
os.environ["DATABASE_URL"] = "sqlite:///" + str(Path(fixture_dir.name) / "test.db")
os.environ["DATA_DIR"] = fixture_dir.name
os.environ["ASR_PROVIDER"] = "huawei_sis_realtime"

import uvicorn
from fastapi import FastAPI
from sqlmodel import Session
from app.db import engine, init_db
from app.models import AuthSession, ClassCourse, Membership, User
from app.routers import sessions
from app.services.security import token_hash


class SimulatedSIS:
    async def __aenter__(self):
        self.events = asyncio.Queue()
        self.bytes = 0
        return self

    async def __aexit__(self, *_):
        pass

    async def send_audio(self, data):
        self.bytes += len(data)
        await self.events.put({"resp_type": "RESULT", "segments": [{"start_time": 0,
            "end_time": round(self.bytes / 32), "is_final": False, "result": {"text": "模拟字幕：课堂"}}]})

    async def end(self):
        await self.events.put({"resp_type": "RESULT", "segments": [{"start_time": 0,
            "end_time": round(self.bytes / 32), "is_final": True, "result": {"text": "模拟字幕：课堂实时识别测试。"}}]})
        await self.events.put({"resp_type": "END"})

    async def receive(self, timeout=90):
        return await asyncio.wait_for(self.events.get(), timeout)


sessions.HuaweiRealtimeStream = SimulatedSIS
init_db()
with Session(engine) as db:
    db.add(User(id=1, name="Emulator Test Teacher", role="teacher"))
    db.add(ClassCourse(id=1, name="Realtime test", class_name="Test", teacher_id=1, invite_code="test"))
    db.add(Membership(user_id=1, class_course_id=1))
    db.add(AuthSession(token_hash=token_hash("realtime-device-test-token"), user_id=1,
                       expires_at=datetime.utcnow() + timedelta(hours=2)))
    db.commit()
app = FastAPI()
app.include_router(sessions.router, prefix="/api/v1")

if __name__ == "__main__":
    print("SIMULATED SIS fixture at loopback:8012; no cloud credentials used", flush=True)
    try:
        uvicorn.run(app, host="127.0.0.1", port=8012)
    finally:
        engine.dispose()
        fixture_dir.cleanup()
