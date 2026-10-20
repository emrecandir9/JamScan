"""FastAPI routes for album metadata and music previews."""

import os

import httpx
from fastapi import APIRouter, File, HTTPException, Path, Query, UploadFile

from app.services.discogs import DiscogsError, get_release, search_releases
from app.services.itunes import ITunesError, get_track_preview
from app.services.recognition import (
    RecognitionError,
    RecognitionResult,
    recognize_image,
)


router = APIRouter(tags=["releases"])

MAX_PREVIEW_LOOKUPS = 5


def _discogs_token() -> str:
    """Read Discogs credentials from the environment."""
    return os.getenv("DISCOGS_TOKEN", "").strip()


@router.get("/releases/search")
def search_release_candidates(
    query: str = Query(min_length=1, max_length=150),
) -> dict:
    """Search Discogs for matching music releases."""
    try:
        with httpx.Client() as client:
            results = search_releases(client, query, _discogs_token())
    except DiscogsError as exc:
        raise HTTPException(
            status_code=exc.status_code,
            detail=str(exc),
        ) from exc

    return {"results": results}


@router.get("/releases/{release_id}")
def get_release_details(
    release_id: int = Path(gt=0),
    country: str = Query(default="FR", pattern=r"^[A-Z]{2}$"),
) -> dict:
    """Return Discogs metadata enriched with available iTunes previews."""
    try:
        with httpx.Client() as client:
            album = get_release(client, release_id, _discogs_token())

            # Preserve the complete Discogs tracklist.
            tracks = album["tracks"]
            for track in tracks:
                track["preview_url"] = None
                track["track_view_url"] = None

            checked = 0
            available = 0
            preview_failed = False

            # Bound the number of external requests.
            for track in tracks[:MAX_PREVIEW_LOOKUPS]:
                checked += 1

                try:
                    preview = get_track_preview(
                        client,
                        artist=album["artist"],
                        track_title=track["title"],
                        album_title=album["title"],
                        country=country,
                    )
                except ITunesError:
                    # Metadata remains available if iTunes fails.
                    preview_failed = True
                    break

                if preview is not None:
                    track["preview_url"] = preview["preview_url"]
                    track["track_view_url"] = preview["track_view_url"]
                    available += 1

    except DiscogsError as exc:
        raise HTTPException(
            status_code=exc.status_code,
            detail=str(exc),
        ) from exc

    if preview_failed:
        preview_status = "partial" if available else "service_unavailable"
    elif available:
        preview_status = "available"
    else:
        preview_status = "none_found"

    album["preview_status"] = preview_status
    album["previews_checked"] = checked
    album["previews_available"] = available
    album["preview_lookup_limit"] = MAX_PREVIEW_LOOKUPS

    return album


# Maximum accepted album-cover image size: 10 MiB.
MAX_IMAGE_BYTES = 10 * 1024 * 1024


def _detect_image_type(data: bytes) -> str | None:
    """Identify common image formats from their file signatures."""
    if data.startswith(b"\xff\xd8\xff"):
        return "image/jpeg"

    if data.startswith(b"\x89PNG\r\n\x1a\n"):
        return "image/png"

    if len(data) >= 12 and data[:4] == b"RIFF" and data[8:12] == b"WEBP":
        return "image/webp"

    return None


@router.post("/recognize", response_model=RecognitionResult)
def recognize_album(image: UploadFile = File(...)) -> RecognitionResult:
    """Validate and forward an album-cover image for recognition."""
    supported_types = {"image/jpeg", "image/png", "image/webp"}

    if image.content_type not in supported_types:
        raise HTTPException(
            status_code=415,
            detail="Unsupported image format",
        )

    # Read only up to the configured size limit plus one byte.
    image_data = image.file.read(MAX_IMAGE_BYTES + 1)

    if not image_data:
        raise HTTPException(
            status_code=400,
            detail="Uploaded image is empty",
        )

    if len(image_data) > MAX_IMAGE_BYTES:
        raise HTTPException(
            status_code=413,
            detail="Uploaded image is too large",
        )

    # Do not trust only the content type declared by the client.
    detected_type = _detect_image_type(image_data)

    if detected_type != image.content_type:
        raise HTTPException(
            status_code=415,
            detail="Invalid image format",
        )

    try:
        return recognize_image(image_data)
    except RecognitionError as exc:
        raise HTTPException(
            status_code=exc.status_code,
            detail=str(exc),
        ) from exc
