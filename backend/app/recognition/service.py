"""Recognition pipeline: decode, quality check, embed, search, decide."""

import logging
from dataclasses import dataclass, field
from time import perf_counter

from app.recognition.config import RecognitionSettings
from app.recognition.embedder import Embedder, OnnxDinoEmbedder
from app.recognition.index import Candidate, ReferenceIndex
from app.recognition.matcher import Decision, decide
from app.recognition.preprocess import (
    PREPROCESS_VERSION,
    ImageQuality,
    load_image,
    measure_quality,
)

logger = logging.getLogger(__name__)


@dataclass
class RecognitionResult:
    decision: Decision
    candidates: list[Candidate]
    quality: ImageQuality
    timings_ms: dict[str, float] = field(default_factory=dict)


class Recognizer:
    def __init__(
        self,
        embedder: Embedder,
        index: ReferenceIndex,
        settings: RecognitionSettings,
    ) -> None:
        if embedder.model_id != index.model_id:
            raise ValueError("The index was built with a different model.")
        self._embedder = embedder
        self._index = index
        self._settings = settings

    @property
    def index_size(self) -> int:
        return len(self._index)

    @property
    def model_id(self) -> str:
        return self._embedder.model_id

    def recognize(
        self, data: bytes, skip_quality_check: bool = False
    ) -> RecognitionResult:
        """Identify the cover in ``data``.

        Raises :class:`~app.recognition.preprocess.InvalidImageError` when the
        bytes are not an image.
        """
        timings: dict[str, float] = {}
        started = perf_counter()
        image = load_image(data)
        quality = measure_quality(image)
        timings["preprocess"] = _elapsed_ms(started)

        if not skip_quality_check and not self._acceptable(quality):
            return RecognitionResult(Decision.POOR_QUALITY, [], quality, timings)

        started = perf_counter()
        query = self._embedder.embed(image)
        timings["embed"] = _elapsed_ms(started)

        started = perf_counter()
        ranked = self._index.search(query, self._settings.top_k)
        decision, shown = decide(ranked, self._settings.thresholds)
        timings["search"] = _elapsed_ms(started)
        return RecognitionResult(decision, shown, quality, timings)

    def _acceptable(self, quality: ImageQuality) -> bool:
        limits = self._settings.quality
        return (
            quality.sharpness >= limits.min_sharpness
            and limits.min_brightness <= quality.brightness <= limits.max_brightness
        )


def load_recognizer(settings: RecognitionSettings) -> Recognizer | None:
    """Build the recognizer, or return ``None`` when the model or index is
    missing, so the rest of the API still starts."""
    try:
        embedder = OnnxDinoEmbedder(settings.model_path)
        index = ReferenceIndex.load(
            settings.index_dir, embedder.model_id, PREPROCESS_VERSION
        )
    except (FileNotFoundError, RuntimeError) as error:
        logger.warning("Recognition disabled: %s", error)
        return None
    logger.info("Recognition ready with %d reference covers.", len(index))
    return Recognizer(embedder, index, settings)


def _elapsed_ms(started: float) -> float:
    return round((perf_counter() - started) * 1000, 1)
