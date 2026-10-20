"""Tests for JamSCAN image recognition API routes."""

import pytest
from fastapi.testclient import TestClient

import app.routes as routes
from app.main import app
from app.services.recognition import (
    RecognitionCandidate,
    RecognitionError,
    RecognitionResult,
)

# Mock image with a JPEG signature.
# The recognition algorithm is mocked, so decoding is not required.
JPEG_IMAGE = b"\xff\xd8\xff" + b"\x00" * 32


@pytest.fixture
def client():
    with TestClient(app) as test_client:
        yield test_client


def upload(client, data=JPEG_IMAGE, content_type="image/jpeg"):
    return client.post(
        "/recognize",
        files={"image": ("album.jpg", data, content_type)},
    )


def test_recognize_matched(client, monkeypatch):
    """A successful recognition returns a release ID and score."""

    def fake_recognition(image_data):
        assert image_data == JPEG_IMAGE
        return RecognitionResult(
            status="matched",
            candidates=[
                RecognitionCandidate(
                    discogs_id=4570366,
                    score=0.92,
                )
            ],
        )

    monkeypatch.setattr(routes, "recognize_image", fake_recognition)

    response = upload(client)

    assert response.status_code == 200
    assert response.json()["status"] == "matched"
    assert response.json()["candidates"][0]["discogs_id"] == 4570366
    assert response.json()["candidates"][0]["score"] == 0.92


def test_recognize_needs_review(client, monkeypatch):
    """Uncertain recognition can return multiple candidates."""
    monkeypatch.setattr(
        routes,
        "recognize_image",
        lambda _: RecognitionResult(
            status="needs_review",
            candidates=[
                RecognitionCandidate(discogs_id=123, score=0.75),
                RecognitionCandidate(discogs_id=456, score=0.72),
            ],
        ),
    )

    response = upload(client)

    assert response.status_code == 200
    assert response.json()["status"] == "needs_review"
    assert len(response.json()["candidates"]) == 2


def test_recognize_not_found(client, monkeypatch):
    """A valid image may have no reliable match."""
    monkeypatch.setattr(
        routes,
        "recognize_image",
        lambda _: RecognitionResult(
            status="not_found",
            candidates=[],
        ),
    )

    response = upload(client)

    assert response.status_code == 200
    assert response.json()["status"] == "not_found"
    assert response.json()["candidates"] == []


def test_recognition_unavailable(client, monkeypatch):
    """Unavailable recognition must return a controlled error."""

    def unavailable(_):
        raise RecognitionError("Recognition unavailable", 503)

    monkeypatch.setattr(routes, "recognize_image", unavailable)

    response = upload(client)

    assert response.status_code == 503
    assert response.json()["detail"] == "Recognition unavailable"


def test_recognition_timeout(client, monkeypatch):
    """Recognition timeouts must be handled."""

    def timeout(_):
        raise RecognitionError("Recognition timed out", 504)

    monkeypatch.setattr(routes, "recognize_image", timeout)

    response = upload(client)

    assert response.status_code == 504


def test_missing_image(client):
    """An image is required."""
    response = client.post("/recognize")
    assert response.status_code == 422


def test_unsupported_format(client):
    """Reject unsupported uploaded content types."""
    response = upload(
        client,
        data=b"plain text",
        content_type="text/plain",
    )

    assert response.status_code == 415


def test_invalid_image_signature(client):
    """Reject files with an incorrect image signature."""
    response = upload(
        client,
        data=b"not a JPEG image",
        content_type="image/jpeg",
    )

    assert response.status_code == 415


def test_empty_image(client):
    """Reject empty uploaded files."""
    response = upload(client, data=b"")

    assert response.status_code == 400


def test_image_too_large(client):
    """Enforce the configured image size limit."""
    image = b"\xff\xd8\xff" + b"\x00" * routes.MAX_IMAGE_BYTES

    response = upload(client, data=image)

    assert response.status_code == 413
