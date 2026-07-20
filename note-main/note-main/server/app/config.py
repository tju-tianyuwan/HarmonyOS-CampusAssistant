from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    llm_base_url: str = "https://api.deepseek.com/v1"
    llm_api_key: str = ""
    llm_model: str = "deepseek-chat"

    embed_base_url: str = ""
    embed_api_key: str = ""
    embed_model: str = ""

    asr_provider: str = "mock"

    database_url: str = "sqlite:///./smartstudy.db"
    data_dir: str = "./data"


settings = Settings()
