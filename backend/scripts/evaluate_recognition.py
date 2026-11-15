"""Measure recognition accuracy on a folder of query photos.

Each query file is named ``<release_id>__<anything>.jpg`` (or
``<release_id>.jpg``), where ``release_id`` is the Discogs release that
should be recognised. Real phone photos of physical covers are the target
evaluation set; ``--augment`` instead creates simulated phone photos from the
dataset's reference covers, which is optimistic but needs no photos.

Reports first-answer (top-1) and top-5 accuracy, how the decisions split, the
wrong matches (the costly error), latency, and a threshold sweep. The output
is JSON, so it can be saved as evidence.
"""

import argparse
import io
import json
import random
import statistics
import sys
from pathlib import Path
from time import perf_counter

import numpy as np
from PIL import Image, ImageDraw, ImageEnhance, ImageFilter

from app.recognition.config import RecognitionSettings, Thresholds
from app.recognition.embedder import OnnxDinoEmbedder
from app.recognition.index import ReferenceIndex
from app.recognition.matcher import Decision, decide
from app.recognition.preprocess import PREPROCESS_VERSION, load_image
from app.recognition.service import Recognizer


def release_id_of(path: Path) -> str:
    return path.stem.split("__")[0]


def phone_photo(cover: Image.Image, rng: random.Random) -> Image.Image:
    """A loose, tilted, unevenly lit and slightly blurred crop of a cover,
    like a quick phone photo that was cropped by the app."""
    cover = cover.convert("RGB").resize((600, 600))
    background = Image.new(
        "RGB", (760, 760), tuple(rng.randint(40, 200) for _ in "rgb")
    )
    jitter = 30
    quad = [
        (rng.uniform(-jitter, jitter), rng.uniform(-jitter, jitter)),
        (rng.uniform(-jitter, jitter), 600 + rng.uniform(-jitter, jitter)),
        (600 + rng.uniform(-jitter, jitter), 600 + rng.uniform(-jitter, jitter)),
        (600 + rng.uniform(-jitter, jitter), rng.uniform(-jitter, jitter)),
    ]
    warped = cover.transform(
        (600, 600),
        Image.Transform.QUAD,
        [c for p in quad for c in p],
        Image.Resampling.BICUBIC,
    ).rotate(rng.uniform(-5, 5), Image.Resampling.BICUBIC)
    background.paste(warped, (80, 80))
    offset = 50
    left = 80 + rng.randint(-offset, offset)
    top = 80 + rng.randint(-offset, offset)
    photo = background.crop((left, top, left + 600, top + 600))
    photo = ImageEnhance.Brightness(photo).enhance(rng.uniform(0.65, 1.25))
    photo = ImageEnhance.Contrast(photo).enhance(rng.uniform(0.75, 1.1))
    photo = ImageEnhance.Color(photo).enhance(rng.uniform(0.7, 1.2))
    if rng.random() < 0.5:
        glare = Image.new("L", photo.size, 0)
        x, y, r = rng.randint(100, 500), rng.randint(100, 500), rng.randint(50, 110)
        ImageDraw.Draw(glare).ellipse((x - r, y - r, x + r, y + r), fill=150)
        glare = glare.filter(ImageFilter.GaussianBlur(30))
        photo = Image.composite(Image.new("RGB", photo.size, "white"), photo, glare)
    photo = photo.filter(ImageFilter.GaussianBlur(rng.uniform(0, 1.6)))
    return photo.resize((512, 512))


def augmented_queries(dataset: Path, per_cover: int, seed: int):
    rng = random.Random(seed)
    for row in (dataset / "covers.csv").read_text(encoding="utf-8").splitlines()[1:]:
        release_id, *_, image = row.split(",")
        cover = Image.open(dataset / image)
        for i in range(per_cover):
            buffer = io.BytesIO()
            phone_photo(cover, rng).save(buffer, "JPEG", quality=85)
            yield f"{release_id}__aug{i}", release_id, buffer.getvalue()


def folder_queries(folder: Path):
    for path in sorted(folder.iterdir()):
        if path.suffix.lower() in {".jpg", ".jpeg", ".png"}:
            yield path.name, release_id_of(path), path.read_bytes()


def evaluate(queries, embedder, index, recognizer, thresholds: Thresholds) -> dict:
    rows = []
    for name, truth, data in queries:
        started = perf_counter()
        result = recognizer.recognize(data)
        elapsed_ms = (perf_counter() - started) * 1000
        # Raw ranking, independent of the thresholds.
        ranked = index.search(embedder.embed(load_image(data)), 5)
        ids = [c.entry.release_id for c in ranked]
        true_score = next(
            (c.score for c in ranked if c.entry.release_id == truth), None
        )
        impostor = next((c.score for c in ranked if c.entry.release_id != truth), None)
        rows.append(
            {
                "query": name,
                "truth": truth,
                "known": any(e.release_id == truth for e in index.entries),
                "decision": result.decision.value,
                "answer": result.candidates[0].entry.release_id
                if result.candidates
                else None,
                "shown": [c.entry.release_id for c in result.candidates],
                "top1": ids[0] if ids else None,
                "rank": ids.index(truth) + 1 if truth in ids else None,
                "true_score": true_score,
                "best_impostor": impostor,
                "ranked": ranked,
                "top1_score": ranked[0].score if ranked else 0.0,
                "ms": elapsed_ms,
            }
        )
    return summarise(rows, thresholds)


def summarise(rows: list[dict], thresholds: Thresholds) -> dict:
    known = [r for r in rows if r["known"]]
    unknown = [r for r in rows if not r["known"]]
    n = len(known)
    decisions = {d.value: 0 for d in Decision}
    for r in known:
        decisions[r["decision"]] += 1
    correct_matches = sum(
        r["decision"] == "match" and r["answer"] == r["truth"] for r in known
    )
    wrong_matches = [
        r["query"]
        for r in known
        if r["decision"] == "match" and r["answer"] != r["truth"]
    ]
    review_with_truth = sum(
        r["decision"] == "needs_review" and r["truth"] in r["shown"] for r in known
    )
    true_scores = [r["true_score"] for r in known if r["rank"] == 1]
    impostors = [r["best_impostor"] for r in known if r["best_impostor"] is not None]
    latencies = sorted(r["ms"] for r in rows)
    return {
        "queries": len(rows),
        "known_releases": n,
        "top1_accuracy": round(sum(r["rank"] == 1 for r in known) / n, 4)
        if n
        else None,
        "top5_accuracy": round(sum(r["rank"] is not None for r in known) / n, 4)
        if n
        else None,
        "thresholds": vars(thresholds),
        "decisions": decisions,
        "correct_matches": correct_matches,
        "wrong_matches": wrong_matches,
        "needs_review_containing_truth": review_with_truth,
        "user_reaches_correct_album": round(
            (correct_matches + review_with_truth) / n, 4
        )
        if n
        else None,
        "score_when_correct": describe(true_scores),
        "best_wrong_score": describe(impostors),
        "latency_ms": {
            "mean": round(statistics.mean(latencies), 1),
            "p95": round(latencies[int(0.95 * (len(latencies) - 1))], 1),
        },
        "threshold_sweep": sweep(known),
        "unknown_albums": {
            "queries": len(unknown),
            "decisions": {
                d.value: sum(r["decision"] == d.value for r in unknown)
                for d in Decision
            },
            "best_score": describe([r["top1_score"] for r in unknown]),
        },
        "misses": [
            {"query": r["query"], "top1": r["top1"], "rank": r["rank"]}
            for r in known
            if r["rank"] != 1
        ],
    }


def describe(values: list[float]) -> dict | None:
    if not values:
        return None
    return {
        "min": round(min(values), 3),
        "p10": round(float(np.percentile(values, 10)), 3),
        "median": round(statistics.median(values), 3),
        "p90": round(float(np.percentile(values, 90)), 3),
        "max": round(max(values), 3),
    }


def sweep(rows: list[dict]) -> list[dict]:
    """Outcomes for alternative match thresholds (margin and review fixed)."""
    out = []
    for match in (0.65, 0.70, 0.75, 0.80, 0.85):
        thresholds = Thresholds(match=match)
        right = wrong = 0
        for r in rows:
            decision, shown = decide(r["ranked"], thresholds)
            if decision is Decision.MATCH:
                if shown[0].entry.release_id == r["truth"]:
                    right += 1
                else:
                    wrong += 1
        out.append(
            {"match_threshold": match, "auto_matched": right, "wrong_matches": wrong}
        )
    return out


def without_releases(index: ReferenceIndex, count: int, seed: int) -> ReferenceIndex:
    releases = sorted({e.release_id for e in index.entries})
    hidden = set(random.Random(seed).sample(releases, count))
    keep = [i for i, e in enumerate(index.entries) if e.release_id not in hidden]
    return ReferenceIndex(
        index.embeddings[keep],
        [index.entries[i] for i in keep],
        index.model_id,
        index.preprocess_version,
    )


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("queries", type=Path, nargs="?", help="Folder of query photos")
    parser.add_argument(
        "--augment", type=int, default=0, help="Simulated photos per cover"
    )
    parser.add_argument("--dataset", type=Path, default=Path("data/dev"))
    parser.add_argument("--seed", type=int, default=1)
    parser.add_argument(
        "--holdout",
        type=int,
        default=0,
        help="Remove N releases from the index to test albums it does not know",
    )
    args = parser.parse_args()
    if (args.queries is None) == (args.augment == 0):
        parser.error("Give a query folder or --augment N, not both.")

    settings = RecognitionSettings.from_env()
    embedder = OnnxDinoEmbedder(settings.model_path)
    index = ReferenceIndex.load(
        settings.index_dir, embedder.model_id, PREPROCESS_VERSION
    )
    if args.holdout:
        index = without_releases(index, args.holdout, args.seed)
    recognizer = Recognizer(embedder, index, settings)
    queries = (
        augmented_queries(args.dataset, args.augment, args.seed)
        if args.augment
        else folder_queries(args.queries)
    )
    report = evaluate(queries, embedder, index, recognizer, settings.thresholds)
    report["model_id"] = embedder.model_id
    report["index_size"] = len(index)
    report["held_out_releases"] = args.holdout
    report["source"] = (
        f"augmented x{args.augment} from {args.dataset}"
        if args.augment
        else str(args.queries)
    )
    print(json.dumps(report, indent=2))
    return 0 if report["known_releases"] else 1


if __name__ == "__main__":
    sys.exit(main())
