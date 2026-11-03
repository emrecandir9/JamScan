"""Tests for the JamSCAN release API endpoints."""

from copy import deepcopy

import pytest
from fastapi.testclient import TestClient

import app.routes as routes
from app.main import app
from app.services.discogs import DiscogsError
from app.services.itunes import ITunesError

SAMPLE_ALBUM = {
    "discogs_id": 4570366,
    "artist": "Daft Punk",
    "title": "Random Access Memories",
    "year": 2013,
    "tracks": [
        {"position": "8", "title": "Get Lucky", "duration": "6:09"},
        {"position": "2", "title": "The Game of Love", "duration": "5:22"},
    ],
}


@pytest.fixture(autouse=True)
def mock_token(monkeypatch):
    monkeypatch.setenv("DISCOGS_TOKEN", "test-token")


@pytest.fixture
def mock_release(monkeypatch):
    def fake_get_release(client, release_id, token):
        assert release_id == 4570366
        assert token == "test-token"
        return deepcopy(SAMPLE_ALBUM)

    monkeypatch.setattr(routes, "get_release", fake_get_release)


def test_release_with_preview(monkeypatch, mock_release):
    """Release details include an available preview URL."""

    def fake_preview(client, **kwargs):
        assert kwargs["artist"] == "Daft Punk"
        assert kwargs["country"] == "FR"

        if kwargs["track_title"] == "Get Lucky":
            return {
                "preview_url": "https://audio-ssl.itunes.apple.com/test.m4a",
                "track_view_url": "https://music.apple.com/test",
            }
        return None

    monkeypatch.setattr(routes, "get_track_preview", fake_preview)

    with TestClient(app) as client:
        response = client.get("/releases/4570366")

    assert response.status_code == 200
    data = response.json()
    assert data["artist"] == "Daft Punk"
    assert data["previews_available"] == 1
    assert data["preview_status"] == "available"
    assert data["tracks"][0]["preview_url"].startswith("https://")


def test_release_without_previews(monkeypatch, mock_release):
    """Album metadata remains accessible without previews."""
    monkeypatch.setattr(routes, "get_track_preview", lambda *args, **kwargs: None)

    with TestClient(app) as client:
        response = client.get("/releases/4570366")

    assert response.status_code == 200
    data = response.json()
    assert data["preview_status"] == "none_found"
    assert data["previews_available"] == 0
    assert data["tracks"][0]["preview_url"] is None


def test_itunes_failure_keeps_metadata(monkeypatch, mock_release):
    """An iTunes outage must not hide the release."""

    def fail_preview(*args, **kwargs):
        raise ITunesError("iTunes unavailable", 503)

    monkeypatch.setattr(routes, "get_track_preview", fail_preview)

    with TestClient(app) as client:
        response = client.get("/releases/4570366")

    assert response.status_code == 200
    data = response.json()
    assert data["title"] == "Random Access Memories"
    assert data["preview_status"] == "service_unavailable"


def test_partial_preview_failure(monkeypatch, mock_release):
    """Keep retrieved previews if a later lookup fails."""

    def fake_preview(client, **kwargs):
        if kwargs["track_title"] == "Get Lucky":
            return {
                "preview_url": "https://audio-ssl.itunes.apple.com/test.m4a",
                "track_view_url": None,
            }
        raise ITunesError("iTunes unavailable", 503)

    monkeypatch.setattr(routes, "get_track_preview", fake_preview)

    with TestClient(app) as client:
        response = client.get("/releases/4570366")

    assert response.status_code == 200
    assert response.json()["preview_status"] == "partial"
    assert response.json()["previews_available"] == 1


def test_discogs_failure_returns_error(monkeypatch):
    """Missing Discogs releases produce a controlled HTTP error."""

    def fail_release(*args, **kwargs):
        raise DiscogsError("Discogs release not found", 404)

    monkeypatch.setattr(routes, "get_release", fail_release)

    with TestClient(app) as client:
        response = client.get("/releases/999999")

    assert response.status_code == 404
    assert response.json()["detail"] == "Discogs release not found"


def test_manual_search(monkeypatch):
    """Manual search returns normalized Discogs candidates."""

    def fake_search(client, query, token):
        assert query == "Daft Punk"
        assert token == "test-token"
        return [{"discogs_id": 4570366, "title": "Random Access Memories"}]

    monkeypatch.setattr(routes, "search_releases", fake_search)

    with TestClient(app) as client:
        response = client.get("/releases/search", params={"query": "Daft Punk"})

    assert response.status_code == 200
    assert response.json()["results"][0]["discogs_id"] == 4570366


def test_search_api_failure(monkeypatch):
    """Search failures are reported without exposing provider details."""

    def fail_search(*args, **kwargs):
        raise DiscogsError("Discogs rate limit reached", 503)

    monkeypatch.setattr(routes, "search_releases", fail_search)

    with TestClient(app) as client:
        response = client.get("/releases/search", params={"query": "Daft Punk"})

    assert response.status_code == 503
    assert response.json()["detail"] == "Discogs rate limit reached"


def test_preview_lookup_limit(monkeypatch, mock_release):
    """Do not issue unlimited preview requests for long albums."""
    album = deepcopy(SAMPLE_ALBUM)
    album["tracks"] = [
        {"position": str(i), "title": f"Track {i}"} for i in range(1, 11)
    ]
    monkeypatch.setattr(
        routes,
        "get_release",
        lambda *args, **kwargs: deepcopy(album),
    )

    calls = []

    def fake_preview(client, **kwargs):
        calls.append(kwargs["track_title"])
        return None

    monkeypatch.setattr(routes, "get_track_preview", fake_preview)

    with TestClient(app) as client:
        response = client.get("/releases/4570366")

    assert response.status_code == 200
    assert len(calls) == 5
    assert len(response.json()["tracks"]) == 10
    assert response.json()["preview_lookup_limit"] == 5


def test_invalid_release_id():
    """Reject invalid release IDs before contacting external services."""
    with TestClient(app) as client:
        response = client.get("/releases/-1")

    assert response.status_code == 422
