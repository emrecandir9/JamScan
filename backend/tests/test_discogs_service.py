import httpx
import pytest

from app.services.discogs import DiscogsError, get_release, search_releases

RELEASE = {
    "id": 4570366,
    "title": "Random Access Memories",
    "artists": [{"name": "Daft Punk"}],
    "year": 2013,
    "labels": [{"name": "Columbia", "catno": "88883716861"}],
    "genres": ["Electronic"],
    "styles": ["Disco"],
    "community": {"rating": {"average": 4.7}},
    "images": [{"uri": "https://example.com/cover.jpg"}],
    "tracklist": [
        {
            "position": "A1",
            "title": "Give Life Back to Music",
            "duration": "4:35",
        },
    ],
}


def test_get_release_normalizes_metadata() -> None:
    def respond(request: httpx.Request) -> httpx.Response:
        assert request.url.path == "/releases/4570366"
        assert request.headers["authorization"] == "Discogs token=test-token"
        assert request.headers["user-agent"].startswith("JamSCAN/")
        return httpx.Response(200, json=RELEASE)

    with httpx.Client(transport=httpx.MockTransport(respond)) as client:
        result = get_release(client, 4570366, "test-token")

    assert result["artist"] == "Daft Punk"
    assert result["title"] == "Random Access Memories"
    assert result["year"] == 2013
    assert result["label"] == "Columbia"
    assert result["tracks"][0]["title"] == "Give Life Back to Music"


def test_search_releases_returns_candidates() -> None:
    def respond(request: httpx.Request) -> httpx.Response:
        assert request.url.params["type"] == "release"
        assert request.url.params["q"] == "Daft Punk"
        return httpx.Response(
            200,
            json={"results": [{"id": 123, "title": "Album"}]},
        )

    with httpx.Client(transport=httpx.MockTransport(respond)) as client:
        result = search_releases(client, "Daft Punk", "test-token")

    assert result == [{"discogs_id": 123, "title": "Album", "cover_url": None}]


@pytest.mark.parametrize(
    ("status", "expected"),
    [(404, 404), (429, 503), (500, 502)],
)
def test_discogs_http_errors_are_safe(status: int, expected: int) -> None:
    with httpx.Client(
        transport=httpx.MockTransport(lambda _: httpx.Response(status, text="secret"))
    ) as client:
        with pytest.raises(DiscogsError) as error:
            get_release(client, 4570366, "test-token")

    assert error.value.status_code == expected
    assert "secret" not in str(error.value)


def test_discogs_timeout() -> None:
    def respond(_: httpx.Request) -> httpx.Response:
        raise httpx.ReadTimeout("private diagnostic")

    with httpx.Client(transport=httpx.MockTransport(respond)) as client:
        with pytest.raises(DiscogsError) as error:
            get_release(client, 4570366)

    assert error.value.status_code == 504
    assert "private diagnostic" not in str(error.value)


def test_missing_search_token_does_not_make_request() -> None:
    with httpx.Client(
        transport=httpx.MockTransport(lambda _: pytest.fail("Request not expected"))
    ) as client:
        with pytest.raises(DiscogsError) as error:
            search_releases(client, "Daft Punk", "")

    assert error.value.status_code == 503


def test_invalid_release_payload() -> None:
    with httpx.Client(
        transport=httpx.MockTransport(lambda _: httpx.Response(200, json={"id": 1}))
    ) as client:
        with pytest.raises(DiscogsError) as error:
            get_release(client, 4570366)

    assert error.value.status_code == 502
