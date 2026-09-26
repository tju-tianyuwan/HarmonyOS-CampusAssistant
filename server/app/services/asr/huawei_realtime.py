"""Huawei SIS continuous WebSocket recognition; credentials stay on the server."""
import asyncio
import json
import re
from urllib.parse import urlsplit

from huaweicloudsdkcore.auth.credentials import BasicCredentials
from huaweicloudsdkcore.sdk_request import SdkRequest
from huaweicloudsdkcore.signer.signer import Signer
from websockets.asyncio.client import connect
from websockets.exceptions import InvalidStatus

from ...config import settings
from .base import ASRError


class HuaweiRealtimeStream:
    """One bounded continuous recording window, including interim utterances."""

    def __init__(self):
        self.socket = None

    @staticmethod
    def connection():
        missing = [key.upper() for key in ("sis_ak", "sis_sk", "sis_project_id", "sis_region",
                                           "sis_realtime_property") if not getattr(settings, key).strip()]
        if missing:
            raise ASRError("华为云实时识别配置缺失：" + ", ".join(missing))
        if (settings.asr_sample_rate, settings.asr_channels, settings.asr_sample_width) != (16000, 1, 2):
            raise ASRError("实时识别要求 16000 Hz 单声道 16 位 PCM")
        endpoint = settings.sis_realtime_endpoint.strip() or f"wss://sis-ext.{settings.sis_region.strip()}.myhuaweicloud.com"
        parts = urlsplit(endpoint)
        if (parts.scheme != "wss" or not parts.hostname or parts.username or parts.password
                or parts.query or parts.fragment or parts.path not in ("", "/")):
            raise ASRError("SIS_REALTIME_ENDPOINT 必须是 wss:// 主机地址，不带路径或查询参数")
        project = settings.sis_project_id.strip()
        if not re.fullmatch(r"[a-zA-Z0-9_-]+", project):
            raise ASRError("SIS_PROJECT_ID 格式错误")
        path = f"/v1/{project}/rasr/continue-stream"
        request = SdkRequest(method="GET", schema="https", host=parts.netloc, resource_path=path,
                             query_params=[], header_params={}, body="")
        Signer(BasicCredentials(settings.sis_ak.strip(), settings.sis_sk.strip(), project)).sign(request)
        # websockets supplies Host itself; duplicate Host headers break APIG authentication.
        headers = {k: v for k, v in request.header_params.items() if k.lower() != "host"}
        return f"wss://{parts.netloc}{path}", headers

    async def __aenter__(self):
        url, headers = self.connection()
        try:
            self.socket = await connect(url, additional_headers=headers, open_timeout=10,
                                        close_timeout=3, max_size=1024 * 1024, max_queue=16)
            config = {"audio_format": "pcm16k16bit", "property": settings.sis_realtime_property.strip(),
                      "interim_results": "yes", "add_punc": settings.sis_add_punc,
                      "digit_norm": settings.sis_digit_norm, "need_word_info": "no"}
            if settings.sis_vocabulary_id.strip():
                config["vocabulary_id"] = settings.sis_vocabulary_id.strip()
            await self.socket.send(json.dumps({"command": "START", "config": config}))
            event = await self.receive(timeout=15)
            if event.get("resp_type") != "START":
                raise ASRError("华为云未确认实时识别开始")
            return self
        except InvalidStatus as exc:
            await self.close()
            status = exc.response.status_code
            if status in (401, 403):
                raise ASRError(f"华为云实时识别鉴权失败（HTTP {status}），请检查 AK/SK、区域项目及 SIS 权限") from None
            raise ASRError(f"华为云实时识别连接失败（HTTP {status}）") from None
        except BaseException as exc:
            await self.close()
            if isinstance(exc, (ASRError, asyncio.CancelledError)):
                raise
            raise ASRError("连接华为云实时识别失败，请检查网络和实时识别服务配置") from None

    async def close(self):
        if self.socket is not None:
            await self.socket.close()
            self.socket = None

    async def __aexit__(self, *_):
        await self.close()

    async def send_audio(self, audio: bytes):
        await self.socket.send(audio)

    async def end(self):
        await self.socket.send(json.dumps({"command": "END", "cancel": "false"}))

    async def receive(self, timeout=25):
        try:
            event = json.loads(await asyncio.wait_for(self.socket.recv(), timeout))
        except asyncio.CancelledError:
            raise
        except Exception:
            raise ASRError("华为云实时识别连接中断或响应超时，录音缓存可重试") from None
        if not isinstance(event, dict):
            raise ASRError("华为云返回了无效的实时识别响应")
        if event.get("resp_type") in ("ERROR", "FATAL_ERROR"):
            code = str(event.get("error_code", "unknown"))
            safe_code = code if re.fullmatch(r"[A-Za-z0-9_.-]{1,50}", code) else "unknown"
            raise ASRError(f"华为云实时识别失败（{safe_code}），请检查服务开通、权限和识别模型")
        return event


class RealtimeTranscript:
    """Replace interim hypotheses and deduplicate repeated final utterances."""

    def __init__(self):
        self.final = {}
        self.interim = {}

    def update(self, event):
        segments = event.get("segments", [])
        if not isinstance(segments, list):
            raise ASRError("华为云实时识别分段格式无效")
        for segment in segments:
            start = int(segment["start_time"])
            end = int(segment["end_time"])
            text = segment.get("result", {}).get("text", "")
            if start < 0 or end < start or not isinstance(text, str):
                raise ASRError("华为云实时识别分段无效")
            if segment.get("is_final") is True:
                self.final[start] = (end, text)
                self.interim.pop(start, None)
            elif start not in self.final:
                self.interim[start] = (end, text)
        if sum(len(v[1]) for v in self.final.values()) > 200000:
            raise ASRError("实时识别返回文本超过限制")

    def text(self, interim=False):
        values = {**self.final, **self.interim} if interim else self.final
        return "".join(values[key][1] for key in sorted(values))
