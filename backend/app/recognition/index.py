"""Reference set of known covers and exact cosine search over it.

An index directory holds two files written by ``scripts.build_index``:

- ``embeddings.npy``: float32 matrix, one L2-normalised row per cover.
- ``manifest.json``: the model and preprocessing used, and one entry per row.

Brute-force search is exact and takes about a millisecond for a few thousand
covers, so no approximate-search library is needed at the MVP's scale.
"""

import json
from dataclasses import asdict, dataclass
from pathlib import Path

import numpy as np

EMBEDDINGS_FILE = "embeddings.npy"
MANIFEST_FILE = "manifest.json"
MANIFEST_VERSION = 1


class IndexLoadError(RuntimeError):
    """Raised when an index is missing, corrupt, or built with another model."""


@dataclass(frozen=True)
class ReferenceEntry:
    """One known release. ``release_id`` is the Discogs release ID."""

    release_id: str
    artist: str
    title: str
    year: int | None = None
    image: str | None = None


@dataclass(frozen=True)
class Candidate:
    entry: ReferenceEntry
    score: float


class ReferenceIndex:
    def __init__(
        self,
        embeddings: np.ndarray,
        entries: list[ReferenceEntry],
        model_id: str,
        preprocess_version: str,
    ) -> None:
        if embeddings.ndim != 2 or embeddings.shape[0] != len(entries):
            raise IndexLoadError("Embeddings and entries do not line up.")
        self.embeddings = embeddings.astype(np.float32, copy=False)
        self.entries = entries
        self.model_id = model_id
        self.preprocess_version = preprocess_version

    def __len__(self) -> int:
        return len(self.entries)

    @property
    def dimension(self) -> int:
        return int(self.embeddings.shape[1])

    def search(self, query: np.ndarray, k: int) -> list[Candidate]:
        """Return up to ``k`` entries by descending cosine similarity.

        Several reference images of one release keep only their best score,
        so the user never sees the same album twice in a candidate list.
        """
        if len(self) == 0 or k <= 0:
            return []
        scores = self.embeddings @ query.astype(np.float32)
        candidates: list[Candidate] = []
        seen: set[str] = set()
        for row in np.argsort(-scores):
            entry = self.entries[row]
            if entry.release_id in seen:
                continue
            seen.add(entry.release_id)
            candidates.append(Candidate(entry, float(scores[row])))
            if len(candidates) == k:
                break
        return candidates

    def save(self, directory: Path) -> None:
        directory.mkdir(parents=True, exist_ok=True)
        np.save(directory / EMBEDDINGS_FILE, self.embeddings)
        manifest = {
            "manifest_version": MANIFEST_VERSION,
            "model_id": self.model_id,
            "preprocess_version": self.preprocess_version,
            "dimension": self.dimension,
            "count": len(self),
            "entries": [asdict(entry) for entry in self.entries],
        }
        (directory / MANIFEST_FILE).write_text(
            json.dumps(manifest, indent=2, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )

    @classmethod
    def load(
        cls, directory: Path, model_id: str, preprocess_version: str
    ) -> "ReferenceIndex":
        """Load an index, checking it was built for this model and pipeline."""
        try:
            manifest = json.loads(
                (directory / MANIFEST_FILE).read_text(encoding="utf-8")
            )
            embeddings = np.load(directory / EMBEDDINGS_FILE, allow_pickle=False)
        except (OSError, ValueError) as error:
            raise IndexLoadError(f"Cannot read the index in {directory}.") from error
        if manifest.get("manifest_version") != MANIFEST_VERSION:
            raise IndexLoadError("Unsupported manifest version.")
        if manifest.get("model_id") != model_id:
            raise IndexLoadError(
                f"Index built with {manifest.get('model_id')!r}, "
                f"but the server uses {model_id!r}. Rebuild the index."
            )
        if manifest.get("preprocess_version") != preprocess_version:
            raise IndexLoadError(
                "Index built with different preprocessing. Rebuild it."
            )
        entries = [ReferenceEntry(**entry) for entry in manifest["entries"]]
        return cls(embeddings, entries, model_id, preprocess_version)
