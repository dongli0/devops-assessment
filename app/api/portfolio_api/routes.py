from typing import Annotated

from fastapi import APIRouter, Depends, status
from sqlalchemy.ext.asyncio import AsyncSession

from portfolio_api.database import get_database_session
from portfolio_api.environments import Environment
from portfolio_api.models import ContactMessage
from portfolio_api.schemas import (
    ContactAccepted,
    ContactSubmission,
)

router = APIRouter(
    prefix="/{environment}/api",
    tags=["portfolio"],
)

DatabaseSession = Annotated[
    AsyncSession,
    Depends(get_database_session),
]


@router.post(
    "/contact",
    response_model=ContactAccepted,
    status_code=status.HTTP_202_ACCEPTED,
)
async def submit_contact(
    environment: Environment,
    submission: ContactSubmission,
    session: DatabaseSession,
) -> ContactAccepted:
    session.add(
        ContactMessage(
            environment=environment.value,
            name=submission.name,
            email=str(submission.email),
            message=submission.message,
        )
    )
    await session.commit()

    return ContactAccepted()
