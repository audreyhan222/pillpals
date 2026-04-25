from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    app_name: str = "pillpals-backend"
    secret_key: str = "dev-secret-change-me"
    access_token_exp_minutes: int = 60 * 24 * 7
    database_url: str = "sqlite:///./pillpals.db"
    cors_allow_origins: str = "*"

    # Push notifications (FCM -> APNs)
    # Either a path to a Firebase service account JSON file, or the JSON itself.
    firebase_service_account_json: str = ""
    enable_dev_push_endpoints: bool = True


settings = Settings()

