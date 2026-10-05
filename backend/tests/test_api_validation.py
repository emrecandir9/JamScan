import json
import sys
from dataclasses import asdict

import httpx
import pytest

from scripts import validate_apis
from scripts.discogs import validate_discogs
from scripts.itunes import validate_itunes, validate_preview

TOKEN = "test-secret-not-for-reports"
PREVIEW_URL = "https://audio-ssl.itunes.apple.com/example.m4a"
RELEASE = {
    "id": 1,
    "title": "Example album",
    "artists": [{"name": "Example artist"}],
    "tracklist": [{"title": "Example song"}],
}
SONG = {
    "trackId": 123,
    "kind": "song",
    "wrapperType": "track",
    "trackName": "Example song",
    "artistName": "Example artist",
    "collectionName": "Example album",
    "trackViewUrl": "https://music.apple.com/fr/album/example/123",
    "previewUrl": PREVIEW_URL,
}


def test_discogs_authenticated_sequence_and_secret_redaction() -> None:
    paths = []

    def respond(request: httpx.Request) -> httpx.Response:
        paths.append(request.url.path)
        assert request.headers["authorization"] == f"Discogs token={TOKEN}"
        assert request.headers["user-agent"].startswith("JamSCAN/")
        assert TOKEN not in str(request.url)
        if request.url.path == "/oauth/identity":
            payload = {"id": 12, "username": "private-account"}
        elif request.url.path == "/database/search":
            assert request.url.params["q"] == "An artist & album"
            assert request.url.params["type"] == "release"
            payload = {
                "pagination": {"page": 1},
                "results": [{"id": 1, "title": "Example album", "type": "release"}],
            }
        else:
            payload = RELEASE
        return httpx.Response(200, json=payload, headers={"X-Discogs-Ratelimit": "60"})

    with httpx.Client(transport=httpx.MockTransport(respond)) as client:
        checks = validate_discogs(client, TOKEN, "An artist & album")
    assert paths == ["/oauth/identity", "/database/search", "/releases/1"]
    assert all(check.status == "passed" for check in checks)
    assert checks[0].rate_limits == {"x-discogs-ratelimit": 60}
    report = json.dumps([asdict(check) for check in checks])
    assert TOKEN not in report
    assert "private-account" not in report


@pytest.mark.parametrize("token", ["", "  "])
def test_missing_token_still_checks_public_release(token: str) -> None:
    def respond(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/releases/1"
        assert "authorization" not in request.headers
        return httpx.Response(200, json=RELEASE)

    with httpx.Client(transport=httpx.MockTransport(respond)) as client:
        checks = validate_discogs(client, token, "album")
    assert [check.status for check in checks] == ["blocked", "blocked", "passed"]


@pytest.mark.parametrize("status", [301, 401, 403, 429, 500])
def test_discogs_http_failure_stops_without_retry_or_secret_leak(status: int) -> None:
    requests = []

    def respond(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(
            status,
            text=TOKEN,
            headers={"Retry-After": "30", "Location": f"https://example.com/{TOKEN}"},
        )

    with httpx.Client(transport=httpx.MockTransport(respond)) as client:
        checks = validate_discogs(client, TOKEN, "album")
    assert len(requests) == 1
    assert checks[0].status == "failed"
    assert checks[0].http_status == status
    assert checks[0].rate_limits == {"retry-after": 30}
    assert TOKEN not in json.dumps(asdict(checks[0]))


@pytest.mark.parametrize("payload", [None, [], {}, {"id": True, "username": "test"}])
def test_discogs_rejects_invalid_identity(payload: object) -> None:
    with httpx.Client(
        transport=httpx.MockTransport(lambda _: httpx.Response(200, json=payload))
    ) as client:
        checks = validate_discogs(client, TOKEN, "album")
    assert len(checks) == 1
    assert checks[0].status == "failed"


@pytest.mark.parametrize(
    ("results", "status"),
    [([], "inconclusive"), ([{"id": "1"}], "failed"), (None, "failed")],
)
def test_discogs_empty_or_invalid_search_does_not_fetch_release(
    results: object, status: str
) -> None:
    def respond(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/oauth/identity":
            return httpx.Response(200, json={"id": 12, "username": "test"})
        assert request.url.path == "/database/search"
        return httpx.Response(200, json={"pagination": {}, "results": results})

    with httpx.Client(transport=httpx.MockTransport(respond)) as client:
        checks = validate_discogs(client, TOKEN, "album")
    assert len(checks) == 2
    assert checks[-1].status == status


@pytest.mark.parametrize("patch", [{"id": 2}, {"artists": []}, {"tracklist": [None]}])
def test_discogs_rejects_invalid_release(patch: dict) -> None:
    with httpx.Client(
        transport=httpx.MockTransport(
            lambda _: httpx.Response(200, json=RELEASE | patch)
        )
    ) as client:
        checks = validate_discogs(client, "", "album")
    assert checks[-1].status == "failed"


def test_itunes_checks_https_audio_without_credentials() -> None:
    def respond(request: httpx.Request) -> httpx.Response:
        assert "authorization" not in request.headers
        if request.url.path == "/search":
            assert request.url.params["country"] == "FR"
            assert request.url.params["entity"] == "song"
            return httpx.Response(200, json={"resultCount": 1, "results": [SONG]})
        assert str(request.url) == PREVIEW_URL
        assert request.headers["range"] == "bytes=0-1023"
        return httpx.Response(
            206, content=b"a" * 2048, headers={"Content-Type": "audio/mp4"}
        )

    with httpx.Client(transport=httpx.MockTransport(respond)) as client:
        checks = validate_itunes(client, "artist song", "FR")
    assert all(check.status == "passed" for check in checks)
    assert checks[-1].observations["bytes_sampled"] == 1024


@pytest.mark.parametrize("preview", [None, "", "http://audio.itunes.apple.com/preview"])
def test_itunes_missing_https_preview_is_inconclusive(preview: str | None) -> None:
    with httpx.Client(
        transport=httpx.MockTransport(
            lambda _: httpx.Response(
                200,
                json={"resultCount": 1, "results": [SONG | {"previewUrl": preview}]},
            )
        )
    ) as client:
        checks = validate_itunes(client, "song", "FR")
    assert [check.status for check in checks] == ["passed", "inconclusive"]


@pytest.mark.parametrize(
    "url",
    [
        "https://localhost/preview",
        "https://audio.itunes.apple.com.example.com/preview",
        "http://audio.itunes.apple.com/preview",
        "https://user:password@audio.itunes.apple.com/preview",
        "https://audio.itunes.apple.com:8443/preview",
        "https://[invalid/preview",
    ],
)
def test_preview_rejects_untrusted_urls_without_request(url: str) -> None:
    def respond(_: httpx.Request) -> httpx.Response:
        pytest.fail("Unsafe preview URL must not be fetched")

    with httpx.Client(transport=httpx.MockTransport(respond)) as client:
        assert validate_preview(client, url).status == "failed"


@pytest.mark.parametrize(
    ("status", "media_type", "body"),
    [
        (302, "audio/mp4", b"audio"),
        (429, "text/plain", b"busy"),
        (200, "text/html", b"error"),
        (206, "audio/mp4", b""),
    ],
)
def test_preview_failure_is_not_reported_as_available(
    status: int, media_type: str, body: bytes
) -> None:
    with httpx.Client(
        transport=httpx.MockTransport(
            lambda _: httpx.Response(
                status, content=body, headers={"Content-Type": media_type}
            )
        )
    ) as client:
        assert validate_preview(client, PREVIEW_URL).status == "failed"


@pytest.mark.parametrize("error", [httpx.ReadTimeout, httpx.ConnectError])
def test_network_errors_do_not_leak_exception_text(
    error: type[httpx.RequestError],
) -> None:
    def respond(_: httpx.Request) -> httpx.Response:
        raise error(TOKEN)

    with httpx.Client(transport=httpx.MockTransport(respond)) as client:
        checks = validate_itunes(client, "song", "FR")
        preview = validate_preview(client, PREVIEW_URL)
    assert checks[0].status == preview.status == "failed"
    assert TOKEN not in json.dumps([asdict(checks[0]), asdict(preview)])


@pytest.mark.parametrize(
    "body", [b"not json", b"[]", b'{"results": [], "resultCount": 2}']
)
def test_itunes_invalid_response_fails(body: bytes) -> None:
    with httpx.Client(
        transport=httpx.MockTransport(lambda _: httpx.Response(200, content=body))
    ) as client:
        assert validate_itunes(client, "song", "FR")[0].status == "failed"


@pytest.mark.parametrize("results", [[], [SONG]])
def test_cli_exit_status_and_report(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
    results: list[dict],
) -> None:
    def respond(request: httpx.Request) -> httpx.Response:
        if request.url.path == "/search":
            return httpx.Response(
                200, json={"resultCount": len(results), "results": results}
            )
        return httpx.Response(
            206, content=b"audio", headers={"Content-Type": "audio/mp4"}
        )

    client = httpx.Client(transport=httpx.MockTransport(respond))
    monkeypatch.setattr(validate_apis.httpx, "Client", lambda: client)
    monkeypatch.setattr(sys, "argv", ["validate_apis", "--provider", "itunes"])
    assert validate_apis.main() == (0 if results else 1)
    report = json.loads(capsys.readouterr().out)
    assert report["provider"] == "itunes"
    assert all(check["name"].startswith("itunes.") for check in report["checks"])


@pytest.mark.parametrize("token", [TOKEN, ""])
def test_combined_cli_keeps_credentials_on_discogs_and_reports_blockers(
    monkeypatch: pytest.MonkeyPatch,
    capsys: pytest.CaptureFixture[str],
    token: str,
) -> None:
    def respond(request: httpx.Request) -> httpx.Response:
        if request.url.host == "api.discogs.com":
            assert request.headers.get("authorization") == (
                f"Discogs token={token}" if token else None
            )
            if request.url.path == "/oauth/identity":
                payload = {"id": 12, "username": "private-account"}
            elif request.url.path == "/database/search":
                payload = {
                    "pagination": {"page": 1},
                    "results": [{"id": 1, "title": "Album", "type": "release"}],
                }
            else:
                assert request.url.path == "/releases/1"
                payload = RELEASE
            return httpx.Response(200, json=payload)
        assert "authorization" not in request.headers
        if request.url.host == "itunes.apple.com":
            return httpx.Response(200, json={"resultCount": 1, "results": [SONG]})
        assert str(request.url) == PREVIEW_URL
        return httpx.Response(
            206, content=b"audio", headers={"Content-Type": "audio/mp4"}
        )

    client = httpx.Client(transport=httpx.MockTransport(respond))
    monkeypatch.setattr(validate_apis.httpx, "Client", lambda: client)
    monkeypatch.setenv("DISCOGS_TOKEN", token)
    monkeypatch.setattr(sys, "argv", ["validate_apis"])
    assert validate_apis.main() == (0 if token else 1)
    output = capsys.readouterr().out
    assert TOKEN not in output
    assert "private-account" not in output
    report = json.loads(output)
    assert [check["status"] for check in report["checks"]] == (
        ["passed"] * 5
        if token
        else ["blocked", "blocked", "passed", "passed", "passed"]
    )
