"""Turn ranked candidates into the decision the app acts on."""

from enum import StrEnum

from app.recognition.config import Thresholds
from app.recognition.index import Candidate


class Decision(StrEnum):
    MATCH = "match"
    NEEDS_REVIEW = "needs_review"
    NO_MATCH = "no_match"
    POOR_QUALITY = "poor_quality"


def decide(
    candidates: list[Candidate], thresholds: Thresholds
) -> tuple[Decision, list[Candidate]]:
    """Return the decision and the candidates worth showing, best first.

    Only candidates at or above the review threshold are returned, so a
    ``no_match`` decision always comes with an empty list.
    """
    shown = [c for c in candidates if c.score >= thresholds.review]
    if not shown:
        return Decision.NO_MATCH, []
    best = shown[0].score
    runner_up = candidates[1].score if len(candidates) > 1 else -1.0
    if best >= thresholds.match and best - runner_up >= thresholds.margin:
        return Decision.MATCH, shown
    return Decision.NEEDS_REVIEW, shown
