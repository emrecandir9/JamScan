"""Validate iTunes song search and stream a small preview sample in memory."""

from time import perf_counter
from urllib.parse import urlsplit

import httpx

from scripts.api_checks import Check, positive_integer, request_json


def is_apple_https_url(value: object) -> bool:
    if not isinstance(value, str):
        return False
    try:
        url = urlsplit(value)
        return (
            url.scheme == "https"
            and url.port in (None, 443)
            and not url.username
            and not url.password
            and bool(url.hostname)
            and url.hostname.endswith((".itunes.apple.com", ".mzstatic.com"))
        )
    except ValueError:
        return False


def validate_itunes(client: httpx.Client, query: str, country: str) -> list[Check]:
    checks: list[Check] = []
    check, search = request_json(
        client,
        checks,
        "itunes.search",
        "https://itunes.apple.com/search",
        params={
            "term": query,
            "country": country,
            "media": "music",
            "entity": "song",
            "limit": 5,
        },
    )
    if search is None:
        return checks
    results = search.get("results")
    if (
        not isinstance(results, list)
        or type(search.get("resultCount")) is not int
        or search["resultCount"] != len(results)
        or not all(
            isinstance(track, dict)
            and positive_integer(track.get("trackId"))
            and track.get("kind") == "song"
            and track.get("wrapperType") == "track"
            and all(
                isinstance(track.get(key), str)
                for key in ("trackName", "artistName", "collectionName", "trackViewUrl")
            )
            for track in results
        )
    ):
        check.detail = (
            "Expected resultCount and song results with IDs, names, and store links."
        )
        return checks
    previews = [
        track for track in results if is_apple_https_url(track.get("previewUrl"))
    ]
    check.status = "passed" if results else "inconclusive"
    check.detail = (
        "Song search contract passed without credentials."
        if results
        else "No songs found; rerun with a known track."
    )
    check.observations = {
        "result_count": len(results),
        "https_preview_count": len(previews),
        "country": country,
    }
    if not previews:
        checks.append(
            Check(
                "itunes.preview",
                "inconclusive",
                "No supported HTTPS preview returned; availability is not guaranteed.",
            )
        )
        return checks
    preview_check = validate_preview(client, previews[0]["previewUrl"])
    preview_check.observations["track_id"] = previews[0]["trackId"]
    checks.append(preview_check)
    return checks


def validate_preview(client: httpx.Client, url: str) -> Check:
    """Read at most 1 KiB into memory; never save preview audio or follow redirects."""
    check = Check("itunes.preview", "failed", "Preview request did not complete.")
    if not is_apple_https_url(url):
        check.detail = "Preview URL must use HTTPS on a supported Apple media host."
        return check
    started = perf_counter()
    try:
        with client.stream(
            "GET",
            url,
            headers={"Range": "bytes=0-1023"},
            timeout=15,
            follow_redirects=False,
        ) as response:
            check.http_status = response.status_code
            if response.status_code not in (200, 206):
                check.detail = (
                    "Preview HTTP request failed; no retry or redirect was attempted."
                )
                return check
            media_type = (
                response.headers.get("content-type", "").split(";", 1)[0].lower()
            )
            if not media_type.startswith("audio/"):
                check.detail = "Expected an audio Content-Type for the preview."
                return check
            sample = next(response.iter_bytes(chunk_size=1024), b"")
            if not sample:
                check.detail = "Preview stream was empty."
                return check
            check.status = "passed"
            check.detail = (
                "HTTPS audio received; device playback and duration are untested."
            )
            check.observations = {
                "bytes_sampled": len(sample),
                "audio_content_type": media_type,
            }
    except httpx.TimeoutException:
        check.detail = "Preview request timed out; no retry was attempted."
    except httpx.RequestError:
        check.detail = "Preview network request failed."
    finally:
        check.elapsed_ms = round((perf_counter() - started) * 1000)
    return check
