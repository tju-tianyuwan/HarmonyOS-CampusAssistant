"""华为云 SIS 短语音识别适配器。"""
import asyncio
import base64

from huaweicloudsdkcore.auth.credentials import BasicCredentials
from huaweicloudsdkcore.exceptions import exceptions
from huaweicloudsdkcore.http.http_config import HttpConfig
from huaweicloudsdkcore.region.region import Region
from huaweicloudsdksis.v1 import Config, PostShortAudioReq, RecognizeShortAudioRequest, SisClient
from huaweicloudsdksis.v1.region.sis_region import SisRegion

from ...config import settings
from .base import ASRError, ASRProvider, ASRResult


class HuaweiSISASRProvider(ASRProvider):
    """通过华为云 SIS ``/asr/short-audio`` 接口识别 PCM 分片。"""

    def __init__(self) -> None:
        missing = [
            name
            for name, value in (
                ("SIS_AK", settings.sis_ak),
                ("SIS_SK", settings.sis_sk),
                ("SIS_PROJECT_ID", settings.sis_project_id),
                ("SIS_REGION", settings.sis_region),
                ("SIS_PROPERTY", settings.sis_property),
            )
            if not value.strip()
        ]
        if missing:
            raise ASRError(f"华为云 SIS 配置缺失：{', '.join(missing)}")

        credentials = BasicCredentials(
            settings.sis_ak.strip(),
            settings.sis_sk.strip(),
            settings.sis_project_id.strip(),
        )
        http_config = HttpConfig(timeout=settings.asr_timeout_seconds, retry_times=2)
        self._client = (
            SisClient.new_builder()
            .with_credentials(credentials)
            .with_region(self._build_region())
            .with_http_config(http_config)
            .build()
        )

    @staticmethod
    def _build_region() -> Region:
        region_id = settings.sis_region.strip()
        endpoint = settings.sis_endpoint.strip()
        if endpoint:
            return Region(region_id, endpoint.rstrip("/"))
        try:
            return SisRegion.value_of(region_id)
        except KeyError as exc:
            raise ASRError(
                f"华为云 SIS SDK 暂未内置区域 {region_id}，请同时配置 SIS_ENDPOINT"
            ) from exc

    async def transcribe_chunk(self, audio: bytes, seq: int, fmt: str = "pcm") -> ASRResult:
        if fmt != "pcm":
            raise ASRError(f"华为云 SIS 暂不支持当前音频格式：{fmt}")
        if settings.asr_channels != 1:
            raise ASRError("华为云 SIS 当前接入要求 ASR_CHANNELS=1")
        if settings.asr_sample_rate != 16000 or settings.asr_sample_width != 2:
            raise ASRError(
                "当前 SIS 配置 pcm16k16bit 要求 ASR_SAMPLE_RATE=16000、ASR_SAMPLE_WIDTH=2"
            )

        frame_width = settings.asr_channels * settings.asr_sample_width
        usable_size = len(audio) - len(audio) % frame_width
        if usable_size <= 0:
            raise ASRError("音频分片为空")
        pcm = audio[:usable_size]
        encoded_audio = base64.b64encode(pcm).decode("ascii")
        if len(encoded_audio) > 4 * 1024 * 1024:
            raise ASRError("华为云 SIS 短语音请求的 Base64 音频不能超过 4 MB")

        config_args: dict[str, str] = {
            "audio_format": settings.sis_audio_format.strip(),
            "_property": settings.sis_property.strip(),
            "add_punc": settings.sis_add_punc.strip(),
            "digit_norm": settings.sis_digit_norm.strip(),
            "need_word_info": "no",
        }
        if settings.sis_vocabulary_id.strip():
            config_args["vocabulary_id"] = settings.sis_vocabulary_id.strip()

        request = RecognizeShortAudioRequest(
            body=PostShortAudioReq(
                config=Config(**config_args),
                data=encoded_audio,
            )
        )
        try:
            response = await asyncio.to_thread(self._client.recognize_short_audio, request)
        except exceptions.ClientRequestException as exc:
            if exc.error_code == "SIS.0004":
                raise ASRError(
                    "华为云 SIS 尚未开通：请在控制台为区域 "
                    f"{settings.sis_region} 开通“一句话识别”服务，并确认 SIS_PROJECT_ID 属于该区域"
                ) from exc
            details = f"HTTP {exc.status_code}"
            if exc.error_code:
                details += f"，错误码 {exc.error_code}"
            raise ASRError(f"华为云 SIS 识别失败（{details}）") from exc
        except Exception as exc:
            raise ASRError("连接华为云 SIS 失败") from exc

        result = getattr(response, "result", None)
        text = (getattr(result, "text", "") or "").strip()
        frame_count = usable_size // frame_width
        duration_ms = max(1, round(frame_count * 1000 / settings.asr_sample_rate))
        start_ms = seq * settings.asr_chunk_ms
        return ASRResult(text=text, start_ms=start_ms, end_ms=start_ms + duration_ms)
