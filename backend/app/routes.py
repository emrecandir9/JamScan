"""FastAPI routes for album metadata and music previews."""

import os

import httpx
from fastapi import APIRouter, HTTPException, Path, Query

from app.services.discogs import DiscogsError, get_release, search_releases
from app.services.itunes import ITunesError, get_track_preview


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
