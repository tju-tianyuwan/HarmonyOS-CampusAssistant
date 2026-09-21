from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    llm_base_url: str = "https://api.deepseek.com/v1"
    llm_api_key: str = ""
    llm_model: str = "deepseek-chat"

    embed_base_url: str = ""
    embed_api_key: str = ""
    embed_model: str = ""
    rag_max_distance: float = 1.0

    asr_provider: str = "local"
    asr_local_model: str = "small"
    asr_local_threads: int = 4
    asr_base_url: str = "https://api.openai.com/v1"
    asr_api_key: str = ""
    asr_model: str = "whisper-1"
    asr_language: str = "zh"
    asr_prompt: str = ""
    asr_sample_rate: int = 16000
    asr_channels: int = 1
    asr_sample_width: int = 2
    asr_chunk_ms: int = 4000
    asr_timeout_seconds: float = 60.0

    # 华为云 SIS 短语音识别。PROJECT_ID 是区域项目 ID，不是账号 ID。
    sis_ak: str = ""
    sis_sk: str = ""
    sis_project_id: str = ""
    sis_region: str = "cn-north-4"
    sis_endpoint: str = ""
    sis_property: str = "chinese_16k_general"
    sis_audio_format: str = "pcm16k16bit"
    sis_add_punc: str = "yes"
    sis_digit_norm: str = "yes"
    sis_vocabulary_id: str = ""

    database_url: str = "sqlite:///./smartstudy.db"
    data_dir: str = "./data"

    auth_session_hours: int = 168
    smtp_host: str = ""
    smtp_port: int = 587
    smtp_username: str = ""
    smtp_password: str = ""
    smtp_from_email: str = ""
    smtp_ssl: bool = False
    smtp_starttls: bool = True
    document_max_bytes: int = 50 * 1024 * 1024
    document_max_pages: int = 100
    llm_vision_model: str = ""
    document_ocr_provider: str = "local"
    document_job_workers: int = 2
    document_queue_limit: int = 20
    document_job_retention_days: int = 7
    chroma_host: str = ""
    chroma_port: int = 8002
    chroma_ssl: bool = False
    rag_cleanup_seconds: int = 3600
    meeting_workers: int = 4
    embed_dimensions: int = 0
    meeting_idle_seconds: int = 3
    meeting_minutes_limit: int = 24000


settings = Settings()
