from ...config import settings
from .base import ASRError, ASRProvider, ASRResult
from .huawei_sis import HuaweiSISASRProvider
from .mock import MockASRProvider
from .local import LocalASRProvider, model_path
from .openai_compatible import OpenAICompatibleASRProvider

__all__ = ["ASRError", "ASRProvider", "ASRResult", "get_asr_provider", "is_asr_configured"]

_provider: ASRProvider | None = None


def get_asr_provider() -> ASRProvider:
    global _provider
    if _provider is None:
        name = settings.asr_provider.strip().lower()
        if name == "mock":
            _provider = MockASRProvider()
        elif name == "local":
            _provider = LocalASRProvider()
        elif name in {"openai", "openai_compatible"}:
            _provider = OpenAICompatibleASRProvider()
        elif name in {"huawei_sis", "sis"}:
            _provider = HuaweiSISASRProvider()
        elif name == "huawei_sis_realtime":
            raise ASRError("当前使用实时识别，请升级客户端并通过实时录音通道提交音频")
        else:
            raise ASRError(f"未实现的 ASR provider: {name}")
    return _provider


def is_asr_configured() -> bool:
    name = settings.asr_provider.strip().lower()
    if name == "mock":
        return False
    if name == "local":
        return (model_path() / "model.bin").is_file()
    if name in {"openai", "openai_compatible"}:
        return bool(settings.asr_api_key.strip() and settings.asr_model.strip())
    if name in {"huawei_sis", "sis", "huawei_sis_realtime"}:
        return all(
            value.strip()
            for value in (
                settings.sis_ak,
                settings.sis_sk,
                settings.sis_project_id,
                settings.sis_region,
                settings.sis_realtime_property if name == "huawei_sis_realtime" else settings.sis_property,
            )
        )
    return False
