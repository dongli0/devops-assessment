from portfolio_api.config import Settings
from portfolio_api.environments import Environment


def test_settings_have_safe_local_defaults() -> None:
    settings = Settings(_env_file=None)

    assert settings.environment is Environment.DEV
    assert settings.database_url.get_secret_value() == "sqlite+aiosqlite:///:memory:"
    assert settings.log_level == "INFO"


def test_settings_load_environment_variables(
    monkeypatch,
) -> None:
    database_url = "postgresql+asyncpg://portfolio:demo-password@database/portfolio"

    monkeypatch.setenv(
        "PORTFOLIO_ENVIRONMENT",
        "staging",
    )
    monkeypatch.setenv(
        "PORTFOLIO_DATABASE_URL",
        database_url,
    )

    settings = Settings(_env_file=None)

    assert settings.environment is Environment.STAGING
    assert settings.database_url.get_secret_value() == database_url
    assert "demo-password" not in repr(settings.database_url)
