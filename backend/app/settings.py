from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "pillpals-backend"
    secret_key: str = "dev-secret-change-me"
    access_token_exp_minutes: int = 60 * 24 * 7
    database_url: str = "sqlite:///./pillpals.db"
    cors_allow_origins: str = "*"


settings = Settings()

