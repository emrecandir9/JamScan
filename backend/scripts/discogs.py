"""Discogs authentication, search, and release validation."""

import httpx

from scripts.api_checks import Check, positive_integer, request_json

DISCOGS_URL = "https://api.discogs.com"


def validate_discogs(client: httpx.Client, token: str, query: str) -> list[Check]:
    """Validate identity, release search, and one returned release in order."""
    checks: list[Check] = []
    token = token.strip()
    if not token:
        checks.extend(
            [
                Check(
                    "discogs.authentication",
                    "blocked",
                    "Set DISCOGS_TOKEN to verify authentication.",
                ),
                Check(
                    "discogs.search",
                    "blocked",
                    "Set DISCOGS_TOKEN to verify authenticated search.",
                ),
            ]
        )
        validate_release(client, checks, token, 1)
        return checks
    check, identity = request_json(
        client, checks, "discogs.authentication", f"{DISCOGS_URL}/oauth/identity", token
    )
    if identity is None:
        return checks
    if not positive_integer(identity.get("id")) or not isinstance(
        identity.get("username"), str
    ):
        check.detail = (
            "Expected identity fields id (positive integer), username (string)."
        )
        return checks
    check.status = "passed"
    check.detail = "Authenticated identity received; personal account fields omitted."

    check, search = request_json(
        client,
        checks,
        "discogs.search",
        f"{DISCOGS_URL}/database/search",
        token,
        {"q": query, "type": "release", "per_page": 3, "page": 1},
    )
    if search is None:
        return checks
    results = search.get("results")
    if not isinstance(results, list) or not isinstance(search.get("pagination"), dict):
        check.detail = "Expected results (array) and pagination (object)."
        return checks
    if not all(
        isinstance(item, dict)
        and positive_integer(item.get("id"))
        and isinstance(item.get("title"), str)
        and item.get("type") == "release"
        for item in results
    ):
        check.detail = "Expected release results with id, title, and type=release."
        return checks
    check.observations["result_count"] = len(results)
    if not results:
        check.status = "inconclusive"
        check.detail = "Valid search response but no matches; rerun with a known album."
        return checks
    check.status = "passed"
    check.detail = "Paginated release search contract passed."

    validate_release(client, checks, token, results[0]["id"])
    return checks


def validate_release(
    client: httpx.Client, checks: list[Check], token: str, release_id: int
) -> None:
    """Check a public release; a missing token does not block metadata access."""
    check, release = request_json(
        client, checks, "discogs.release", f"{DISCOGS_URL}/releases/{release_id}", token
    )
    if release is None:
        return
    tracklist = release.get("tracklist")
    artists = release.get("artists")
    if (
        not positive_integer(release.get("id"))
        or release["id"] != release_id
        or not isinstance(release.get("title"), str)
        or not isinstance(artists, list)
        or not artists
        or not all(
            isinstance(artist, dict) and isinstance(artist.get("name"), str)
            for artist in artists
        )
        or not isinstance(tracklist, list)
        or not all(
            isinstance(track, dict) and isinstance(track.get("title"), str)
            for track in tracklist
        )
    ):
        check.detail = "Expected matching release id, title, artists, and tracklist."
        return
    check.status = "passed"
    check.detail = (
        "Release metadata contract passed; playback requires its own provider."
    )
    check.observations = {
        "release_id": release_id,
        "track_count": len(tracklist),
        "audio_preview": "not_checked_by_discogs_probe",
    }
