import json
from typing import Any

from .llm import chat


class PracticeGenerationError(ValueError):
    pass


PRACTICE_SYSTEM = """[PRACTICE_GENERATOR]
你是课程选择题出题器。只能依据用户提供的“课程知识库片段”出题，不得引入片段之外的课程事实。

输出要求：
1. 只输出一个 JSON 对象，不要使用 Markdown 代码块或附加说明。
2. JSON 格式必须为：
   {"questions":[{"type":"单选题","difficulty":"基础|适中|进阶","topic":"知识点",
   "stem":"题干","options":["A内容","B内容","C内容","D内容"],"answer":0,
   "explanation":"答案解析","source":"来源名称"}]}
3. 每题必须恰好四个互不相同的选项，answer 使用 0 到 3 的整数表示正确选项。
4. 题目、选项和解析必须能由知识库片段直接推导；避免纯记忆式重复，干扰项要合理。
5. source 只能填写输入中出现过的来源名称。
6. 严格生成用户要求的题目数量，不要重复题干。
"""


def _json_payload(raw: str) -> Any:
    text = raw.strip()
    start = text.find("{")
    end = text.rfind("}")
    if start < 0 or end < start:
        raise PracticeGenerationError("模型未返回 JSON 对象")
    try:
        return json.loads(text[start : end + 1])
    except json.JSONDecodeError as exc:
        raise PracticeGenerationError("模型返回的 JSON 无效") from exc


def _answer_index(value: Any) -> int:
    if isinstance(value, int) and not isinstance(value, bool):
        return value
    if isinstance(value, str):
        normalized = value.strip().upper()
        if normalized in ("A", "B", "C", "D"):
            return ord(normalized) - ord("A")
        if normalized in ("0", "1", "2", "3"):
            return int(normalized)
    raise PracticeGenerationError("正确答案必须是 0 到 3")


def parse_questions(
    raw: str,
    expected_count: int,
    default_topic: str,
    default_difficulty: str,
    allowed_sources: list[str],
) -> list[dict[str, Any]]:
    payload = _json_payload(raw)
    items = payload.get("questions") if isinstance(payload, dict) else None
    if not isinstance(items, list):
        raise PracticeGenerationError("questions 字段缺失")

    fallback_source = allowed_sources[0] if allowed_sources else "课程知识库"
    questions: list[dict[str, Any]] = []
    stems: set[str] = set()
    for item in items:
        if not isinstance(item, dict):
            continue
        stem = str(item.get("stem", "")).strip()
        explanation = str(item.get("explanation", "")).strip()
        options_raw = item.get("options")
        if not stem or not explanation or not isinstance(options_raw, list):
            continue
        options = [str(option).strip() for option in options_raw]
        if len(options) != 4 or any(not option for option in options) or len(set(options)) != 4:
            continue
        answer = _answer_index(item.get("answer"))
        if answer < 0 or answer >= len(options):
            raise PracticeGenerationError("正确答案索引越界")
        if stem in stems:
            continue
        stems.add(stem)

        source = str(item.get("source", "")).strip()
        if source not in allowed_sources:
            source = fallback_source
        topic = str(item.get("topic", "")).strip() or default_topic
        difficulty = str(item.get("difficulty", "")).strip() or default_difficulty
        if difficulty not in ("基础", "适中", "进阶"):
            difficulty = default_difficulty if default_difficulty in ("基础", "适中", "进阶") else "适中"

        questions.append(
            {
                "id": len(questions) + 1,
                "type": "单选题",
                "difficulty": difficulty,
                "topic": topic,
                "stem": stem,
                "options": options,
                "answer": answer,
                "explanation": explanation,
                "source": source,
            }
        )
        if len(questions) == expected_count:
            break

    if len(questions) != expected_count:
        raise PracticeGenerationError(f"模型只生成了 {len(questions)} 道有效题目")
    return questions


async def generate_choice_questions(
    course_name: str,
    mode: str,
    topic: str,
    difficulty: str,
    requirements: str,
    count: int,
    knowledge: list[dict[str, str]],
) -> list[dict[str, Any]]:
    allowed_sources = list(dict.fromkeys(item.get("source", "") for item in knowledge if item.get("source", "")))
    payload = {
        "course_name": course_name,
        "mode": mode,
        "topic": topic,
        "difficulty": difficulty,
        "requirements": requirements or "无额外要求",
        "count": count,
        "knowledge": knowledge,
    }
    user_prompt = json.dumps(payload, ensure_ascii=False)
    raw = await chat(PRACTICE_SYSTEM, user_prompt)
    try:
        return parse_questions(raw, count, topic, difficulty, allowed_sources)
    except PracticeGenerationError:
        repair_prompt = (
            "上一次输出不符合格式或题目数量要求。请重新生成，只返回合法 JSON。\n\n"
            + user_prompt
        )
        repaired = await chat(PRACTICE_SYSTEM, repair_prompt)
        return parse_questions(repaired, count, topic, difficulty, allowed_sources)
