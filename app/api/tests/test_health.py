import pytest
from httpx import ASGITransport, AsyncClient
from portfolio_api.main import app


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
