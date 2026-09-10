"""LLM 客户端：OpenAI 兼容协议，base_url/api_key/model 可配。
未配置 api_key 时自动降级为 Mock（返回固定内容），保证 Demo 可离线跑通。"""
import json
import re
from typing import AsyncIterator

from openai import AsyncOpenAI

from ..config import settings

_client: AsyncOpenAI | None = None


def _get_client() -> AsyncOpenAI | None:
    global _client
    if not settings.llm_api_key:
        return None
    if _client is None:
        _client = AsyncOpenAI(base_url=settings.llm_base_url, api_key=settings.llm_api_key, timeout=45, max_retries=1)
    return _client


async def chat(system: str, user: str) -> str:
    client = _get_client()
    if client is None:
        return _mock_reply(system, user)
    resp = await client.chat.completions.create(
        model=settings.llm_model,
        messages=[{"role": "system", "content": system}, {"role": "user", "content": user}],
    )
    return resp.choices[0].message.content or ""


async def chat_stream(system: str, user: str) -> AsyncIterator[str]:
    client = _get_client()
    if client is None:
        reply = _mock_reply(system, user)
        for i in range(0, len(reply), 8):
            yield reply[i : i + 8]
        return
    stream = await client.chat.completions.create(
        model=settings.llm_model,
        messages=[{"role": "system", "content": system}, {"role": "user", "content": user}],
        stream=True,
    )
    try:
        async for chunk in stream:
            delta = chunk.choices[0].delta.content if chunk.choices else None
            if delta:
                yield delta
    finally:
        await stream.close()


def _mock_reply(system: str, user: str) -> str:
    if "[PRACTICE_GENERATOR]" in system:
        return _mock_practice_reply(user)
    if "[MAS_AGENT:analyst]" in system:
        return (
            "先把条件理清楚。以二叉树中序遍历为例，核心顺序是左子树、根节点、右子树。"
            "如果对象是二叉搜索树，这个顺序还会产生有序序列；普通二叉树则没有这一保证。"
        )
    if "[MAS_AGENT:skeptic]" in system:
        return (
            "换个条件还成立吗？小研给出的遍历顺序没有问题，但要注意“中序结果有序”依赖二叉搜索树性质。"
            "你可以试着构造一棵普通二叉树，检查其中序序列是否仍然递增。"
        )
    if "[MAS_AGENT:connector]" in system:
        return (
            "可以把它想成先整理左边书架，再处理桌面，最后整理右边书架。映射到递归代码，就是先调用左子树，"
            "再访问当前节点，最后调用右子树，这个类比能帮助记住调用顺序。"
        )
    if "[MAS_AGENT:synthesizer]" in system:
        return (
            "我们把刚才的观点收一下：中序遍历的固定规则是左、根、右；只有二叉搜索树才保证结果有序。"
            "建议你下一步手画一棵普通二叉树和一棵搜索树，分别写出中序序列进行对比。"
        )
    if "关键词" in system:
        try:
            payload = json.loads(user)
            candidates = payload.get("candidates", []) if isinstance(payload, dict) else []
            if isinstance(candidates, list) and candidates:
                return json.dumps({"keywords": candidates[:4]}, ensure_ascii=False)
        except json.JSONDecodeError:
            pass
        return json.dumps({"keywords": []}, ensure_ascii=False)
    if "提纲" in system or "outline" in system.lower():
        return (
            "# 二叉树\n\n## 一、基本概念\n- 每个节点最多两个子节点（左子树 / 右子树）\n\n"
            "## 二、遍历方式（考试重点）\n- 前序遍历：根 → 左 → 右，用于复制树\n"
            "- 中序遍历：左 → 根 → 右，二叉搜索树中序有序\n- 后序遍历：左 → 右 → 根，用于释放内存\n\n"
            "## 三、完全二叉树\n- 定义与堆结构的实现\n\n> ⚠️ 期末重点：三种遍历的递归与非递归实现"
        )
    if "评估" in system:
        return json.dumps({"relevance": 8, "correctness": 8, "structure": 7, "pass": True}, ensure_ascii=False)
    return "（Mock 回复）根据本课程知识库：二叉树的中序遍历顺序为左子树、根节点、右子树。配置 LLM_API_KEY 后将由真实模型作答。"


def _mock_practice_reply(user: str) -> str:
    start = user.find("{")
    end = user.rfind("}")
    try:
        payload = json.loads(user[start : end + 1]) if start >= 0 and end >= start else {}
    except json.JSONDecodeError:
        payload = {}

    count = payload.get("count", 5)
    count = count if isinstance(count, int) else 5
    count = max(1, min(count, 10))
    course_name = str(payload.get("course_name", "当前课程"))
    requested_topic = str(payload.get("topic", "综合"))
    requested_difficulty = str(payload.get("difficulty", "综合"))
    knowledge = payload.get("knowledge", [])

    knowledge_text = "\n".join(
        str(item.get("text", "")) for item in knowledge if isinstance(item, dict)
    ) if isinstance(knowledge, list) else ""
    first_source = next(
        (
            str(item.get("source", "课程知识库")).strip()
            for item in knowledge
            if isinstance(item, dict) and str(item.get("source", "")).strip()
        ),
        "课程知识库",
    ) if isinstance(knowledge, list) else "课程知识库"

    if "二叉树" in knowledge_text:
        templates = [
            (
                "关于二叉树的基本定义，下列说法正确的是？",
                ["每个节点必须有两个子节点", "每个节点最多有两个子节点", "所有叶子节点必须同层", "只能使用顺序存储"],
                1,
                "二叉树中每个节点最多有两个子节点，分别对应左子树和右子树。",
            ),
            (
                "二叉树中序遍历的正确访问顺序是？",
                ["根、左、右", "左、根、右", "左、右、根", "按层从左到右"],
                1,
                "中序遍历依次访问左子树、根节点和右子树。",
            ),
            (
                "对二叉搜索树进行中序遍历，通常可以得到什么结果？",
                ["节点按层分组", "所有叶子节点优先", "关键字有序序列", "树的高度序列"],
                2,
                "二叉搜索树满足左子树小于根、右子树大于根，因此中序遍历得到有序序列。",
            ),
            (
                "课程资料强调，二叉树遍历学习时应重点掌握哪一项？",
                ["只记住遍历名称", "递归与非递归实现", "只分析完全二叉树", "忽略节点访问顺序"],
                1,
                "课程资料将三种遍历的递归与非递归实现列为考试重点。",
            ),
            (
                "下列哪一项是二叉树后序遍历的访问顺序？",
                ["根、左、右", "左、根、右", "左、右、根", "右、根、左"],
                2,
                "后序遍历先访问左子树，再访问右子树，最后访问根节点。",
            ),
        ]
        difficulties = ["基础", "适中", "进阶"]
        questions = []
        for index in range(count):
            stem, options, answer, explanation = templates[index % len(templates)]
            if index >= len(templates):
                stem = f"{stem}（变式 {index + 1}）"
            questions.append(
                {
                    "type": "单选题",
                    "difficulty": requested_difficulty if requested_difficulty in difficulties else difficulties[index % 3],
                    "topic": requested_topic if requested_topic != "综合" else "二叉树",
                    "stem": stem,
                    "options": options,
                    "answer": answer,
                    "explanation": explanation,
                    "source": first_source,
                }
            )
        return json.dumps({"questions": questions}, ensure_ascii=False)

    facts: list[tuple[str, str]] = []
    if isinstance(knowledge, list):
        for item in knowledge:
            if not isinstance(item, dict):
                continue
            text = str(item.get("text", "")).strip()
            source = str(item.get("source", "课程知识库")).strip() or "课程知识库"
            for sentence in re.split(r"[。！？\n]+", text):
                normalized = sentence.strip(" -#：:")
                if len(normalized) >= 8:
                    facts.append((normalized, source))
    if not facts:
        facts.append((f"{course_name}知识库包含本课程的课堂重点", "课程知识库"))

    difficulties = ["基础", "适中", "进阶"]
    questions = []
    for index in range(count):
        fact, source = facts[index % len(facts)]
        topic = requested_topic if requested_topic != "综合" else course_name
        difficulty = (
            requested_difficulty
            if requested_difficulty in difficulties
            else difficulties[index % len(difficulties)]
        )
        answer = index % 4
        distractors = [
            "该知识点只适用于课程之外的场景",
            "课程资料明确要求忽略这一概念",
            "该结论与知识库中的定义完全相反",
        ]
        options = distractors[:]
        options.insert(answer, fact)
        questions.append(
            {
                "type": "单选题",
                "difficulty": difficulty,
                "topic": topic,
                "stem": f"根据课程知识库，第 {index + 1} 题中哪项表述与资料一致？",
                "options": options,
                "answer": answer,
                "explanation": f"知识库片段指出：{fact}。",
                "source": source,
            }
        )
    return json.dumps({"questions": questions}, ensure_ascii=False)
