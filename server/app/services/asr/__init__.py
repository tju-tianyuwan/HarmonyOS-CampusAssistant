from ...config import settings
from .base import ASRProvider, ASRResult
from .mock import MockASRProvider

__all__ = ["ASRProvider", "ASRResult", "get_asr_provider"]

_provider: ASRProvider | None = None


def get_asr_provider() -> ASRProvider:
    global _provider
    if _provider is None:
        name = settings.asr_provider
        if name == "mock":
            _provider = MockASRProvider()
        else:
            # huawei_sis / xfyun：新增实现类后在此注册
            raise ValueError(f"未实现的 ASR provider: {name}")
    return _provider
