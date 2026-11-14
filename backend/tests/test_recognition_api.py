from collections.abc import Iterator
from pathlib import Path

import pytest
from fastapi.testclient import TestClient
from PIL import Image

from app.main import app
from app.recognition.config import DEFAULT_INDEX_DIR, DEFAULT_MODEL_PATH
from tests.recognition_fakes import encode, fake_recognizer, striped_jpeg

BACKEND_DIR = Path(__file__).resolve().parents[1]


@pytest.fixture
def client(monkeypatch: pytest.MonkeyPatch) -> Iterator[TestClient]:
    # Keep startup from loading a real model that may exist locally.
    monkeypatch.setenv("JAMSCAN_MODEL_PATH", "missing-model.onnx")
    with TestClient(app) as client:
        app.state.recognizer = fake_recognizer()
        yield client


def post(client: TestClient, data: bytes, **form: str):
    return client.post(
        "/recognitions",
        files={"image": ("cover.jpg", data, "image/jpeg")},
        data=form,
    )


def test_clear_cover_is_a_match(client: TestClient) -> None:
    response = post(client, striped_jpeg((200, 10, 10)))

    assert response.status_code == 200
    body = response.json()
    assert body["decision"] == "match"
    assert body["candidates"][0]["release_id"] == "1"
    assert body["candidates"][0]["title"] == "Red"
    assert body["model_id"] == "fake/mean-rgb"
    assert {"preprocess", "embed", "search"} <= body["timings_ms"].keys()


def test_ambiguous_cover_needs_review(client: TestClient) -> None:
    body = post(client, striped_jpeg((200, 10, 200))).json()

    assert body["decision"] == "needs_review"
    assert {c["release_id"] for c in body["candidates"]} == {"1", "3"}


def test_unknown_cover_has_no_match(client: TestClient) -> None:
    body = post(client, striped_jpeg((160, 160, 160))).json()

    assert body["decision"] == "no_match"
    assert body["candidates"] == []


def test_flat_photo_is_poor_quality_unless_check_skipped(client: TestClient) -> None:
    flat = encode(Image.new("RGB", (128, 128), (200, 10, 10)))

    assert post(client, flat).json()["decision"] == "poor_quality"
    skipped = post(client, flat, skip_quality_check="true").json()
    assert skipped["decision"] == "match"


def test_invalid_and_oversized_uploads_are_rejected(client: TestClient) -> None:
    assert post(client, b"not an image").status_code == 422

    limit = app.state.recognition_settings.max_upload_bytes
    assert post(client, b"0" * (limit + 1)).status_code == 413


def test_unconfigured_recognition_returns_503(client: TestClient) -> None:
    app.state.recognizer = None

    response = post(client, striped_jpeg((200, 10, 10)))

    assert response.status_code == 503


@pytest.mark.skipif(
    not (BACKEND_DIR / DEFAULT_MODEL_PATH).is_file()
    or not (BACKEND_DIR / DEFAULT_INDEX_DIR).is_dir(),
    reason="Model or dev index not present; see docs/S2-03.md.",
)
def test_real_model_recognises_an_indexed_cover(
    monkeypatch: pytest.MonkeyPatch,
) -> None:
    monkeypatch.chdir(BACKEND_DIR)
    with TestClient(app) as client:
        manifest_entry = app.state.recognizer._index.entries[0]
        cover = (BACKEND_DIR / "data/dev" / manifest_entry.image).read_bytes()
        body = post(client, cover).json()

    assert body["decision"] == "match"
    assert body["candidates"][0]["release_id"] == manifest_entry.release_id
