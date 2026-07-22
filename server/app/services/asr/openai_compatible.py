"""OpenAI-compatible ASR：将客户端 S16LE PCM 封装成 WAV 后提交转写。"""
from io import BytesIO
import wave

from openai import APIError, AsyncOpenAI

from ...config import settings
from .base import ASRError, ASRProvider, ASRResult


def pcm_to_wav(audio: bytes, sample_rate: int, channels: int, sample_width: int) -> bytes:
    """给无文件头的 PCM 添加标准 WAV 容器，避免改变采样内容。"""
    frame_width = channels * sample_width
    if frame_width <= 0:
        raise ASRError("ASR 音频格式配置无效")
    usable_size = len(audio) - len(audio) % frame_width
    if usable_size <= 0:
        raise ASRError("音频分片为空")

    output = BytesIO()
    with wave.open(output, "wb") as wav:
        wav.setnchannels(channels)
        wav.setsampwidth(sample_width)
        wav.setframerate(sample_rate)
        wav.writeframes(audio[:usable_size])
    return output.getvalue()


class OpenAICompatibleASRProvider(ASRProvider):
    def __init__(self) -> None:
        if not settings.asr_api_key:
            raise ASRError("ASR_API_KEY 未配置")
        if not settings.asr_model:
            raise ASRError("ASR_MODEL 未配置")
        self._client = AsyncOpenAI(
            base_url=settings.asr_base_url,
            api_key=settings.asr_api_key,
            timeout=settings.asr_timeout_seconds,
            max_retries=2,
        )

    async def transcribe_chunk(self, audio: bytes, seq: int, fmt: str = "pcm") -> ASRResult:
        if fmt != "pcm":
            raise ASRError(f"暂不支持的音频格式: {fmt}")

        wav_data = pcm_to_wav(
            audio,
            sample_rate=settings.asr_sample_rate,
            channels=settings.asr_channels,
            sample_width=settings.asr_sample_width,
        )
        frame_count = len(audio) // (settings.asr_channels * settings.asr_sample_width)
        duration_ms = max(1, round(frame_count * 1000 / settings.asr_sample_rate))
        start_ms = seq * settings.asr_chunk_ms

        request: dict = {
            "file": (f"chunk_{seq}.wav", wav_data, "audio/wav"),
            "model": settings.asr_model,
            "response_format": "json",
        }
        if settings.asr_language:
            request["language"] = settings.asr_language
        if settings.asr_prompt:
            request["prompt"] = settings.asr_prompt

        try:
            response = await self._client.audio.transcriptions.create(**request)
        except APIError as exc:
            status = getattr(exc, "status_code", None)
            suffix = f"（HTTP {status}）" if status else ""
            raise ASRError(f"云端语音转写失败{suffix}") from exc
        except Exception as exc:
            raise ASRError("无法连接云端语音转写服务") from exc

        text = (getattr(response, "text", "") or "").strip()
        return ASRResult(text=text, start_ms=start_ms, end_ms=start_ms + duration_ms)
