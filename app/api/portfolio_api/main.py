from collections.abc import AsyncIterator
from contextlib import asynccontextmanager
from typing import Literal

from fastapi import FastAPI, HTTPException, status
from pydantic import BaseModel
from sqlalchemy.exc import SQLAlchemyError

from portfolio_api.database import (
    check_database_connection,
    close_database,
)
from portfolio_api.environments import Environment
from portfolio_api.metrics import router as metrics_router
from portfolio_api.routes import router as portfolio_router


@asynccontextmanager
async def lifespan(_: FastAPI) -> AsyncIterator[None]:
    yield
    await close_database()


app = FastAPI(
    title="Portfolio API",
    version="0.1.0",
    docs_url="/docs",
    redoc_url=None,
    lifespan=lifespan,
)

app.include_router(portfolio_router)
app.include_router(metrics_router)


class HealthResponse(BaseModel):
    status: Literal["ok"] = "ok"
    environment: Environment


class ReadinessResponse(BaseModel):
    status: Literal["ready"] = "ready"
    environment: Environment


@app.get(
    "/{environment}/api/health/live",
    response_model=HealthResponse,
    tags=["health"],
)
async def liveness(environment: Environment) -> HealthResponse:
    return HealthResponse(environment=environment)


@app.get(
    "/{environment}/api/health/ready",
    response_model=ReadinessResponse,
    tags=["health"],
)
async def readiness(
    environment: Environment,
) -> ReadinessResponse:
    try:
        await check_database_connection()
    except (OSError, SQLAlchemyError) as error:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="database unavailable",
        ) from error

    return ReadinessResponse(environment=environment)
