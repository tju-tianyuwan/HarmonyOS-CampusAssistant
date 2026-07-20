"""RAG：Chroma 向量库，按课程集合(class_course_id)分 collection，物理隔离。
所有读写必须携带 class_course_id，杜绝跨集合检索。"""
import chromadb

from ..config import settings

_client: chromadb.ClientAPI | None = None


def _get_client() -> chromadb.ClientAPI:
    global _client
    if _client is None:
        _client = chromadb.PersistentClient(path=f"{settings.data_dir}/chroma")
    return _client


def _collection(class_course_id: int):
    return _get_client().get_or_create_collection(name=f"cc_{class_course_id}")


def _split(text: str, size: int = 400, overlap: int = 50) -> list[str]:
    chunks: list[str] = []
    i = 0
    while i < len(text):
        chunks.append(text[i : i + size])
        i += size - overlap
    return [c for c in chunks if c.strip()]


def add_document(class_course_id: int, doc_id: str, text: str, source: str) -> int:
    """向集合知识库写入文档（提纲/优质笔记）。source 用于问答引用展示。"""
    col = _collection(class_course_id)
    # 幂等：先删旧分块
    col.delete(where={"doc_id": doc_id})
    chunks = _split(text)
    if not chunks:
        return 0
    col.add(
        ids=[f"{doc_id}#{i}" for i in range(len(chunks))],
        documents=chunks,
        metadatas=[{"doc_id": doc_id, "source": source} for _ in chunks],
    )
    return len(chunks)


def query(class_course_id: int, question: str, top_k: int = 4) -> list[dict]:
    col = _collection(class_course_id)
    if col.count() == 0:
        return []
    res = col.query(query_texts=[question], n_results=min(top_k, col.count()))
    docs = res["documents"][0] if res["documents"] else []
    metas = res["metadatas"][0] if res["metadatas"] else []
    return [{"text": d, "source": m.get("source", "")} for d, m in zip(docs, metas)]
