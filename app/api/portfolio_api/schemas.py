from typing import Literal

from pydantic import (
    BaseModel,
    ConfigDict,
    EmailStr,
    Field,
)


class ContactSubmission(BaseModel):
    model_config = ConfigDict(str_strip_whitespace=True)

    name: str = Field(min_length=1, max_length=80)
    email: EmailStr
    message: str = Field(min_length=1, max_length=2000)


class ContactAccepted(BaseModel):
    status: Literal["accepted"] = "accepted"
