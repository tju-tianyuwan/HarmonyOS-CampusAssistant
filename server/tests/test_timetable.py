import unittest
from datetime import date, datetime, timedelta

from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy.pool import StaticPool
from sqlmodel import SQLModel, Session, create_engine, select

from app.db import get_db
from app.models import (AuthSession, ClassCourse, CourseSchedule, Membership, PersonalWorkspace,
                        TimetableEntry, TimetableSettings, User)
from app.routers import courses, timetable
from app.services.security import token_hash


class TimetableTest(unittest.TestCase):
    def setUp(self):
        self.engine = create_engine('sqlite://', connect_args={'check_same_thread': False}, poolclass=StaticPool)
        SQLModel.metadata.create_all(self.engine)
        app = FastAPI()
        for router in (courses.router, timetable.router):
            app.include_router(router, prefix='/api/v1')

        def database():
            with Session(self.engine) as db:
                yield db

        app.dependency_overrides[get_db] = database
        self.client = TestClient(app)
        with Session(self.engine) as db:
            db.add_all([User(id=1, name='Teacher', role='teacher'), User(id=2, name='Student'),
                        User(id=3, name='Peer'), User(id=4, name='Outsider'),
                        User(id=5, name='Other teacher', role='teacher')])
            db.add_all([ClassCourse(id=i, name=f'Course {i}', class_name='A', teacher_id=1,
                                   invite_code=f'00000{i}') for i in (1, 2)])
            db.add(ClassCourse(id=3, name='Personal', class_name='Private', teacher_id=2, invite_code='private'))
            db.add(PersonalWorkspace(user_id=2, class_course_id=3))
            db.add_all([Membership(user_id=user, class_course_id=course)
                        for user in (1, 2, 3, 5) for course in (1, 2)])
            db.add(Membership(user_id=2, class_course_id=3))
            db.add_all([AuthSession(token_hash=token_hash(f'timetable-{i}'), user_id=i,
                                    expires_at=datetime.utcnow() + timedelta(hours=1)) for i in range(1, 6)])
            db.commit()
        self.as_user(1)

    def tearDown(self):
        self.client.close()
        self.engine.dispose()

    def as_user(self, user):
        self.client.headers['Authorization'] = f'Bearer timetable-{user}'

    def slot(self, **changes):
        return dict(weekday=1, start_section=1, end_section=2, start_week=1,
                    end_week=20, week_type='all', location='Room 301') | changes

    def publish(self, course=1, slots=None, start='2026-09-07'):
        return self.client.put(f'/api/v1/courses/{course}/schedule',
                               json={'semester_start': start, 'slots': [self.slot()] if slots is None else slots})

    def entries(self):
        return self.client.get('/api/v1/timetable').json()['entries']

    def test_teacher_publish_and_students_inherit_same_rows(self):
        self.assertEqual(self.publish().status_code, 200)
        teacher = self.entries()
        self.as_user(2)
        student = self.entries()
        self.as_user(3)
        self.assertEqual(student, self.entries())
        self.assertEqual(teacher, student)
        self.assertEqual(student[0]['semester_start'], '2026-09-07')
        self.assertNotIn('user_id', student[0])
        self.assertEqual(self.client.get('/api/v1/timetable').headers['cache-control'], 'no-store')

    def test_join_course_immediately_shows_published_schedule(self):
        self.publish()
        self.as_user(4)
        self.assertEqual(self.entries(), [])
        self.assertEqual(self.client.get('/api/v1/courses/1/schedule').status_code, 403)
        self.assertEqual(self.client.post('/api/v1/courses/join', json={
            'user_id': 4, 'invite_code': '000001'}).status_code, 200)
        self.assertEqual(len(self.entries()), 1)
        self.client.post('/api/v1/courses/join', json={'user_id': 4, 'invite_code': '000001'})
        self.assertEqual(len(self.entries()), 1)

    def test_teacher_updates_and_clears_for_all_members(self):
        self.publish()
        self.assertEqual(self.publish(slots=[self.slot(weekday=3, location='Room 302')],
                                      start='2026-09-14').status_code, 200)
        for student in (2, 3):
            self.as_user(student)
            entry = self.entries()[0]
            self.assertEqual((entry['weekday'], entry['location'], entry['semester_start']),
                             (3, 'Room 302', '2026-09-14'))
        self.as_user(1)
        self.assertEqual(self.publish(slots=[]).status_code, 200)
        self.as_user(2)
        self.assertEqual(self.entries(), [])

    def test_only_course_teacher_can_write(self):
        self.publish()
        for user in (2, 4, 5):
            self.as_user(user)
            self.assertEqual(self.publish().status_code, 403)
        self.as_user(2)
        self.assertEqual(self.publish(course=3).status_code, 403)
        self.client.headers.clear()
        self.assertEqual(self.client.get('/api/v1/timetable').status_code, 401)
        self.assertEqual(self.publish().status_code, 401)

    def test_legacy_writes_rejected_and_legacy_records_preserved(self):
        with Session(self.engine) as db:
            db.add(TimetableEntry(user_id=2, class_course_id=1, weekday=6, start_section=9, end_section=10))
            db.add(TimetableSettings(user_id=2, semester_start=date(2025, 9, 1)))
            db.commit()
        self.as_user(2)
        self.assertEqual(self.entries(), [])
        for method, path in [('post', '/entries'), ('put', '/settings'), ('put', '/entries/1'), ('delete', '/entries/1')]:
            self.assertEqual(self.client.request(method, '/api/v1/timetable' + path, json={}).status_code, 403)
        with Session(self.engine) as db:
            self.assertEqual(len(db.exec(select(TimetableEntry)).all()), 1)
            self.assertEqual(db.get(TimetableSettings, 2).semester_start, date(2025, 9, 1))

    def test_conflicts_respect_parity_and_do_not_replace_previous_schedule(self):
        self.assertEqual(self.publish(slots=[self.slot(week_type='odd'), self.slot(week_type='even')]).status_code, 200)
        before = self.entries()
        self.assertEqual(self.publish(slots=[self.slot(), self.slot(start_section=2, end_section=3)]).status_code, 409)
        self.assertEqual(self.entries(), before)
        self.assertEqual(self.publish(course=2).status_code, 409)
        self.assertEqual(self.publish(course=2, slots=[self.slot(start_section=3, end_section=4)]).status_code, 200)

    def test_conflicts_use_actual_dates_across_semesters(self):
        self.publish(slots=[self.slot(start_week=2, end_week=2)])
        self.assertEqual(self.publish(course=2, slots=[self.slot(start_week=1, end_week=1)],
                                      start='2026-09-14').status_code, 409)
        self.assertEqual(self.publish(course=2, slots=[self.slot(start_week=1, end_week=1)],
                                      start='2026-09-21').status_code, 200)
        self.as_user(2)
        self.assertTrue(self.client.get('/api/v1/timetable').json()['multiple_semesters'])

    def test_create_course_and_schedule_are_atomic(self):
        body = {'name': 'New course', 'class_name': 'B', 'teacher_id': 1,
                'schedule': {'semester_start': '2026-09-07', 'slots': [self.slot()]}}
        result = self.client.post('/api/v1/courses', json=body)
        self.assertEqual(result.status_code, 200, result.text)
        course = result.json()
        self.as_user(4)
        self.client.post('/api/v1/courses/join', json={'user_id': 4, 'invite_code': course['invite_code']})
        self.assertEqual(self.entries()[0]['class_course_id'], course['id'])
        self.as_user(1)
        with Session(self.engine) as db:
            count = len(db.exec(select(ClassCourse)).all())
        self.assertEqual(self.client.post('/api/v1/courses', json=body).status_code, 409)
        with Session(self.engine) as db:
            self.assertEqual(len(db.exec(select(ClassCourse)).all()), count)
            self.assertEqual(len(db.exec(select(CourseSchedule)).all()), 1)

    def test_validation_and_empty_creation(self):
        for changes in ({'weekday': 0}, {'weekday': 8}, {'start_section': 4, 'end_section': 2},
                        {'end_section': 13}, {'start_week': 10, 'end_week': 2}, {'end_week': 31},
                        {'week_type': 'invalid'}, {'start_week': 2, 'end_week': 2, 'week_type': 'odd'}):
            self.assertEqual(self.publish(slots=[self.slot(**changes)]).status_code, 422, changes)
        self.assertEqual(self.publish(start='2026-09-08').status_code, 422)
        self.assertEqual(self.publish(slots=[self.slot()] * 41).status_code, 422)
        self.assertEqual(self.client.post('/api/v1/courses', json={
            'name': 'Empty', 'class_name': 'A', 'teacher_id': 1,
            'schedule': {'semester_start': '2026-09-07', 'slots': []}}).status_code, 422)

    def test_lost_membership_hides_course_and_student_conflicts_are_not_discarded(self):
        self.publish()
        with Session(self.engine) as db:
            course = db.get(ClassCourse, 2)
            course.teacher_id = 5
            db.add(course)
            db.commit()
        self.as_user(5)
        self.assertEqual(self.publish(course=2).status_code, 200)
        self.as_user(2)
        self.assertEqual(len(self.entries()), 2)
        with Session(self.engine) as db:
            membership = db.exec(select(Membership).where(Membership.user_id == 2,
                                                          Membership.class_course_id == 1)).first()
            db.delete(membership)
            db.commit()
        self.assertEqual(len(self.entries()), 1)
        self.assertEqual(self.entries()[0]['class_course_id'], 2)


if __name__ == '__main__':
    unittest.main()
