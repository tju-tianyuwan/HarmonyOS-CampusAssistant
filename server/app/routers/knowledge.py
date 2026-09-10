from pathlib import Path
from uuid import uuid4

from fastapi import APIRouter, Depends, File, HTTPException, UploadFile
from pydantic import BaseModel, Field
from sqlmodel import Session, select
from starlette.concurrency import run_in_threadpool

from ..config import settings
from ..db import get_db, write_lock
from ..models import DocumentJob, KnowledgeDocument, User
from ..services.document_jobs import upload_path
from ..services import rag
from ..services.documents import extract
from ..services.security import current_user, manager, member

router = APIRouter(prefix="/knowledge", tags=["knowledge"])


class Search(BaseModel):
    question: str = Field(min_length=1, max_length=4000)


class DocumentBody(BaseModel):
    source: str = Field(min_length=1, max_length=200)
    content: str = Field(min_length=1, max_length=200000)


@router.get("/{course_id}")
def status(course_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    member(db, user, course_id)
    docs = rag.documents(course_id, db)
    return {"mode": "hybrid" if rag.configured() else "lexical",
        "needs_rebuild": rag.configured() and any(doc.embedding_profile != rag.profile() for doc in docs), "documents": [
        {"id": doc.id, "source": doc.source, "kind": doc.kind, "chars": len(doc.content),
         "updated_at": doc.updated_at.isoformat()} for doc in docs]}


@router.post("/{course_id}/search")
def search(course_id: int, body: Search, db: Session = Depends(get_db), user: User = Depends(current_user)):
    member(db, user, course_id)
    return {"hits": rag.query(course_id, body.question, db=db)}


@router.post("/{course_id}/documents")
def add(course_id: int, body: DocumentBody, db: Session = Depends(get_db), user: User = Depends(current_user)):
    manager(db, user, course_id)
    with write_lock:
        count = rag.add_document(course_id, uuid4().hex, body.content, body.source, db=db)
        db.commit()
    return {"chunks": count}


@router.post("/{course_id}/upload")
async def upload(course_id: int, file: UploadFile = File(...), db: Session = Depends(get_db),
                 user: User = Depends(current_user)):
    manager(db, user, course_id)
    data = await file.read(settings.document_max_bytes + 1)
    if len(data) > settings.document_max_bytes:
        raise HTTPException(413, "文件超过上传大小限制")
    text = await run_in_threadpool(extract, file.filename or "", data)
    return await run_in_threadpool(add, course_id,
                                  DocumentBody(source=Path(file.filename).name[:200], content=text), db, user)


@router.get("/{course_id}/jobs")
def jobs(course_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    manager(db, user, course_id)
    return db.exec(select(DocumentJob).where(DocumentJob.class_course_id == course_id)
                   .order_by(DocumentJob.created_at.desc()).limit(50)).all()


@router.post("/{course_id}/imports", status_code=202)
async def start_import(course_id: int, file: UploadFile = File(...), db: Session = Depends(get_db),
                       user: User = Depends(current_user)):
    manager(db, user, course_id)
    filename = Path((file.filename or "").replace("\\", "/")).name[:200]
    if Path(filename).suffix.lower() not in (".pdf", ".pptx", ".txt", ".md"):
        raise HTTPException(415, "支持 PDF、PPTX、Markdown 和 TXT")
    data = await file.read(settings.document_max_bytes + 1)
    if not data or len(data) > settings.document_max_bytes:
        raise HTTPException(413, "文件为空或超过上传限制")
    with write_lock:
        pending = db.exec(select(DocumentJob.id).where(DocumentJob.status.in_(["queued", "processing"]))).all()
        if len(pending) >= settings.document_queue_limit:
            raise HTTPException(429, "导入队列已满，请稍后重试")
        job = DocumentJob(id=uuid4().hex, class_course_id=course_id, user_id=user.id, filename=filename)
        path = upload_path(job.id)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(data)
        db.add(job)
        db.commit()
        db.refresh(job)
    return job


@router.post("/{course_id}/jobs/{job_id}/retry")
def retry_import(course_id: int, job_id: str, db: Session = Depends(get_db), user: User = Depends(current_user)):
    manager(db, user, course_id)
    with write_lock:
        job = db.get(DocumentJob, job_id)
        if not job or job.class_course_id != course_id: raise HTTPException(404, "导入任务不存在")
        if job.status != "failed": raise HTTPException(409, "只有失败任务可重试")
        if not upload_path(job.id).exists(): raise HTTPException(410, "源文件已清理，请重新上传")
        pending = db.exec(select(DocumentJob.id).where(DocumentJob.status.in_(["queued", "processing"]))).all()
        if len(pending) >= settings.document_queue_limit:
            raise HTTPException(429, "导入队列已满，请稍后重试")
        job.status, job.error, job.progress = "queued", "", 0
        job.user_id = user.id
        db.commit()
    return {"ok": True}


@router.delete("/{course_id}/documents/{document_id}")
def remove(course_id: int, document_id: str, db: Session = Depends(get_db), user: User = Depends(current_user)):
    manager(db, user, course_id)
    doc = db.get(KnowledgeDocument, document_id)
    if not doc or doc.class_course_id != course_id:
        raise HTTPException(404, "资料不存在")
    if doc.kind != "manual":
        raise HTTPException(409, "请在提纲或笔记页面撤回该资料")
    db.delete(doc)
    db.commit()
    return {"ok": True}


@router.post("/{course_id}/rebuild")
def rebuild(course_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    manager(db, user, course_id)
    with write_lock:
        return {"documents": rag.rebuild(course_id, db)}


@router.post("/{course_id}/embedding-test")
def test_embedding(course_id: int, db: Session = Depends(get_db), user: User = Depends(current_user)):
    manager(db, user, course_id)
    vector = rag.embed(["课程知识库连接测试"])[0]
    return {"ok": True, "dimensions": len(vector), "model": settings.embed_model}
