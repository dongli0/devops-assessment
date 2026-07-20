from sqlalchemy import text
from sqlalchemy.ext.asyncio import AsyncEngine, create_async_engine

from portfolio_api.config import get_settings


def create_database_engine() -> AsyncEngine:
    settings = get_settings()

    return create_async_engine(
        settings.database_url.get_secret_value(),
        pool_pre_ping=True,
    )


engine = create_database_engine()


async def check_database_connection() -> None:
    async with engine.connect() as connection:
        await connection.execute(text("SELECT 1"))


async def close_database() -> None:
    await engine.dispose()
