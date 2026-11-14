"""iTunes Search API integration for JamSCAN track previews."""

import re
import unicodedata
from typing import Any
from urllib.parse import urlsplit

import httpx

BASE_URL = "https://itunes.apple.com/search"
USER_AGENT = "JamSCAN/0.1 (+https://github.com/emrecandir9/JamScan)"


class ITunesError(Exception):
    """Safe error information for iTunes API failures."""

    def __init__(self, message: str, status_code: int = 502) -> None:
        super().__init__(message)
        self.status_code = status_code


def _normalize(value: str) -> str:
    """Normalize names for conservative artist/track matching."""
    value = unicodedata.normalize("NFKD", value.casefold())
    value = "".join(char for char in value if not unicodedata.combining(char))
    return " ".join("".join(char if char.isalnum() else " " for char in value).split())


def _artist_matches(expected: str, candidate: str) -> bool:
    """Match an artist credited alone or first among collaborators."""
    if _normalize(expected) == _normalize(candidate):
        return True

    primary_artist = re.split(
        r",|&|\s+feat\.?\s+|\s+featuring\s+",
        candidate,
        maxsplit=1,
        flags=re.IGNORECASE,
    )[0]

    return _normalize(expected) == _normalize(primary_artist)


def _is_apple_url(value: object, domains: tuple[str, ...]) -> bool:
    """Accept only HTTPS URLs on supported Apple domains."""
    if not isinstance(value, str):
        return False

    try:
        url = urlsplit(value)
        host = url.hostname or ""
        return (
            url.scheme == "https"
            and url.port in (None, 443)
            and not url.username
            and not url.password
            and any(host == domain or host.endswith("." + domain) for domain in domains)
        )
    except ValueError:
        return False


def get_track_preview(
    client: httpx.Client,
    artist: str,
    track_title: str,
    album_title: str = "",
    country: str = "FR",
) -> dict[str, Any] | None:
    """Find a matching iTunes track with an available preview.

    Returns None when no reliable playable match is available.
    """
    if not artist.strip() or not track_title.strip():
        raise ValueError("Artist and track title are required")

    try:
        response = client.get(
            BASE_URL,
            params={
                "term": f"{artist} {track_title}",
                "media": "music",
                "entity": "song",
                "country": country,
                "limit": 10,
            },
            headers={
                "User-Agent": USER_AGENT,
                "Accept": "application/json",
            },
            timeout=15,
            follow_redirects=False,
        )
    except httpx.TimeoutException as exc:
        raise ITunesError("iTunes request timed out", 504) from exc
    except httpx.RequestError as exc:
        raise ITunesError("iTunes is currently unreachable") from exc

    if response.status_code == 429:
        raise ITunesError("iTunes rate limit reached", 503)
    if response.status_code != 200:
        raise ITunesError("iTunes returned an unexpected response")

    try:
        data = response.json()
    except ValueError as exc:
        raise ITunesError("iTunes returned invalid JSON") from exc

    if not isinstance(data, dict) or not isinstance(data.get("results"), list):
        raise ITunesError("iTunes returned an invalid search response")

    expected_track = _normalize(track_title)
    expected_album = _normalize(album_title)

    candidates = []

    for item in data["results"]:
        if not isinstance(item, dict):
            continue

        if item.get("kind") != "song":
            continue

        artist_name = item.get("artistName")
        song_name = item.get("trackName")

        if not isinstance(artist_name, str) or not isinstance(song_name, str):
            continue

        if (
            not _artist_matches(artist, artist_name)
            or _normalize(song_name) != expected_track
        ):
            continue

        preview_url = item.get("previewUrl")

        if not _is_apple_url(preview_url, ("itunes.apple.com", "mzstatic.com")):
            continue

        collection = item.get("collectionName")
        album_matches = (
            bool(expected_album)
            and isinstance(collection, str)
            and _normalize(collection) == expected_album
        )

        candidates.append((album_matches, item))

    if not candidates:
        return None

    # Prefer the correct album edition if it is available.
    best = max(candidates, key=lambda candidate: candidate[0])[1]

    store_url = best.get("trackViewUrl")
    if not _is_apple_url(store_url, ("music.apple.com", "itunes.apple.com")):
        store_url = None

    return {
        "itunes_track_id": best.get("trackId"),
        "preview_url": best["previewUrl"],
        "track_view_url": store_url,
    }
