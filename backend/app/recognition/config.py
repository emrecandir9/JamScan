"""Recognition settings read from environment variables."""

import os
from dataclasses import dataclass
from pathlib import Path

DEFAULT_MODEL_PATH = Path("models/dinov2-small.onnx")
DEFAULT_INDEX_DIR = Path("data/index")


@dataclass(frozen=True)
class Thresholds:
    """Cosine-similarity limits that turn ranked candidates into a decision.

    A query is a match when the best score reaches ``match`` and leads the
    runner-up by at least ``margin``. Scores from ``review`` upward are shown
    to the user as candidates. These defaults are provisional until they are
    calibrated on the S2-02 evaluation set.
    """

    match: float = 0.75
    margin: float = 0.05
    review: float = 0.60


@dataclass(frozen=True)
class QualityLimits:
    """Minimum sharpness and brightness accepted before recognition."""

    min_sharpness: float = 15.0
    min_brightness: float = 35.0
    max_brightness: float = 235.0


@dataclass(frozen=True)
class RecognitionSettings:
    model_path: Path = DEFAULT_MODEL_PATH
    index_dir: Path = DEFAULT_INDEX_DIR
    top_k: int = 5
    max_upload_bytes: int = 10 * 1024 * 1024
    thresholds: Thresholds = Thresholds()
    quality: QualityLimits = QualityLimits()

    @classmethod
    def from_env(cls) -> "RecognitionSettings":
        defaults = cls()
        return cls(
            model_path=Path(os.environ.get("JAMSCAN_MODEL_PATH", DEFAULT_MODEL_PATH)),
            index_dir=Path(os.environ.get("JAMSCAN_INDEX_DIR", DEFAULT_INDEX_DIR)),
            top_k=int(os.environ.get("JAMSCAN_TOP_K", defaults.top_k)),
            thresholds=Thresholds(
                match=_float_env("JAMSCAN_MATCH_THRESHOLD", defaults.thresholds.match),
                margin=_float_env("JAMSCAN_MATCH_MARGIN", defaults.thresholds.margin),
                review=_float_env(
                    "JAMSCAN_REVIEW_THRESHOLD", defaults.thresholds.review
                ),
            ),
        )


def _float_env(name: str, default: float) -> float:
    value = os.environ.get(name)
    return default if value is None else float(value)
