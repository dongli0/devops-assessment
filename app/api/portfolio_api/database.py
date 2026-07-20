from collections.abc import AsyncIterator

from sqlalchemy import text
from sqlalchemy.ext.asyncio import (
    AsyncEngine,
    AsyncSession,
    async_sessionmaker,
    create_async_engine,
)

from portfolio_api.config import get_settings


def create_database_engine() -> AsyncEngine:
    settings = get_settings()

    return create_async_engine(
        settings.database_url.get_secret_value(),
        pool_pre_ping=True,
    )


engine = create_database_engine()

session_factory = async_sessionmaker(
    bind=engine,
    expire_on_commit=False,
)


async def get_database_session() -> AsyncIterator[AsyncSession]:
    async with session_factory() as session:
        yield session


async def check_database_connection() -> None:
    async with engine.connect() as connection:
        await connection.execute(text("SELECT 1"))


async def close_database() -> None:
    await engine.dispose()
