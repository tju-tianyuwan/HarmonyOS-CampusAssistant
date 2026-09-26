import asyncio
import tempfile
import unittest
from datetime import datetime, timedelta
from unittest.mock import patch
from filelock import FileLock

from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy.pool import StaticPool
from sqlmodel import SQLModel, Session, create_engine, select

from app.db import get_db
from app.models import AuthSession, ClassCourse, CourseSession, Membership, TranscriptSegment, User
from app.routers import sessions
from app.services.asr.base import ASRError
from app.services.asr.huawei_realtime import HuaweiRealtimeStream, RealtimeTranscript
from app.services.security import token_hash


def result(text, final, start=0, end=100):
    return {"resp_type": "RESULT", "segments": [{"start_time": start, "end_time": end,
             "is_final": final, "result": {"text": text}}]}


class FakeCloud:
    opened = 0
    fail = False
    hold_final = False

    async def __aenter__(self):
        type(self).opened += 1
        if type(self).fail:
            raise ASRError("华为云实时识别鉴权失败（HTTP 401）")
        self.events = asyncio.Queue()
        return self

    async def __aexit__(self, *_):
        pass

    async def send_audio(self, data):
        await self.events.put(result('课堂', False))

    async def end(self):
        if not type(self).hold_final:
            await self.events.put(result('课堂内容。', True))
        await self.events.put({"resp_type": "END"})

    async def receive(self, timeout=90):
        return await self.events.get()


class RealtimeTests(unittest.TestCase):
    def setUp(self):
        self.engine = create_engine('sqlite://', connect_args={'check_same_thread': False}, poolclass=StaticPool)
        SQLModel.metadata.create_all(self.engine)
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        for p in [patch.object(sessions.settings, 'asr_provider', 'huawei_sis_realtime'),
                  patch.object(sessions.settings, 'data_dir', self.tmp.name),
                  patch.object(sessions, 'write_lock', FileLock(self.tmp.name + '/write.lock')),
                  patch.object(sessions, 'HuaweiRealtimeStream', FakeCloud)]:
            p.start()
            self.addCleanup(p.stop)
        FakeCloud.opened = 0
        FakeCloud.fail = False
        FakeCloud.hold_final = False
        app = FastAPI()
        app.include_router(sessions.router, prefix='/api/v1')
        def database():
            with Session(self.engine) as db:
                yield db
        app.dependency_overrides[get_db] = database
        self.client = TestClient(app)
        self.addCleanup(self.engine.dispose)
        self.addCleanup(self.client.close)
        with Session(self.engine) as db:
            db.add_all([User(id=1, name='Teacher', role='teacher'), User(id=2, name='Student'),
                        User(id=3, name='Other', role='teacher')])
            db.add(ClassCourse(id=1, name='Class', class_name='A', teacher_id=1, invite_code='123456'))
            db.add_all([Membership(user_id=1, class_course_id=1), Membership(user_id=2, class_course_id=1)])
            db.add(CourseSession(id=1, class_course_id=1, title='Lesson', creator_id=1))
            db.add_all([AuthSession(token_hash=token_hash(f'token-{i}'), user_id=i,
                        expires_at=datetime.utcnow() + timedelta(hours=1)) for i in (1, 2, 3)])
            db.commit()

    def connect(self, seq=0, user=1):
        headers = {'Authorization': f'Bearer token-{user}'} if user else {}
        return self.client.websocket_connect(f'/api/v1/sessions/1/realtime/{seq}', headers=headers)

    def record(self, seq=0, size=3200):
        with self.connect(seq) as ws:
            self.assertEqual(ws.receive_json()['type'], 'ready')
            ws.send_bytes(bytes(size))
            partial = ws.receive_json()
            self.assertEqual(partial['type'], 'partial')
            self.assertEqual(partial['text'], '课堂')
            ws.send_json({'type': 'stop'})
            self.assertEqual(ws.receive_json()['text'], '课堂内容。')
            ack = ws.receive_json()
            self.assertEqual(ack['type'], 'committed')
            return ack['segment']

    def test_interim_then_final_commit_and_replay_without_cloud(self):
        row = self.record()
        self.assertEqual((row['start_ms'], row['end_ms'], row['text']), (0, 100, '课堂内容。'))
        with self.connect() as ws:
            self.assertEqual(ws.receive_json()['segment']['id'], row['id'])
        self.assertEqual(FakeCloud.opened, 1)
        with Session(self.engine) as db:
            self.assertEqual(len(db.exec(select(TranscriptSegment)).all()), 1)

    def test_short_pause_windows_use_actual_duration_not_seq_times_60s(self):
        self.record(size=1600)
        row = self.record(seq=1, size=3200)
        self.assertEqual((row['start_ms'], row['end_ms']), (50, 150))

    def test_auth_permissions_missing_sequence_and_finished_session(self):
        for user, status in ((None, 401), (2, 403), (3, 403)):
            with self.connect(user=user) as ws:
                self.assertEqual(ws.receive_json()['status'], status)
        with self.connect(seq=1) as ws:
            self.assertEqual(ws.receive_json()['status'], 409)
        with Session(self.engine) as db:
            row = db.get(CourseSession, 1)
            row.status = 'done'
            db.add(row)
            db.commit()
        with self.connect() as ws:
            self.assertEqual(ws.receive_json()['status'], 409)
        self.assertEqual(FakeCloud.opened, 0)

    def test_disconnect_does_not_commit_and_full_replay_succeeds(self):
        with self.connect() as ws:
            self.assertEqual(ws.receive_json()['type'], 'ready')
            ws.send_bytes(bytes(3200))
            ws.receive_json()
        with Session(self.engine) as db:
            self.assertIsNone(db.exec(select(TranscriptSegment)).first())
        self.record()

    def test_cloud_failure_invalid_frames_and_unconfirmed_final_preserve_retry(self):
        FakeCloud.fail = True
        with self.connect() as ws:
            self.assertIn('鉴权', ws.receive_json()['message'])
        FakeCloud.fail = False
        for audio in (b'1', bytes(6402)):
            with self.connect() as ws:
                ws.receive_json()
                ws.send_bytes(audio)
                self.assertEqual(ws.receive_json()['type'], 'error')
        FakeCloud.hold_final = True
        with self.connect() as ws:
            ws.receive_json()
            ws.send_bytes(bytes(3200))
            ws.receive_json()
            ws.send_json({'type': 'stop'})
            self.assertEqual(ws.receive_json()['type'], 'error')
        with Session(self.engine) as db:
            self.assertIsNone(db.exec(select(TranscriptSegment)).first())

    def test_token_revocation_before_commit(self):
        with self.connect() as ws:
            ws.receive_json()
            ws.send_bytes(bytes(3200))
            ws.receive_json()
            with Session(self.engine) as db:
                db.delete(db.get(AuthSession, token_hash('token-1')))
                db.commit()
            ws.send_json({'type': 'stop'})
            ws.receive_json()
            self.assertEqual(ws.receive_json()['status'], 401)
        with Session(self.engine) as db:
            self.assertIsNone(db.exec(select(TranscriptSegment)).first())


class ProtocolTests(unittest.TestCase):
    def test_interim_replacement_final_dedup_and_order(self):
        transcript = RealtimeTranscript()
        transcript.update(result('first?', False))
        transcript.update(result('first!', False))
        self.assertEqual(transcript.text(True), 'first!')
        transcript.update(result('first.', True))
        transcript.update(result('first.', True))
        transcript.update(result('stale', False))
        transcript.update(result('second', False, 100, 200))
        self.assertEqual(transcript.text(), 'first.')
        self.assertEqual(transcript.text(True), 'first.second')

    def test_signed_websocket_target_has_no_duplicate_host_or_credentials_in_url(self):
        with patch.multiple(sessions.settings, sis_ak='test-ak', sis_sk='test-sk', sis_project_id='project',
                            sis_region='cn-north-4', sis_realtime_endpoint=''):
            url, headers = HuaweiRealtimeStream.connection()
        self.assertEqual(url, 'wss://sis-ext.cn-north-4.myhuaweicloud.com/v1/project/rasr/continue-stream')
        self.assertFalse(any(key.lower() == 'host' for key in headers))
        self.assertIn('Authorization', headers)


if __name__ == '__main__':
    unittest.main()
