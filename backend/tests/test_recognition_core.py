from io import BytesIO

import numpy as np
import pytest
from PIL import Image, ImageFilter

from app.recognition.config import Thresholds
from app.recognition.index import Candidate, IndexLoadError, ReferenceIndex
from app.recognition.matcher import Decision, decide
from app.recognition.preprocess import (
    PREPROCESS_VERSION,
    InvalidImageError,
    load_image,
    measure_quality,
    square_crop,
    to_model_input,
)
from tests.recognition_fakes import (
    FAKE_MODEL_ID,
    entry,
    rgb_index,
    striped_jpeg,
)


def test_load_image_rejects_empty_and_non_image_bytes() -> None:
    with pytest.raises(InvalidImageError):
        load_image(b"")
    with pytest.raises(InvalidImageError):
        load_image(b"not an image")


def test_load_image_applies_exif_orientation_and_converts_to_rgb() -> None:
    image = Image.new("L", (40, 20), 128)
    exif = image.getexif()
    exif[0x0112] = 6  # rotated 90 degrees clockwise
    loaded = load_image(encode_with_exif(image, exif))

    assert loaded.mode == "RGB"
    assert loaded.size == (20, 40)


def encode_with_exif(image: Image.Image, exif: Image.Exif) -> bytes:
    buffer = BytesIO()
    image.save(buffer, format="JPEG", exif=exif)
    return buffer.getvalue()


def test_blur_lowers_sharpness_and_brightness_tracks_exposure() -> None:
    sharp = load_image(striped_jpeg((200, 200, 200)))
    blurred = sharp.filter(ImageFilter.GaussianBlur(6))
    dark = Image.new("RGB", (64, 64), (10, 10, 10))

    assert measure_quality(sharp).sharpness > 10 * measure_quality(blurred).sharpness
    assert measure_quality(dark).brightness == pytest.approx(10, abs=1)


def test_model_input_is_a_normalised_square_tensor() -> None:
    image = Image.new("RGB", (300, 200), (124, 116, 104))

    tensor = to_model_input(image)

    assert square_crop(image).size == (200, 200)
    assert tensor.shape == (1, 3, 224, 224)
    assert tensor.dtype == np.float32
    # The ImageNet mean colour normalises to roughly zero.
    assert np.abs(tensor).max() < 0.02


def test_search_ranks_by_cosine_and_keeps_best_row_per_release() -> None:
    index = ReferenceIndex(
        np.array([[1, 0], [0.8, 0.6], [0, 1]], dtype=np.float32),
        [entry("1", "A"), entry("1", "A again"), entry("2", "B")],
        FAKE_MODEL_ID,
        PREPROCESS_VERSION,
    )

    candidates = index.search(np.array([0.6, 0.8], dtype=np.float32), k=5)

    assert [c.entry.release_id for c in candidates] == ["1", "2"]
    assert candidates[0].entry.title == "A again"
    assert candidates[0].score == pytest.approx(0.96)


def test_index_round_trip_and_model_check(tmp_path) -> None:
    rgb_index().save(tmp_path)

    loaded = ReferenceIndex.load(tmp_path, FAKE_MODEL_ID, PREPROCESS_VERSION)

    assert len(loaded) == 3
    assert loaded.entries[2].title == "Blue"
    with pytest.raises(IndexLoadError, match="Rebuild"):
        ReferenceIndex.load(tmp_path, "another-model", PREPROCESS_VERSION)
    with pytest.raises(IndexLoadError):
        ReferenceIndex.load(tmp_path / "missing", FAKE_MODEL_ID, PREPROCESS_VERSION)


@pytest.mark.parametrize(
    ("scores", "decision", "shown"),
    [
        ([0.9, 0.5], Decision.MATCH, 1),
        ([0.9, 0.88], Decision.NEEDS_REVIEW, 2),
        ([0.7, 0.65, 0.2], Decision.NEEDS_REVIEW, 2),
        ([0.59, 0.4], Decision.NO_MATCH, 0),
        ([], Decision.NO_MATCH, 0),
    ],
)
def test_decide(scores: list[float], decision: Decision, shown: int) -> None:
    candidates = [Candidate(entry(str(i), "T"), s) for i, s in enumerate(scores)]

    result, visible = decide(
        candidates, Thresholds(match=0.75, margin=0.05, review=0.6)
    )

    assert result is decision
    assert len(visible) == shown
