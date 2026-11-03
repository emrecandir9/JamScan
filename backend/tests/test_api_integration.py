"""Recognition and release metadata must coexist after integrating main."""

from fastapi.testclient import TestClient

import app.routes as release_routes
from app.main import app
from tests.recognition_fakes import fake_recognizer, striped_jpeg


def test_recognition_then_release_details_in_same_app(monkeypatch):
    monkeypatch.setenv("JAMSCAN_MODEL_PATH", "missing-model.onnx")
    monkeypatch.setenv("DISCOGS_TOKEN", "test-token")

    def release(client, release_id, token):
        assert release_id == 1
        assert token == "test-token"
        return {
            "discogs_id": release_id,
            "artist": "Test artist",
            "title": "Red",
            "tracks": [{"position": "A1", "title": "Test song", "duration": "3:00"}],
        }

    def preview(client, **kwargs):
        assert kwargs["artist"] == "Test artist"
        assert kwargs["track_title"] == "Test song"
        return {
            "preview_url": "https://audio-ssl.itunes.apple.com/test.m4a",
            "track_view_url": "https://music.apple.com/test",
        }

    monkeypatch.setattr(release_routes, "get_release", release)
    monkeypatch.setattr(release_routes, "get_track_preview", preview)

    with TestClient(app) as client:
        assert app.state.recognition_settings is not None
        app.state.recognizer = fake_recognizer()
        recognition = client.post(
            "/recognitions",
            files={"image": ("cover.jpg", striped_jpeg((200, 10, 10)), "image/jpeg")},
        )
        assert recognition.status_code == 200
        result = recognition.json()
        assert result["decision"] == "match"
        release_id = result["candidates"][0]["release_id"]
        response = client.get(f"/releases/{release_id}")
        assert response.status_code == 200
        assert response.json()["preview_status"] == "available"
        assert response.json()["tracks"][0]["preview_url"].startswith("https://")
        assert client.get("/health").json() == {"status": "ok"}
