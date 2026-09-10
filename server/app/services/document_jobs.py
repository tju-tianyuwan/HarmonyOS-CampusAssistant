"""Disk-backed imports survive HTTP timeouts and process restarts."""
import asyncio
import logging
from datetime import datetime, timedelta
from pathlib import Path

from fastapi import HTTPException
from filelock import Timeout
from sqlmodel import Session, select

from ..config import settings
from ..db import engine, write_lock
from ..models import DocumentJob, KnowledgeDocument, User
from . import rag
from .documents import extract
from .locking import process_lock
from .security import manager

logger = logging.getLogger(__name__)


def upload_path(job_id):
    return Path(settings.data_dir).resolve() / "imports" / (job_id + ".upload")


def run_job(job_id):
    lock = process_lock("import-" + job_id)
    try:
        lock.acquire(timeout=0)
    except Timeout:
        return
    try:
        with Session(engine) as db:
            job = db.get(DocumentJob, job_id)
            if not job or job.status not in ("queued", "processing"):
                return
            with write_lock:
                job.status, job.error = "processing", ""
                db.commit()
            def progress(done, total):
                with Session(engine) as update, write_lock:
                    row = update.get(DocumentJob, job_id)
                    if not row:
                        return
                    row.progress = min(95, round(done * 95 / max(1, total)))
                    row.updated_at = datetime.utcnow()
                    update.commit()
            try:
                content = extract(job.filename, upload_path(job_id).read_bytes(), progress)
                with write_lock:
                    db.expire_all()
                    user = db.get(User, job.user_id)
                    if not user:
                        raise HTTPException(403, "上传账号已不存在")
                    manager(db, user, job.class_course_id)
                    key = f"{job.class_course_id}:import_{job.id}"
                    existing = db.get(KnowledgeDocument, key)
                    job.chunks = len(rag._split(existing.content)) if existing else rag.add_document(
                        job.class_course_id, "import_" + job.id, content, job.filename, db=db, kind="manual")
                    job.status, job.progress = "done", 100
                    job.updated_at = datetime.utcnow()
                    db.commit()
            except Exception as exc:
                db.rollback()
                with write_lock:
                    job = db.get(DocumentJob, job_id)
                    job.status = "failed"
                    job.error = str(exc.detail) if isinstance(exc, HTTPException) else "资料处理失败，请重试或检查服务端日志"
                    job.updated_at = datetime.utcnow()
                    db.commit()
                logger.exception("Document import failed: %s", job_id)
            else:
                try:
                    upload_path(job_id).unlink(missing_ok=True)
                except OSError:
                    logger.warning("Import completed; temporary file cleanup deferred: %s", job_id, exc_info=True)
    finally:
        lock.release()


async def worker():
    tasks = {}
    def completed(task, job_id):
        tasks.pop(job_id, None)
        if not task.cancelled() and task.exception():
            logger.error("Import worker failed: %s", job_id, exc_info=task.exception())

    try:
        while True:
            with Session(engine) as db:
                ids = db.exec(select(DocumentJob.id).where(DocumentJob.status.in_(["queued", "processing"]))
                              .order_by(DocumentJob.created_at).limit(settings.document_queue_limit)).all()
            for job_id in ids:
                if job_id in tasks: continue
                if len(tasks) >= max(1, settings.document_job_workers): break
                task = asyncio.create_task(asyncio.to_thread(run_job, job_id))
                tasks[job_id] = task
                task.add_done_callback(lambda done, key=job_id: completed(done, key))
            await asyncio.sleep(1)
    finally:
        if tasks: await asyncio.gather(*list(tasks.values()), return_exceptions=True)


def cleanup():
    cutoff = datetime.utcnow() - timedelta(days=settings.document_job_retention_days)
    with Session(engine) as db, write_lock:
        rows = db.exec(select(DocumentJob).where(DocumentJob.status.in_(["done", "failed"]),
                                                DocumentJob.updated_at < cutoff)).all()
        for row in rows:
            upload_path(row.id).unlink(missing_ok=True)
            db.delete(row)
        db.commit()
