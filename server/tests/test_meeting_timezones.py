import unittest
from contextlib import asynccontextmanager
from datetime import datetime, timedelta, timezone
from types import SimpleNamespace
from unittest.mock import AsyncMock, MagicMock, patch

from app.services import meetings


@asynccontextmanager
async def unlocked(*args):
    yield


class MeetingTimezoneTests(unittest.IsolatedAsyncioTestCase):
    async def test_idle_detection_accepts_naive_utc_and_explicit_offsets(self):
        for tz in (None, timezone.utc, timezone(timedelta(hours=8))):
            for seconds, expected in ((1, False), (30, True)):
                with self.subTest(tz=tz, seconds=seconds):
                    now = datetime.now(tz) if tz else datetime.utcnow()
                    room = SimpleNamespace(room_type='ai_meeting', status='active', enabled=True,
                                           last_activity=now - timedelta(seconds=seconds),
                                           agent_mode='multi', idle_prompted=False, processed_message_id=0)
                    db = MagicMock()
                    db.get.return_value = room
                    db.exec.return_value.all.return_value = []
                    with patch.object(meetings, 'Session') as session, \
                         patch.object(meetings, 'async_process_lock', unlocked), \
                         patch.object(meetings, '_prompt_idle', new_callable=AsyncMock) as prompt, \
                         patch.object(meetings.settings, 'meeting_idle_seconds', 10), \
                         patch.object(meetings, 'locks', {}):
                        session.return_value.__enter__.return_value = db
                        await meetings.process(1)
                        self.assertEqual(prompt.await_count, int(expected))
