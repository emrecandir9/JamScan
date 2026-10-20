"""Unit tests for the JamSCAN iTunes preview service."""

import httpx
import pytest

from app.services.itunes import ITunesError, get_track_preview

PREVIEW_URL = "https://audio-ssl.itunes.apple.com/sample.m4a"
STORE_URL = "https://music.apple.com/fr/album/example"


def make_song(
    preview: str | None = PREVIEW_URL,
    album: str = "Random Access Memories",
) -> dict:
    return {
        "wrapperType": "track",
        "kind": "song",
        "trackId": 12345,
        "artistName": "Daft Punk",
        "trackName": "Get Lucky",
        "collectionName": album,
        "previewUrl": preview,
        "trackViewUrl": STORE_URL,
    }


def test_get_track_preview() -> None:
    def respond(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/search"
        assert request.url.params["term"] == "Daft Punk Get Lucky"
        assert request.url.params["country"] == "FR"
        assert request.url.params["entity"] == "song"
        return httpx.Response(
            200,
            json={"resultCount": 1, "results": [make_song()]},
        )

    with httpx.Client(transport=httpx.MockTransport(respond)) as client:
        result = get_track_preview(
            client, "Daft Punk", "Get Lucky", "Random Access Memories"
        )

    assert result is not None
    assert result["preview_url"] == PREVIEW_URL
    assert result["itunes_track_id"] == 12345
    assert result["track_view_url"] == STORE_URL


def test_no_preview_available() -> None:
    with httpx.Client(
        transport=httpx.MockTransport(
            lambda _: httpx.Response(
                200,
                json={"results": [make_song(preview=None)]},
            )
        )
    ) as client:
        result = get_track_preview(client, "Daft Punk", "Get Lucky")

    assert result is None


def test_no_matching_track() -> None:
    song = make_song()
    song["artistName"] = "Different Artist"

    with httpx.Client(
        transport=httpx.MockTransport(
            lambda _: httpx.Response(200, json={"results": [song]})
        )
    ) as client:
        result = get_track_preview(client, "Daft Punk", "Get Lucky")

    assert result is None


def test_prefer_matching_album() -> None:
    other = make_song(album="Another Album")
    other["previewUrl"] = "https://audio-ssl.itunes.apple.com/other.m4a"

    with httpx.Client(
        transport=httpx.MockTransport(
            lambda _: httpx.Response(
                200,
                json={"results": [other, make_song()]},
            )
        )
    ) as client:
        result = get_track_preview(
            client, "Daft Punk", "Get Lucky", "Random Access Memories"
        )

    assert result is not None
    assert result["preview_url"] == PREVIEW_URL


def test_reject_unsafe_preview_url() -> None:
    with httpx.Client(
        transport=httpx.MockTransport(
            lambda _: httpx.Response(
                200,
                json={"results": [make_song(preview="https://example.com/audio.mp3")]},
            )
        )
    ) as client:
        result = get_track_preview(client, "Daft Punk", "Get Lucky")

    assert result is None


@pytest.mark.parametrize(
    ("status", "expected"),
    [(429, 503), (500, 502)],
)
def test_itunes_http_errors(status: int, expected: int) -> None:
    with httpx.Client(
        transport=httpx.MockTransport(
            lambda _: httpx.Response(status, text="private diagnostic")
        )
    ) as client:
        with pytest.raises(ITunesError) as error:
            get_track_preview(client, "Daft Punk", "Get Lucky")

    assert error.value.status_code == expected
    assert "private diagnostic" not in str(error.value)


def test_itunes_timeout() -> None:
    def respond(_: httpx.Request) -> httpx.Response:
        raise httpx.ReadTimeout("private diagnostic")

    with httpx.Client(transport=httpx.MockTransport(respond)) as client:
        with pytest.raises(ITunesError) as error:
            get_track_preview(client, "Daft Punk", "Get Lucky")

    assert error.value.status_code == 504


def test_invalid_itunes_response() -> None:
    with httpx.Client(
        transport=httpx.MockTransport(
            lambda _: httpx.Response(200, json={"results": None})
        )
    ) as client:
        with pytest.raises(ITunesError):
            get_track_preview(client, "Daft Punk", "Get Lucky")


def test_empty_track_title() -> None:
    with httpx.Client() as client:
        with pytest.raises(ValueError):
            get_track_preview(client, "Daft Punk", "")
