"""ASR 适配层：统一接口，服务商可插拔。"""
from abc import ABC, abstractmethod
from dataclasses import dataclass


@dataclass
class ASRResult:
    text: str
    start_ms: int
    end_ms: int


class ASRError(RuntimeError):
    """可安全返回给客户端的 ASR 配置或调用错误。"""


class ASRProvider(ABC):
    """提交一个音频分片，返回该分片的转写结果。"""

    @abstractmethod
    async def transcribe_chunk(self, audio: bytes, seq: int, fmt: str = "pcm") -> ASRResult: ...
