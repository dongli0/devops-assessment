import pytest
from httpx import AsyncClient
from portfolio_api.models import ContactMessage
from sqlalchemy import select
from sqlalchemy.ext.asyncio import AsyncSession


@pytest.mark.asyncio
async def test_contact_submission_is_persisted(
    client: AsyncClient,
    database_session: AsyncSession,
) -> None:
    response = await client.post(
        "/dev/api/contact",
        json={
            "name": "Visitor",
            "email": "visitor@example.com",
            "message": "Hello from the portfolio.",
        },
    )

    assert response.status_code == 202
    assert response.json() == {"status": "accepted"}

    contact = await database_session.scalar(select(ContactMessage))

    assert contact is not None
    assert contact.environment == "dev"
    assert contact.name == "Visitor"
    assert contact.email == "visitor@example.com"
    assert contact.message == "Hello from the portfolio."


@pytest.mark.asyncio
async def test_contact_submission_rejects_invalid_input(
    client: AsyncClient,
) -> None:
    response = await client.post(
        "/dev/api/contact",
        json={
            "name": " ",
            "email": "not-an-email",
            "message": " ",
        },
    )

    assert response.status_code == 422
