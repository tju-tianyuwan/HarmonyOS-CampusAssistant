from ...config import settings
from .base import ASRError, ASRProvider, ASRResult
from .huawei_sis import HuaweiSISASRProvider
from .mock import MockASRProvider
from .openai_compatible import OpenAICompatibleASRProvider

__all__ = ["ASRError", "ASRProvider", "ASRResult", "get_asr_provider", "is_asr_configured"]

_provider: ASRProvider | None = None


def get_asr_provider() -> ASRProvider:
    global _provider
    if _provider is None:
        name = settings.asr_provider.strip().lower()
        if name == "mock":
            _provider = MockASRProvider()
        elif name in {"openai", "openai_compatible"}:
            _provider = OpenAICompatibleASRProvider()
        elif name in {"huawei_sis", "sis"}:
            _provider = HuaweiSISASRProvider()
        else:
            raise ASRError(f"未实现的 ASR provider: {name}")
    return _provider


def is_asr_configured() -> bool:
    name = settings.asr_provider.strip().lower()
    if name == "mock":
        return True
    if name in {"openai", "openai_compatible"}:
        return bool(settings.asr_api_key.strip() and settings.asr_model.strip())
    if name in {"huawei_sis", "sis"}:
        return all(
            value.strip()
            for value in (
                settings.sis_ak,
                settings.sis_sk,
                settings.sis_project_id,
                settings.sis_region,
                settings.sis_property,
            )
        )
    return False
