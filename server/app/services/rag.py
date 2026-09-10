"""SQL controls document visibility; immutable Chroma versions are derived data."""
import hashlib
import json
import re
from datetime import datetime
from uuid import uuid4

import jieba
from fastapi import HTTPException
from openai import OpenAI
from rank_bm25 import BM25Okapi
from sqlmodel import Session, select

from ..config import settings
from ..models import CourseSession, KnowledgeDocument, Note, Outline
from ..db import write_lock


def _split(text: str, size: int = 700, overlap: int = 100) -> list[str]:
    return [text[i:i + size] for i in range(0, len(text), size - overlap) if text[i:i + size].strip()]


def profile() -> str:
    return hashlib.sha256(json.dumps([settings.embed_base_url, settings.embed_model,
                                     settings.embed_dimensions, 700, 100]).encode()).hexdigest()[:16]


def configured() -> bool:
    return bool(settings.embed_api_key and settings.embed_model)


def embed(texts: list[str]) -> list[list[float]]:
    if not configured():
        raise HTTPException(409, "尚未配置 Embedding，当前使用关键词检索")
    options = {"dimensions": settings.embed_dimensions} if settings.embed_dimensions else {}
    try:
        with OpenAI(api_key=settings.embed_api_key, base_url=settings.embed_base_url or None,
                    timeout=30, max_retries=1) as client:
            result = client.embeddings.create(model=settings.embed_model, input=texts, **options)
        vectors = [row.embedding for row in sorted(result.data, key=lambda row: row.index)]
        if len(vectors) != len(texts) or not vectors or not vectors[0]:
            raise ValueError("empty embeddings")
        return vectors
    except Exception as exc:
        raise HTTPException(502, "Embedding 服务连接失败，请检查服务端配置") from exc


def chroma_client():
    import chromadb
    if settings.chroma_host:
        return chromadb.HttpClient(host=settings.chroma_host, port=settings.chroma_port, ssl=settings.chroma_ssl)
    return chromadb.PersistentClient(path=f"{settings.data_dir}/chroma")


def _collection(course: int):
    return chroma_client().get_or_create_collection(
        name=f"course_{course}_{profile()}", metadata={"hnsw:space": "cosine"})


def _write_vectors(doc: KnowledgeDocument):
    if not configured():
        return
    chunks = _split(doc.content)
    col = _collection(doc.class_course_id)
    for offset in range(0, len(chunks), 32):
        batch = chunks[offset:offset + 32]
        col.upsert(ids=[f"{doc.id}:{doc.version}:{offset + i}" for i in range(len(batch))],
                   embeddings=embed(batch), documents=batch,
                   metadatas=[{"doc": doc.id, "version": doc.version, "source": doc.source} for _ in batch])


def add_document(class_course_id: int, doc_id: str, text: str, source: str, *, db: Session,
                 kind: str | None = None) -> int:
    if not text.strip() or len(text) > 200000:
        raise HTTPException(422, "文档内容不能为空且不能超过 20 万字符")
    key = f"{class_course_id}:{doc_id}"
    old = db.get(KnowledgeDocument, key)
    doc = KnowledgeDocument(id=key, class_course_id=class_course_id, source=source, content=text,
                            kind=kind or ("outline" if doc_id.startswith("outline_") else
                                          "note" if doc_id.startswith("note_") else "manual"),
                            version=uuid4().hex, embedding_profile=profile() if configured() else "")
    _write_vectors(doc)
    if old:
        for field, value in doc.model_dump().items():
            setattr(old, field, value)
    else:
        db.add(doc)
    db.flush()
    return len(_split(text))


def delete_document(class_course_id: int, doc_id: str, *, db: Session) -> None:
    doc = db.get(KnowledgeDocument, f"{class_course_id}:{doc_id}")
    if doc:
        db.delete(doc)
        db.flush()


def documents(course: int, db: Session) -> list[KnowledgeDocument]:
    rows = db.exec(select(KnowledgeDocument).where(KnowledgeDocument.class_course_id == course)).all()
    active = []
    for doc in rows:
        ref = doc.id.split(":", 1)[1]
        if doc.kind == "outline":
            outline = db.get(Outline, int(ref.removeprefix("outline_")))
            if not outline or outline.owner_id != -1 or outline.status != "published" or outline.markdown != doc.content:
                continue
        elif doc.kind == "note":
            note = db.get(Note, int(ref.removeprefix("note_")))
            if not note or note.visibility != "shared" or note.quality_status != "accepted" or note.content != doc.content:
                continue
        active.append(doc)
    # Legacy publications remain searchable before the first vector rebuild.
    known = {doc.id for doc in active}
    for outline in db.exec(select(Outline).where(Outline.class_course_id == course,
                           Outline.owner_id == -1, Outline.status == "published")).all():
        key = f"{course}:outline_{outline.id}"
        if key not in known and outline.markdown.strip():
            lesson = db.get(CourseSession, outline.session_id)
            active.append(KnowledgeDocument(id=key, class_course_id=course, kind="outline",
                          source=f"提纲：{lesson.title if lesson else outline.session_id}",
                          content=outline.markdown, version="legacy", embedding_profile=""))
    for note in db.exec(select(Note).where(Note.class_course_id == course, Note.kind == "md",
                        Note.visibility == "shared", Note.quality_status == "accepted")).all():
        key = f"{course}:note_{note.id}"
        if key not in known and note.content.strip():
            active.append(KnowledgeDocument(id=key, class_course_id=course, kind="note",
                          source=f"共享笔记：{note.title}", content=note.content,
                          version="legacy", embedding_profile=""))
    return active


def list_chunks(class_course_id: int, limit: int = 8, *, db: Session) -> list[dict]:
    rows = [{"text": chunk, "source": doc.source, "doc_id": doc.id, "version": doc.version}
            for doc in documents(class_course_id, db) for chunk in _split(doc.content)]
    return rows[:limit]


def query(class_course_id: int, question: str, top_k: int = 4, *, db: Session) -> list[dict]:
    docs = documents(class_course_id, db)
    chunks = [{"text": chunk, "source": doc.source, "doc_id": doc.id, "version": doc.version}
              for doc in docs for chunk in _split(doc.content)]
    if not chunks or not question.strip():
        return []
    def tokenize(text):
        return [token for token in jieba.cut(text.lower()) if re.search(r"[\w]", token)]
    corpus = [tokenize(row["text"]) for row in chunks]
    tokens = tokenize(question)
    if not tokens or not any(corpus):
        return []
    bm25 = BM25Okapi(corpus)
    scores = bm25.get_scores(tokens)
    # BM25 can be zero for ubiquitous terms; token overlap keeps single-document courses usable.
    lexical = sorted(range(len(chunks)), key=lambda i: (scores[i], len(set(tokens) & set(corpus[i]))), reverse=True)
    lexical = [i for i in lexical if set(tokens) & set(corpus[i])][:20]
    ranks = {i: 1 / (60 + rank) for rank, i in enumerate(lexical, 1)}
    mode, warning = "lexical", ""
    if configured():
        try:
            indexed = [doc for doc in docs if doc.embedding_profile == profile()]
            if len(indexed) != len(docs):
                raise ValueError("rebuild required")
            ids = [f"{doc.id}:{doc.version}:{i}" for doc in docs for i, _ in enumerate(_split(doc.content))]
            col = _collection(class_course_id)
            result = col.query(query_embeddings=embed([question]), n_results=min(20, len(ids)), ids=ids,
                               include=["distances"])
            positions = {key: i for i, key in enumerate(ids)}
            for rank, (key, distance) in enumerate(zip(result["ids"][0], result["distances"][0]), 1):
                if distance <= settings.rag_max_distance:
                    index = positions[key]
                    ranks[index] = ranks.get(index, 0) + 1 / (60 + rank)
            mode = "hybrid"
        except Exception:
            warning = "向量检索不可用或索引需重建，本次使用关键词检索"
    return [{**chunks[i], "retrieval_mode": mode, "warning": warning}
            for i in sorted(ranks, key=ranks.get, reverse=True)[:top_k]]


def rebuild(course: int, db: Session) -> int:
    specs = [(doc.id.split(":", 1)[1], doc.content, doc.source, "manual")
             for doc in documents(course, db) if doc.kind == "manual"]
    for outline in db.exec(select(Outline).where(Outline.class_course_id == course,
                                                Outline.owner_id == -1, Outline.status == "published")).all():
        session = db.get(CourseSession, outline.session_id)
        if outline.markdown.strip():
            specs.append((f"outline_{outline.id}", outline.markdown, f"提纲：{session.title}", "outline"))
    for note in db.exec(select(Note).where(Note.class_course_id == course, Note.visibility == "shared",
                                          Note.quality_status == "accepted", Note.kind == "md")).all():
        if note.content.strip():
            specs.append((f"note_{note.id}", note.content, f"共享笔记：{note.title}", "note"))
    for key, content, source, kind in specs:
        add_document(course, key, content, source, db=db, kind=kind)
    db.commit()
    return len(specs)


def cleanup(db: Session) -> int:
    # Writers hold the same lock through SQL commit, so uncommitted vector versions stay protected.
    with write_lock:
        client = chroma_client()
        removed = 0
        for item in client.list_collections():
            name = item if isinstance(item, str) else item.name
            match = re.fullmatch(r"course_(\d+)_([a-f0-9]{16})", name)
            if not match: continue
            docs = documents(int(match[1]), db)
            live = {f"{doc.id}:{doc.version}:{i}" for doc in docs if doc.embedding_profile == match[2]
                    for i, _ in enumerate(_split(doc.content))}
            col = client.get_collection(name)
            stale = []
            offset = 0
            while True:
                batch = col.get(limit=1000, offset=offset, include=[])["ids"]
                if not batch: break
                stale.extend(key for key in batch if key not in live)
                offset += len(batch)
            for offset in range(0, len(stale), 1000):
                col.delete(ids=stale[offset:offset + 1000])
            removed += len(stale)
            if not live and match[2] != profile(): client.delete_collection(name)
        return removed
