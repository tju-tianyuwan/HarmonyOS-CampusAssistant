import unittest

from fastapi import HTTPException, Response
from sqlalchemy.pool import StaticPool
from sqlmodel import SQLModel, Session, create_engine

from app.models import ClassCourse, CourseSession, Membership, Note, Outline, User
from app.routers.courses import course_workspace_stats


class CourseWorkspaceStatsTest(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        SQLModel.metadata.create_all(self.engine)

    def test_counts_are_isolated_by_course(self) -> None:
        with Session(self.engine) as db:
            teacher = User(name="教师", role="teacher")
            student = User(name="学生", role="student")
            classmate = User(name="同学", role="student")
            db.add_all([teacher, student, classmate])
            db.commit()
            db.refresh(teacher)
            db.refresh(student)
            db.refresh(classmate)

            course_a = ClassCourse(
                name="课程 A",
                class_name="A 班",
                teacher_id=teacher.id,
                invite_code="100001",
            )
            course_b = ClassCourse(
                name="课程 B",
                class_name="B 班",
                teacher_id=teacher.id,
                invite_code="100002",
            )
            db.add_all([course_a, course_b])
            db.commit()
            db.refresh(course_a)
            db.refresh(course_b)
            db.add_all(
                [
                    Membership(user_id=student.id, class_course_id=course_a.id),
                    Membership(user_id=student.id, class_course_id=course_b.id),
                ]
            )

            session_a_published = CourseSession(
                class_course_id=course_a.id,
                title="A 已发布",
                creator_id=teacher.id,
            )
            session_a_draft = CourseSession(
                class_course_id=course_a.id,
                title="A 草稿",
                creator_id=teacher.id,
            )
            session_b_published = CourseSession(
                class_course_id=course_b.id,
                title="B 已发布",
                creator_id=teacher.id,
            )
            db.add_all([session_a_published, session_a_draft, session_b_published])
            db.commit()
            db.refresh(session_a_published)
            db.refresh(session_a_draft)
            db.refresh(session_b_published)
            db.add_all(
                [
                    Outline(
                        session_id=session_a_published.id,
                        class_course_id=course_a.id,
                        owner_id=-1,
                        markdown="# A",
                        status="published",
                    ),
                    Outline(
                        session_id=session_a_draft.id,
                        class_course_id=course_a.id,
                        owner_id=-1,
                        markdown="# A draft",
                        status="draft",
                    ),
                    Outline(
                        session_id=session_a_draft.id,
                        class_course_id=course_a.id,
                        owner_id=student.id,
                        markdown="# personal",
                        status="published",
                    ),
                    Outline(
                        session_id=session_b_published.id,
                        class_course_id=course_b.id,
                        owner_id=-1,
                        markdown="# B",
                        status="published",
                    ),
                    Note(
                        class_course_id=course_a.id,
                        owner_id=student.id,
                        title="我的私有笔记",
                    ),
                    Note(
                        class_course_id=course_a.id,
                        owner_id=student.id,
                        title="我的共享笔记",
                        visibility="shared",
                    ),
                    Note(
                        class_course_id=course_a.id,
                        owner_id=classmate.id,
                        title="同学共享笔记",
                        visibility="shared",
                    ),
                    Note(
                        class_course_id=course_a.id,
                        owner_id=classmate.id,
                        title="同学私有笔记",
                    ),
                    Note(
                        class_course_id=course_b.id,
                        owner_id=student.id,
                        title="B 课程个人笔记",
                    ),
                ]
            )
            db.commit()

            stats_a = course_workspace_stats(course_a.id, student.id, Response(), db, student)
            stats_b = course_workspace_stats(course_b.id, student.id, Response(), db, student)

            self.assertEqual(stats_a.official_lesson_count, 1)
            self.assertEqual(stats_a.personal_note_count, 2)
            self.assertEqual(stats_a.class_note_count, 2)
            self.assertEqual(stats_b.official_lesson_count, 1)
            self.assertEqual(stats_b.personal_note_count, 1)
            self.assertEqual(stats_b.class_note_count, 0)

            db.add(
                Note(
                    class_course_id=course_b.id,
                    owner_id=classmate.id,
                    title="B 课程新增班级笔记",
                    visibility="shared",
                )
            )
            db.commit()

            refreshed_a = course_workspace_stats(course_a.id, student.id, Response(), db, student)
            refreshed_b = course_workspace_stats(course_b.id, student.id, Response(), db, student)
            self.assertEqual(refreshed_a.class_note_count, 2)
            self.assertEqual(refreshed_b.class_note_count, 1)

    def test_requires_course_membership_and_disables_cache(self) -> None:
        with Session(self.engine) as db:
            teacher = User(name="教师", role="teacher")
            outsider = User(name="旁听者", role="student")
            db.add_all([teacher, outsider])
            db.commit()
            db.refresh(teacher)
            db.refresh(outsider)
            course = ClassCourse(
                name="课程",
                class_name="班级",
                teacher_id=teacher.id,
                invite_code="100003",
            )
            db.add(course)
            db.commit()
            db.refresh(course)

            response = Response()
            with self.assertRaises(HTTPException) as raised:
                course_workspace_stats(course.id, outsider.id, response, db, outsider)

            self.assertEqual(raised.exception.status_code, 403)
            self.assertEqual(response.headers["Cache-Control"], "no-store")


if __name__ == "__main__":
    unittest.main()
