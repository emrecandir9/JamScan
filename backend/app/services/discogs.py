"""Discogs release search and metadata retrieval for the JamSCAN backend."""

from typing import Any

import httpx

BASE_URL = "https://api.discogs.com"
USER_AGENT = "JamSCAN/0.1 (+https://github.com/emrecandir9/JamScan)"


class DiscogsError(Exception):
    """Safe error information for the future API routes."""

    def __init__(self, message: str, status_code: int = 502) -> None:
        super().__init__(message)
        self.status_code = status_code


def _get_json(
    client: httpx.Client,
    path: str,
    token: str,
    params: dict[str, str | int] | None = None,
) -> dict[str, Any]:
    headers = {"User-Agent": USER_AGENT, "Accept": "application/json"}

    if token.strip():
        headers["Authorization"] = f"Discogs token={token.strip()}"

    try:
        response = client.get(
            f"{BASE_URL}{path}",
            params=params,
            headers=headers,
            timeout=15,
            follow_redirects=False,
        )
    except httpx.TimeoutException as exc:
        raise DiscogsError("Discogs request timed out", 504) from exc
    except httpx.RequestError as exc:
        raise DiscogsError("Discogs is currently unreachable") from exc

    if response.status_code == 404:
        raise DiscogsError("Discogs release not found", 404)
    if response.status_code == 429:
        raise DiscogsError("Discogs rate limit reached", 503)
    if response.status_code in (401, 403):
        raise DiscogsError("Discogs authentication or access failed")
    if response.status_code != 200:
        raise DiscogsError("Discogs returned an unexpected response")

    try:
        result = response.json()
    except ValueError as exc:
        raise DiscogsError("Discogs returned invalid JSON") from exc

    if not isinstance(result, dict):
        raise DiscogsError("Discogs returned an unexpected data structure")

    return result


def search_releases(
    client: httpx.Client, query: str, token: str
) -> list[dict[str, Any]]:
    """Search Discogs for physical music releases."""
    if not query.strip():
        raise ValueError("Search query cannot be empty")
    if not token.strip():
        raise DiscogsError("Discogs authentication is not configured", 503)

    data = _get_json(
        client,
        "/database/search",
        token,
        {"q": query.strip(), "type": "release", "per_page": 10, "page": 1},
    )

    results = data.get("results")
    if not isinstance(results, list):
        raise DiscogsError("Discogs returned an invalid search result")

    candidates = []
    for item in results:
        if (
            not isinstance(item, dict)
            or type(item.get("id")) is not int
            or not isinstance(item.get("title"), str)
        ):
            raise DiscogsError("Discogs returned an invalid search result")

        candidates.append(
            {
                "discogs_id": item["id"],
                "title": item["title"],
                "cover_url": item.get("cover_image"),
            }
        )

    return candidates


def get_release(
    client: httpx.Client, release_id: int, token: str = ""
) -> dict[str, Any]:
    """Retrieve and normalize metadata for a Discogs release."""
    if type(release_id) is not int or release_id <= 0:
        raise ValueError("release_id must be a positive integer")

    data = _get_json(client, f"/releases/{release_id}", token)

    artists = data.get("artists")
    tracks = data.get("tracklist", [])

    if (
        data.get("id") != release_id
        or not isinstance(data.get("title"), str)
        or not isinstance(artists, list)
        or not artists
        or not all(
            isinstance(artist, dict) and isinstance(artist.get("name"), str)
            for artist in artists
        )
        or not isinstance(tracks, list)
    ):
        raise DiscogsError("Discogs returned incomplete release data")

    tracklist = []
    for track in tracks:
        if not isinstance(track, dict) or not isinstance(track.get("title"), str):
            raise DiscogsError("Discogs returned an invalid tracklist")

        if track.get("type_") == "heading":
            continue

        tracklist.append(
            {
                "position": track.get("position", ""),
                "title": track["title"],
                "duration": track.get("duration") or None,
            }
        )

    labels = data.get("labels") or []
    first_label = labels[0] if isinstance(labels, list) and labels else {}

    images = data.get("images") or []
    cover_url = (
        next(
            (
                image["uri"]
                for image in images
                if isinstance(image, dict)
                and isinstance(image.get("uri"), str)
                and image["uri"].startswith("https://")
            ),
            None,
        )
        if isinstance(images, list)
        else None
    )

    community = data.get("community") or {}
    rating = community.get("rating", {}) if isinstance(community, dict) else {}
    average = rating.get("average") if isinstance(rating, dict) else None

    return {
        "discogs_id": release_id,
        "artist": ", ".join(artist["name"] for artist in artists),
        "title": data["title"],
        "year": data.get("year") if type(data.get("year")) is int else None,
        "cover_url": cover_url,
        "label": first_label.get("name") if isinstance(first_label, dict) else None,
        "catalog_number": (
            first_label.get("catno") if isinstance(first_label, dict) else None
        ),
        "genres": data.get("genres") if isinstance(data.get("genres"), list) else [],
        "styles": data.get("styles") if isinstance(data.get("styles"), list) else [],
        "rating": average if type(average) in (int, float) else None,
        "tracks": tracklist,
    }
