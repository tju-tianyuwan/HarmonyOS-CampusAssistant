"""CPU inference with a predownloaded multilingual Whisper model."""
import asyncio
from pathlib import Path
from threading import Lock

from ...config import settings
from .base import ASRError, ASRProvider, ASRResult


def model_path() -> Path:
    return Path(settings.data_dir) / "models" / ("whisper-" + settings.asr_local_model)


class LocalASRProvider(ASRProvider):
    def __init__(self):
        self._model = None
        self._lock = Lock()

    def _transcribe(self, audio: bytes, prompt: str = "") -> str:
        import numpy as np
        from faster_whisper import WhisperModel
        if not (model_path() / "model.bin").is_file():
            raise ASRError("本地语音模型未安装，请在服务端运行 python prepare_models.py")
        if (settings.asr_sample_rate, settings.asr_channels, settings.asr_sample_width) != (16000, 1, 2):
            raise ASRError("本地转写要求 16000 Hz 单声道 16 位 PCM")
        with self._lock:
            if self._model is None:
                self._model = WhisperModel(str(model_path()), device="cpu", compute_type="int8",
                                           cpu_threads=settings.asr_local_threads, local_files_only=True)
            samples = np.frombuffer(audio, dtype="<i2").astype(np.float32) / 32768.0
            segments, _ = self._model.transcribe(samples, language=settings.asr_language or None,
                beam_size=3, vad_filter=True, condition_on_previous_text=False,
                initial_prompt=(settings.asr_prompt + " " + prompt).strip()[:1000] or None)
            return "".join(segment.text for segment in segments).strip()

    async def transcribe_chunk(self, audio: bytes, seq: int, fmt: str = "pcm", prompt: str = "") -> ASRResult:
        if fmt != "pcm" or not audio or len(audio) % 2:
            raise ASRError("需要完整的 16 位 PCM 音频分片")
        try:
            text = await asyncio.to_thread(self._transcribe, audio, prompt)
        except ASRError:
            raise
        except Exception as exc:
            raise ASRError("本地语音识别失败，请检查模型文件及服务端日志") from exc
        start = seq * settings.asr_chunk_ms
        return ASRResult(text=text, start_ms=start, end_ms=start + round(len(audio) / 32))
