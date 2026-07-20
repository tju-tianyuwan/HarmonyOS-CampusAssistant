"""LLM 客户端：OpenAI 兼容协议，base_url/api_key/model 可配。
未配置 api_key 时自动降级为 Mock（返回固定内容），保证 Demo 可离线跑通。"""
import json
from typing import AsyncIterator

from openai import AsyncOpenAI

from ..config import settings

_client: AsyncOpenAI | None = None


def _get_client() -> AsyncOpenAI | None:
    global _client
    if not settings.llm_api_key:
        return None
    if _client is None:
        _client = AsyncOpenAI(base_url=settings.llm_base_url, api_key=settings.llm_api_key)
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
    async for chunk in stream:
        delta = chunk.choices[0].delta.content if chunk.choices else None
        if delta:
            yield delta


def _mock_reply(system: str, user: str) -> str:
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
