"""Small stand-ins so recognition tests run without the ONNX model."""

from io import BytesIO

import numpy as np
from PIL import Image

from app.recognition.config import RecognitionSettings
from app.recognition.embedder import l2_normalise
from app.recognition.index import ReferenceEntry, ReferenceIndex
from app.recognition.preprocess import PREPROCESS_VERSION
from app.recognition.service import Recognizer

FAKE_MODEL_ID = "fake/mean-rgb"


class MeanColourEmbedder:
    """Embeds an image as its normalised mean RGB colour."""

    model_id = FAKE_MODEL_ID
    dimension = 3

    def embed(self, image: Image.Image) -> np.ndarray:
        mean = np.asarray(image, dtype=np.float32).reshape(-1, 3).mean(axis=0)
        return l2_normalise(mean)


def entry(release_id: str, title: str) -> ReferenceEntry:
    return ReferenceEntry(release_id, "Artist", title, 2000, f"{release_id}.jpg")


def rgb_index() -> ReferenceIndex:
    """Three releases whose embeddings point along red, green and blue."""
    return ReferenceIndex(
        np.eye(3, dtype=np.float32),
        [entry("1", "Red"), entry("2", "Green"), entry("3", "Blue")],
        FAKE_MODEL_ID,
        PREPROCESS_VERSION,
    )


def fake_recognizer() -> Recognizer:
    return Recognizer(MeanColourEmbedder(), rgb_index(), RecognitionSettings())


def striped_jpeg(colour: tuple[int, int, int], size: int = 256) -> bytes:
    """A sharp test photo: stripes of ``colour`` and a darker shade of it."""
    dark = tuple(round(channel * 0.6) for channel in colour)
    pixels = np.zeros((size, size, 3), dtype=np.uint8)
    pixels[:] = colour
    pixels[:, ::8] = dark
    pixels[:, 1::8] = dark
    return encode(Image.fromarray(pixels))


def encode(image: Image.Image, format: str = "JPEG") -> bytes:
    buffer = BytesIO()
    image.save(buffer, format=format, quality=95)
    return buffer.getvalue()
