"""HTTP API for album-cover recognition."""

from typing import Annotated

from fastapi import APIRouter, File, Form, HTTPException, Request, UploadFile, status
from pydantic import BaseModel

from app.recognition.matcher import Decision
from app.recognition.preprocess import InvalidImageError
from app.recognition.service import RecognitionResult, Recognizer

router = APIRouter(tags=["recognition"])


class CandidateOut(BaseModel):
    release_id: str
    artist: str
    title: str
    year: int | None
    score: float


class QualityOut(BaseModel):
    sharpness: float
    brightness: float


class RecognitionOut(BaseModel):
    decision: Decision
    candidates: list[CandidateOut]
    quality: QualityOut
    model_id: str
    timings_ms: dict[str, float]


def get_recognizer(request: Request) -> Recognizer:
    recognizer: Recognizer | None = getattr(request.app.state, "recognizer", None)
    if recognizer is None:
        raise HTTPException(
            status.HTTP_503_SERVICE_UNAVAILABLE,
            "Recognition is not configured: the model or reference index is missing.",
        )
    return recognizer


@router.post("/recognitions")
def recognize(
    request: Request,
    image: Annotated[UploadFile, File(description="Album-cover photo (JPEG/PNG)")],
    skip_quality_check: Annotated[bool, Form()] = False,
) -> RecognitionOut:
    """Identify an album cover and return ranked candidates.

    ``decision`` is ``match`` (first candidate is the album), ``needs_review``
    (let the user choose), ``no_match`` (offer manual search) or
    ``poor_quality`` (ask for a sharper photo, or resend with
    ``skip_quality_check``).
    """
    recognizer = get_recognizer(request)
    limit = request.app.state.recognition_settings.max_upload_bytes
    data = image.file.read(limit + 1)
    if len(data) > limit:
        raise HTTPException(
            status.HTTP_413_CONTENT_TOO_LARGE, "The image is larger than 10 MB."
        )
    try:
        result = recognizer.recognize(data, skip_quality_check=skip_quality_check)
    except InvalidImageError as error:
        raise HTTPException(
            status.HTTP_422_UNPROCESSABLE_CONTENT, str(error)
        ) from error
    return _to_response(result, recognizer.model_id)


def _to_response(result: RecognitionResult, model_id: str) -> RecognitionOut:
    return RecognitionOut(
        decision=result.decision,
        candidates=[
            CandidateOut(
                release_id=c.entry.release_id,
                artist=c.entry.artist,
                title=c.entry.title,
                year=c.entry.year,
                score=round(max(c.score, 0.0), 4),
            )
            for c in result.candidates
        ],
        quality=QualityOut(
            sharpness=round(result.quality.sharpness, 1),
            brightness=round(result.quality.brightness, 1),
        ),
        model_id=model_id,
        timings_ms=result.timings_ms,
    )
