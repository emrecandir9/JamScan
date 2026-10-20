"""Interface between FastAPI and the album recognition algorithm."""

from typing import Literal

from pydantic import BaseModel, Field


class RecognitionCandidate(BaseModel):
    """An album candidate returned by the recognition algorithm."""

    discogs_id: int = Field(gt=0)
    score: float


class RecognitionResult(BaseModel):
    """Normalized recognition response for the mobile application."""

    status: Literal["matched", "needs_review", "not_found"]
    candidates: list[RecognitionCandidate]


class RecognitionError(Exception):
    """Controlled failure of the recognition component."""

    def __init__(self, message: str, status_code: int = 502) -> None:
        super().__init__(message)
        self.status_code = status_code


def recognize_image(image_data: bytes) -> RecognitionResult:
    """Recognize an album cover.

    S2-03 will supply the actual image recognition implementation.
    Until connected, no recognition results are fabricated.
    """
    raise RecognitionError(
        "Recognition component is not configured",
        status_code=503,
    )
