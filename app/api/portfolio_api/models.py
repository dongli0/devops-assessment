from datetime import datetime

from sqlalchemy import DateTime, String, Text, func
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column


class Base(DeclarativeBase):
    pass


class ContactMessage(Base):
    __tablename__ = "contact_messages"

    id: Mapped[int] = mapped_column(
        primary_key=True,
        autoincrement=True,
    )
    environment: Mapped[str] = mapped_column(
        String(16),
        nullable=False,
        index=True,
    )
    name: Mapped[str] = mapped_column(
        String(80),
        nullable=False,
    )
    email: Mapped[str] = mapped_column(
        String(254),
        nullable=False,
    )
    message: Mapped[str] = mapped_column(
        Text,
        nullable=False,
    )
    created_at: Mapped[datetime] = mapped_column(
        DateTime(timezone=True),
        nullable=False,
        server_default=func.now(),
        index=True,
    )
