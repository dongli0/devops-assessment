from typing import Literal

from fastapi import FastAPI
from pydantic import BaseModel

from portfolio_api.environments import Environment

app = FastAPI(
    title="Portfolio API",
    version="0.1.0",
    docs_url="/docs",
    redoc_url=None,
)


class HealthResponse(BaseModel):
    status: Literal["ok"] = "ok"
    environment: Environment


@app.get(
    "/{environment}/api/health/live",
    response_model=HealthResponse,
    tags=["health"],
)
async def liveness(environment: Environment) -> HealthResponse:
    return HealthResponse(environment=environment)
