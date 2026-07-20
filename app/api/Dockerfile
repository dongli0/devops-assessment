# syntax=docker/dockerfile:1.7

FROM python:3.13-slim-bookworm AS builder

COPY --from=ghcr.io/astral-sh/uv:0.10.10 /uv /uvx /bin/

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PYTHON_DOWNLOADS=0

WORKDIR /app

COPY pyproject.toml uv.lock ./

RUN --mount=type=cache,target=/root/.cache/uv \
    uv sync --frozen --no-dev --no-install-project


FROM python:3.13-slim-bookworm AS runtime

ENV PATH="/app/.venv/bin:$PATH" \
    PORTFOLIO_ENVIRONMENT=dev \
    PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1

RUN groupadd --gid 10001 portfolio \
    && useradd \
        --uid 10001 \
        --gid portfolio \
        --no-create-home \
        --shell /usr/sbin/nologin \
        portfolio

WORKDIR /app

COPY --from=builder /app/.venv /app/.venv
COPY alembic.ini ./
COPY migrations ./migrations
COPY portfolio_api ./portfolio_api

USER 10001:10001

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=3s --start-period=10s --retries=3 \
    CMD ["python", "-c", \
    "import urllib.request as u; u.urlopen('http://127.0.0.1:8000/dev/api/health/live', timeout=2)"]


CMD ["uvicorn", "portfolio_api.main:app", "--host=0.0.0.0", "--port=8000", "--workers=1"]
