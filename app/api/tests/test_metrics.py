import pytest
from httpx import ASGITransport, AsyncClient
from portfolio_api.main import app


@pytest.mark.asyncio
async def test_metrics_exposes_prometheus_data() -> None:
    transport = ASGITransport(app=app)

    async with AsyncClient(
        transport=transport,
        base_url="http://test",
    ) as client:
        response = await client.get("/metrics")

    assert response.status_code == 200
    assert response.headers["content-type"].startswith("text/plain")
    assert "# HELP python_info" in response.text
