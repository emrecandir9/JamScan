"""Build the reference index from a folder of album covers.

The dataset folder (S2-02) contains ``covers.csv`` with the columns
``release_id,artist,title,year,image``, where ``image`` is a path relative to
the folder. A release may have several rows, one per reference photo. The
index is written with the same model and preprocessing the server uses.
"""

import argparse
import csv
import sys
from pathlib import Path

import numpy as np

from app.recognition.config import DEFAULT_INDEX_DIR, DEFAULT_MODEL_PATH
from app.recognition.embedder import Embedder, OnnxDinoEmbedder
from app.recognition.index import ReferenceEntry, ReferenceIndex
from app.recognition.preprocess import PREPROCESS_VERSION, InvalidImageError, load_image


def read_entries(dataset: Path) -> list[ReferenceEntry]:
    with (dataset / "covers.csv").open(newline="", encoding="utf-8") as file:
        return [
            ReferenceEntry(
                release_id=row["release_id"].strip(),
                artist=row["artist"].strip(),
                title=row["title"].strip(),
                year=int(row["year"]) if row.get("year", "").strip() else None,
                image=row["image"].strip(),
            )
            for row in csv.DictReader(file)
        ]


def build(dataset: Path, embedder: Embedder) -> ReferenceIndex:
    vectors = []
    kept = []
    for entry in read_entries(dataset):
        try:
            image = load_image((dataset / entry.image).read_bytes())
        except (OSError, InvalidImageError) as error:
            print(f"skip {entry.image}: {error}", file=sys.stderr)
            continue
        vectors.append(embedder.embed(image))
        kept.append(entry)
    embeddings = (
        np.stack(vectors) if vectors else np.zeros((0, embedder.dimension), np.float32)
    )
    return ReferenceIndex(embeddings, kept, embedder.model_id, PREPROCESS_VERSION)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--dataset", type=Path, default=Path("data/dev"))
    parser.add_argument("--output", type=Path, default=DEFAULT_INDEX_DIR)
    parser.add_argument("--model", type=Path, default=DEFAULT_MODEL_PATH)
    args = parser.parse_args()
    index = build(args.dataset, OnnxDinoEmbedder(args.model))
    index.save(args.output)
    print(f"Indexed {len(index)} covers into {args.output}")
    return 0 if len(index) else 1


if __name__ == "__main__":
    raise SystemExit(main())
