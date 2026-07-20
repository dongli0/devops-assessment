import pytest
from httpx import ASGITransport, AsyncClient
from portfolio_api import main as main_module
from portfolio_api.main import app
from sqlalchemy.exc import SQLAlchemyError


@pytest.mark.asyncio
@pytest.mark.parametrize(
    "environment",
    ["dev", "test", "perf", "staging", "production"],
)
async def test_liveness_for_supported_environments(environment: str) -> None:
    transport = ASGITransport(app=app)

    async with AsyncClient(
        transport=transport,
        base_url="http://test",
    ) as client:
        response = await client.get(f"/{environment}/api/health/live")

    assert response.status_code == 200
    assert response.json() == {
        "status": "ok",
        "environment": environment,
    }


@pytest.mark.asyncio
async def test_liveness_rejects_unknown_environment() -> None:
    transport = ASGITransport(app=app)

    async with AsyncClient(
        transport=transport,
        base_url="http://test",
    ) as client:
        response = await client.get("/qa/api/health/live")

    assert response.status_code == 422


@pytest.mark.asyncio
async def test_readiness_checks_database() -> None:
    transport = ASGITransport(app=app)

    async with AsyncClient(
        transport=transport,
        base_url="http://test",
    ) as client:
        response = await client.get("/dev/api/health/ready")

    assert response.status_code == 200
    assert response.json() == {
        "status": "ready",
        "environment": "dev",
    }


@pytest.mark.asyncio
async def test_readiness_reports_database_failure(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    async def unavailable_database() -> None:
        raise SQLAlchemyError("database unavailable")

    monkeypatch.setattr(
        main_module,
        "check_database_connection",
        unavailable_database,
    )

    transport = ASGITransport(app=app)

    async with AsyncClient(
        transport=transport,
        base_url="http://test",
    ) as client:
        response = await client.get("/dev/api/health/ready")

    assert response.status_code == 503
    assert response.json() == {
        "detail": "database unavailable",
    }
