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

    asr_provider: str = "mock"
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


settings = Settings()
