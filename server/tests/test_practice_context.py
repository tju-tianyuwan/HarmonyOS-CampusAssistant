import unittest
from datetime import datetime, timedelta
from unittest.mock import AsyncMock, patch
from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy.pool import StaticPool
from sqlmodel import Session, SQLModel, create_engine
from app.db import get_db
from app.models import AuthSession, ClassCourse, CourseSession, Membership, Outline, User
from app.routers import practice
from app.services.practice_context import topic_labels
from app.services.security import token_hash


class PracticeContextTest(unittest.TestCase):
    def setUp(self):
        self.engine=create_engine('sqlite://',connect_args={'check_same_thread':False},poolclass=StaticPool)
        SQLModel.metadata.create_all(self.engine)
        app=FastAPI()
        app.include_router(practice.router)
        def db_session():
            with Session(self.engine) as db:yield db
        app.dependency_overrides[get_db]=db_session
        self.client=TestClient(app)
        self.client.headers['Authorization']='Bearer practice-test'
        with Session(self.engine) as db:
            db.add_all([User(id=1,name='Teacher',role='teacher'),User(id=2,name='Student')])
            for i,name in [(1,'高等数学'),(2,'数据结构'),(3,'无资料课程'),(4,'未加入课程')]:
                db.add(ClassCourse(id=i,name=name,class_name='A',teacher_id=1,invite_code=str(i)*6))
                if i!=4:db.add(Membership(user_id=2,class_course_id=i))
            db.add(AuthSession(user_id=2,token_hash=token_hash('practice-test'),expires_at=datetime.utcnow()+timedelta(hours=1)))
            for i,course,title,content,status in [
                (1,1,'第一讲 极限','# 高等数学\n## 一、函数极限\n极限的定义。','published'),
                (2,2,'树','# 二叉树\n## 中序遍历','published'),
                (3,1,'第二讲 积分','# 定积分\n## 二、微积分基本定理','published'),
                (4,1,'隐藏提纲','# 不应泄露的草稿','draft')]:
                db.add(CourseSession(id=i,class_course_id=course,title=title,creator_id=1))
                db.add(Outline(session_id=i,class_course_id=course,owner_id=-1,markdown=content,status=status))
            db.add(Outline(session_id=1,class_course_id=1,owner_id=1,markdown='# 教师私有笔记',status='published'))
            db.commit()

    def tearDown(self):
        self.client.close()
        self.engine.dispose()

    def test_course_metadata_is_isolated_and_published_only(self):
        response=self.client.get('/practice/context?class_course_id=1')
        self.assertEqual(response.status_code,200,response.text)
        data=response.json()
        self.assertEqual(data['course_name'],'高等数学')
        self.assertEqual(data['knowledge_count'],2)
        labels=[t['name'] for t in data['topics']]
        self.assertIn('函数极限',labels)
        self.assertIn('定积分',labels)
        self.assertNotIn('二叉树',labels)
        self.assertNotIn('不应泄露的草稿',labels)
        self.assertNotIn('教师私有笔记',labels)
        tree=self.client.get('/practice/context?class_course_id=2').json()
        self.assertIn('二叉树',[t['name'] for t in tree['topics']])
        self.assertNotIn('函数极限',[t['name'] for t in tree['topics']])

    def test_empty_course_returns_no_demo_topics(self):
        data=self.client.get('/practice/context?class_course_id=3').json()
        self.assertEqual(data['knowledge_count'],0)
        self.assertEqual(data['topics'],[])
        self.assertEqual(data['knowledge_sources'],[])
        response=self.client.post('/practice/generate',json={'class_course_id':3,'user_id':2})
        self.assertEqual(response.status_code,409)

    def test_lesson_scope_and_access_checks(self):
        data=self.client.get('/practice/context?class_course_id=1&session_id=3').json()
        self.assertEqual(data['session_title'],'第二讲 积分')
        self.assertEqual(data['knowledge_count'],1)
        self.assertNotIn('函数极限',[t['name'] for t in data['topics']])
        self.assertEqual(self.client.get('/practice/context?class_course_id=1&session_id=2').status_code,404)
        self.assertEqual(self.client.get('/practice/context?class_course_id=1&session_id=4').status_code,403)
        self.assertEqual(self.client.get('/practice/context?class_course_id=4').status_code,403)
        self.client.headers.clear()
        self.assertEqual(self.client.get('/practice/context?class_course_id=1').status_code,401)

    def test_generation_uses_the_same_lesson_scope(self):
        question=dict(id=1,type='单选题',difficulty='基础',topic='积分',stem='题目',options=['a','b','c','d'],answer=0,
                      explanation='解析',source='提纲：第二讲 积分')
        with patch.object(practice,'generate_choice_questions',new=AsyncMock(return_value=[question])) as generator:
            response=self.client.post('/practice/generate',json={'class_course_id':1,'session_id':3,'user_id':2,'count':1})
            self.assertEqual(response.status_code,200,response.text)
            content=str(generator.await_args.kwargs['knowledge'])
            self.assertIn('微积分基本定理',content)
            self.assertNotIn('函数极限',content)
            self.assertNotIn('二叉树',content)
            denied=self.client.post('/practice/generate',json={'class_course_id':1,'session_id':2,'user_id':2,'count':1})
            self.assertEqual(denied.status_code,404)
            self.assertEqual(generator.await_count,1)

    def test_topics_ignore_code_and_fallback_to_real_source(self):
        self.assertEqual(topic_labels('```md\n# 假标题\n```\n## 一、**极限**\n## 总结','提纲：第一讲'),['极限'])
        self.assertEqual(topic_labels('普通正文，没有标题','提纲：第二讲'),['第二讲'])


if __name__=='__main__':unittest.main()
