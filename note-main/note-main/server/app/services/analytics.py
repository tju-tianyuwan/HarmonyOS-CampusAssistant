"""课堂疑问分析：记录学生问题，提取/归一化关键词并维护聚合计数。"""
import json
import re
from datetime import datetime

from sqlmodel import Session, select

from ..models import KeywordStat, QuestionLog
from .llm import chat

KEYWORD_SYSTEM = (
    "你是课堂问题关键词归一化器。请根据课程名、学生问题和本地候选词，"
    "提取 1-4 个最适合教师端展示的课程知识点关键词。"
    "要求：合并同义说法，保留课程术语，不要输出泛词。"
    '只输出 JSON：{"keywords":["关键词1","关键词2"]}。'
)

DOMAIN_TERMS = [
    "二叉搜索树", "完全二叉树", "平衡二叉树", "二叉树", "红黑树", "哈夫曼树", "B树", "B+树",
    "前序遍历", "中序遍历", "后序遍历", "层序遍历", "递归遍历", "非递归遍历",
    "时间复杂度", "空间复杂度", "算法复杂度", "稳定性", "递归", "迭代",
    "顺序表", "链表", "单链表", "双向链表", "循环链表", "栈", "队列", "优先队列",
    "哈希表", "散列表", "哈希冲突", "开放定址", "链地址法",
    "图", "邻接矩阵", "邻接表", "深度优先搜索", "广度优先搜索", "DFS", "BFS",
    "最短路径", "Dijkstra", "Floyd", "拓扑排序", "最小生成树", "Prim", "Kruskal",
    "堆", "大根堆", "小根堆", "堆排序", "快速排序", "归并排序", "插入排序", "选择排序",
    "冒泡排序", "希尔排序", "计数排序", "基数排序", "二分查找", "查找表",
]

LOCAL_ALIASES = {
    "中间顺序访问": "中序遍历",
    "左根右": "中序遍历",
    "根左右": "前序遍历",
    "左右根": "后序遍历",
    "一层一层": "层序遍历",
    "宽度优先": "广度优先搜索",
    "深搜": "深度优先搜索",
    "广搜": "广度优先搜索",
    "复杂度": "时间复杂度",
}

STOP_WORDS = [
    "为什么", "怎么", "如何", "什么", "请问", "老师", "同学", "这个", "那个", "这里",
    "一下", "是不是", "能不能", "可以", "应该", "需要", "到底", "感觉", "请", "帮我",
    "解释", "说明", "理解", "区分", "区别", "关系", "用法", "例子", "计算", "求", "和",
    "与", "以及", "或者", "还是", "一个", "一种", "如果", "时候", "里面", "中的", "的是",
    "了吗", "呢", "吗", "的", "了", "在", "是", "有", "会", "不", "又", "都", "就",
]

GENERIC_WORDS = {
    "问题", "概念", "内容", "知识点", "例题", "公式", "方法", "步骤", "代码", "实现",
    "原因", "结果", "过程", "意思", "重点", "难点", "课堂", "课程", "笔记",
}

ONE_CHAR_TERMS = {"栈", "图", "堆"}


def _unique(items: list[str], limit: int) -> list[str]:
    result: list[str] = []
    seen: set[str] = set()
    for item in items:
        cleaned = _clean_keyword(item)
        if not cleaned:
            continue
        key = cleaned.lower()
        if key in seen:
            continue
        seen.add(key)
        result.append(cleaned)
        if len(result) >= limit:
            break
    return result


def _clean_keyword(word: str) -> str:
    cleaned = re.sub(r"[\s,，。！？?；;：:\"'`~、（）()\[\]{}<>《》]+", "", word.strip())
    if (len(cleaned) < 2 and cleaned not in ONE_CHAR_TERMS) or cleaned in GENERIC_WORDS or cleaned in STOP_WORDS:
        return ""
    if len(cleaned) > 16:
        return cleaned[:16]
    return cleaned


def _split_chinese(segment: str) -> list[str]:
    text = segment
    for word in STOP_WORDS:
        text = text.replace(word, " ")
    return [part for part in re.split(r"\s+", text) if 2 <= len(part) <= 12]


def extract_local_keywords(question: str) -> list[str]:
    """轻量本地规则：课程术语表 + 同义词 + 中英文 token 粗提取。"""
    candidates: list[str] = []
    compact = question.strip()
    lower = compact.lower()

    for alias, canonical in LOCAL_ALIASES.items():
        if alias.lower() in lower:
            candidates.append(canonical)

    for term in sorted(DOMAIN_TERMS, key=len, reverse=True):
        if term.lower() in lower:
            candidates.append(term)

    for token in re.findall(r"[A-Za-z][A-Za-z0-9_+#.-]*|[\u4e00-\u9fff]+", compact):
        if re.match(r"^[A-Za-z]", token):
            candidates.append(token.upper() if len(token) <= 4 else token)
        else:
            candidates.extend(_split_chinese(token))

    return _unique(candidates, 8)


def _extract_json(raw: str) -> object:
    text = raw.strip()
    if text.startswith("```"):
        text = text.removeprefix("```json").removeprefix("```").removesuffix("```").strip()
    return json.loads(text)


async def normalize_keywords(question: str, course_name: str = "") -> list[str]:
    local = extract_local_keywords(question)
    payload = {
        "course": course_name,
        "question": question,
        "candidates": local,
    }
    try:
        raw = await chat(KEYWORD_SYSTEM, json.dumps(payload, ensure_ascii=False))
        data = _extract_json(raw)
        if isinstance(data, dict):
            words = data.get("keywords", [])
        else:
            words = data
        if isinstance(words, list):
            normalized = _unique([str(x) for x in words], 4)
            if normalized:
                return normalized
    except Exception:
        pass
    return _unique(local, 4)


async def record_question(
    db: Session,
    class_course_id: int,
    user_id: int,
    chat_session_id: int,
    question: str,
    kb_hit_count: int,
    course_name: str = "",
) -> None:
    keywords = await normalize_keywords(question, course_name)
    now = datetime.utcnow()
    db.add(
        QuestionLog(
            class_course_id=class_course_id,
            user_id=user_id,
            chat_session_id=chat_session_id,
            question=question,
            keywords=json.dumps(keywords, ensure_ascii=False),
            kb_hit_count=kb_hit_count,
            kb_missed=kb_hit_count == 0,
            created_at=now,
        )
    )
    for keyword in keywords:
        stat = db.exec(
            select(KeywordStat).where(
                KeywordStat.class_course_id == class_course_id,
                KeywordStat.keyword == keyword,
            )
        ).first()
        if stat:
            stat.count += 1
            stat.last_seen_at = now
        else:
            db.add(
                KeywordStat(
                    class_course_id=class_course_id,
                    keyword=keyword,
                    count=1,
                    last_seen_at=now,
                )
            )
    db.commit()
