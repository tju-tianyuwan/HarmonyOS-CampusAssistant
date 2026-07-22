"""Mock ASR：返回预置课堂文本，保证无服务商账号时可完整联调演示。"""
from .base import ASRProvider, ASRResult

_SCRIPT = [
    "同学们好，今天我们学习数据结构中的二叉树。",
    "二叉树是每个节点最多有两个子节点的树形结构，分别称为左子树和右子树。",
    "二叉树的遍历方式主要有三种：前序遍历、中序遍历和后序遍历。",
    "前序遍历的顺序是：根节点、左子树、右子树，常用于复制树结构。",
    "中序遍历的顺序是：左子树、根节点、右子树，对二叉搜索树进行中序遍历可以得到有序序列。",
    "后序遍历的顺序是：左子树、右子树、根节点，常用于释放树的内存。",
    "接下来我们看完全二叉树的定义，它常用于实现堆结构。",
    "大家注意，这部分是期末考试的重点内容，务必掌握三种遍历的递归与非递归实现。",
]

_CHUNK_MS = 60_000


class MockASRProvider(ASRProvider):
    async def transcribe_chunk(self, audio: bytes, seq: int, fmt: str = "pcm") -> ASRResult:
        text = _SCRIPT[seq % len(_SCRIPT)]
        return ASRResult(text=text, start_ms=seq * _CHUNK_MS, end_ms=(seq + 1) * _CHUNK_MS)
