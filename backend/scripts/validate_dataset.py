"""Check that the S2-02 reference dataset and its index are consistent.

Dataset checks (``--dataset``, the folder ``fetch_dev_covers`` writes):

- ``covers.csv`` has the columns ``release_id,artist,title,year,image``.
- Every ``release_id`` is a numeric Discogs ID; artist and title are filled;
  ``year`` is empty or plausible; one release never has two different names.
- Every image exists inside the folder, decodes, and is large enough.
- No image file is listed twice, and no two releases share identical image
  bytes (the matcher could never tell them apart).
- Images in ``images/`` that ``covers.csv`` does not list are reported.
- With ``--albums``, every album of the supported list made it into the
  dataset (fetching skips albums without a cover).

Index checks (``--index``, the folder ``build_index`` writes):

- The manifest lists the same rows as ``covers.csv``, in the same order.
- Embeddings are finite, unit length, and one row per entry.
- Every release can be looked up by ID and ranks first for its own embedding.
- Pairs of different releases above ``--confusable`` similarity are listed;
  they are the covers most likely to be mixed up.

Prints a JSON report, writes it with ``--report``, and exits with 1 when
there is any error (warnings alone exit with 0).
"""

import argparse
import csv
import hashlib
import json
import sys
from dataclasses import asdict, dataclass, field
from pathlib import Path

import numpy as np
from PIL import Image

from app.recognition.index import IndexLoadError, ReferenceIndex
from app.recognition.preprocess import InvalidImageError, load_image

REQUIRED_COLUMNS = ("release_id", "artist", "title", "year", "image")
MIN_IMAGE_SIDE = 300
MIN_YEAR = 1900
MAX_YEAR = 2100
DEFAULT_CONFUSABLE = 0.90
IMAGE_SUFFIXES = {".jpg", ".jpeg", ".png", ".webp"}


@dataclass
class Report:
    dataset: str
    rows: int = 0
    releases: int = 0
    images_checked: int = 0
    fingerprint: str = ""
    index: dict | None = None
    confusable_pairs: list[dict] = field(default_factory=list)
    errors: list[str] = field(default_factory=list)
    warnings: list[str] = field(default_factory=list)

    @property
    def ok(self) -> bool:
        return not self.errors


def _sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def read_rows(dataset: Path, report: Report) -> list[dict[str, str]]:
    csv_path = dataset / "covers.csv"
    if not csv_path.is_file():
        report.errors.append(f"{csv_path} is missing.")
        return []
    with csv_path.open(newline="", encoding="utf-8") as file:
        reader = csv.DictReader(file)
        missing = [c for c in REQUIRED_COLUMNS if c not in (reader.fieldnames or [])]
        if missing:
            report.errors.append(f"covers.csv is missing columns: {missing}")
            return []
        return [{k: (v or "").strip() for k, v in row.items()} for row in reader]


def check_dataset(dataset: Path, report: Report) -> list[dict[str, str]]:
    """Validate ``covers.csv`` and the images; return the rows that are usable."""
    rows = read_rows(dataset, report)
    report.rows = len(rows)
    root = dataset.resolve()
    names: dict[str, tuple[str, str, str]] = {}
    listed: set[Path] = set()
    image_owner: dict[str, str] = {}
    fingerprint = hashlib.sha256()
    usable = []

    for number, row in enumerate(rows, start=2):  # line 1 is the header
        where = f"covers.csv line {number}"
        release_id, image = row["release_id"], row["image"]
        row_errors = []
        if not release_id.isdigit():
            row_errors.append(f"{where}: release_id {release_id!r} is not numeric")
        if not row["artist"] or not row["title"]:
            row_errors.append(f"{where}: artist and title are required")
        if row["year"] and not (
            row["year"].isdigit() and MIN_YEAR <= int(row["year"]) <= MAX_YEAR
        ):
            row_errors.append(f"{where}: implausible year {row['year']!r}")

        name = (row["artist"], row["title"], row["year"])
        if release_id in names and names[release_id] != name:
            row_errors.append(
                f"{where}: release {release_id} is also listed as {names[release_id]}"
            )
        names.setdefault(release_id, name)

        path = (root / image).resolve()
        if not image or root not in path.parents:
            row_errors.append(f"{where}: image path {image!r} is outside the dataset")
        elif path in listed:
            row_errors.append(f"{where}: image {image} is listed twice")
        elif not path.is_file():
            row_errors.append(f"{where}: image {image} does not exist")
        else:
            listed.add(path)
            digest = _sha256(path)
            owner = image_owner.setdefault(digest, release_id)
            if owner != release_id:
                row_errors.append(
                    f"{where}: image {image} is identical to a cover of release {owner}"
                )
            try:
                with Image.open(path) as probe:
                    side = min(probe.size)
                load_image(path.read_bytes())
                report.images_checked += 1
                if side < MIN_IMAGE_SIDE:
                    report.warnings.append(
                        f"{where}: image {image} is small ({side} px shortest side)"
                    )
            except (OSError, InvalidImageError) as error:
                row_errors.append(f"{where}: image {image} cannot be read: {error}")
            fingerprint.update(
                f"{release_id}|{row['artist']}|{row['title']}|{row['year']}|"
                f"{image}|{digest}\n".encode()
            )

        report.errors.extend(row_errors)
        if not row_errors:
            usable.append(row)

    images_dir = root / "images"
    if images_dir.is_dir():
        for orphan in sorted(images_dir.rglob("*")):
            if orphan.suffix.lower() in IMAGE_SUFFIXES and orphan not in listed:
                report.warnings.append(
                    f"{orphan.relative_to(root)} is not listed in covers.csv"
                )

    report.releases = len(names)
    report.fingerprint = fingerprint.hexdigest()
    return usable


def check_albums(albums: Path, rows: list[dict[str, str]], report: Report) -> None:
    """Report albums of the supported list that did not reach the dataset."""
    with albums.open(newline="", encoding="utf-8") as file:
        wanted = list(csv.DictReader(file))
    present_ids = {row["release_id"] for row in rows}
    present_names = {(row["artist"].lower(), row["title"].lower()) for row in rows}
    for album in wanted:
        release_id = (album.get("release_id") or "").strip()
        name = (album["artist"].strip().lower(), album["title"].strip().lower())
        if release_id not in present_ids and name not in present_names:
            report.warnings.append(
                f"supported album missing from dataset: "
                f"{album['artist']} - {album['title']}"
            )


def check_index(
    index: ReferenceIndex,
    rows: list[dict[str, str]],
    report: Report,
    confusable: float = DEFAULT_CONFUSABLE,
) -> None:
    """Compare the index with the dataset and check every release is retrievable."""
    report.index = {
        "model_id": index.model_id,
        "preprocess_version": index.preprocess_version,
        "count": len(index),
        "releases": len(index.release_ids()),
        "dimension": index.dimension if len(index) else 0,
    }
    expected = [(row["release_id"], row["image"]) for row in rows]
    actual = [(entry.release_id, entry.image) for entry in index.entries]
    if expected != actual:
        missing = sorted(set(expected) - set(actual))
        extra = sorted(set(actual) - set(expected))
        report.errors.append(
            "index entries do not match covers.csv "
            f"(missing {len(missing)}, extra {len(extra)}, order differs: "
            f"{not missing and not extra}). Rebuild the index."
        )
    if len(index) == 0:
        return

    vectors = index.embeddings
    if not np.isfinite(vectors).all():
        report.errors.append("index contains non-finite embedding values")
        return
    norms = np.linalg.norm(vectors, axis=1)
    bad_norms = int((np.abs(norms - 1.0) > 1e-3).sum())
    if bad_norms:
        report.errors.append(f"{bad_norms} embeddings are not unit length")

    release_ids = index.release_ids()
    for release_id in release_ids:
        if index.get(release_id) is None:
            report.errors.append(f"release {release_id} cannot be looked up")
            continue
        for vector in index.vectors_for(release_id):
            best = index.search(vector, 1)
            if not best or best[0].entry.release_id != release_id:
                found = best[0].entry.release_id if best else None
                report.errors.append(
                    f"release {release_id}: its own cover ranks {found} first"
                )
                break

    owners = np.array([entry.release_id for entry in index.entries])
    similarity = vectors @ vectors.T
    pairs: dict[tuple[str, str], float] = {}
    for a, b in zip(*np.nonzero(np.triu(similarity, k=1) >= confusable), strict=True):
        if owners[a] == owners[b]:
            continue
        key = tuple(sorted((str(owners[a]), str(owners[b]))))
        pairs[key] = max(pairs.get(key, 0.0), float(similarity[a, b]))
    for (first, second), score in sorted(pairs.items(), key=lambda item: -item[1]):
        one, two = index.get(first), index.get(second)
        report.confusable_pairs.append(
            {
                "releases": [first, second],
                "albums": [
                    f"{one.artist} - {one.title}",
                    f"{two.artist} - {two.title}",
                ],
                "score": round(score, 4),
            }
        )
    if pairs:
        report.warnings.append(
            f"{len(pairs)} pairs of different releases score >= {confusable}; "
            "see confusable_pairs"
        )


def validate(
    dataset: Path,
    index_dir: Path | None = None,
    albums: Path | None = None,
    confusable: float = DEFAULT_CONFUSABLE,
) -> Report:
    report = Report(dataset=str(dataset))
    rows = check_dataset(dataset, report)
    if albums is not None:
        check_albums(albums, rows, report)
    if index_dir is not None:
        try:
            manifest = json.loads(
                (index_dir / "manifest.json").read_text(encoding="utf-8")
            )
            index = ReferenceIndex.load(
                index_dir, manifest.get("model_id"), manifest.get("preprocess_version")
            )
        except (OSError, ValueError, IndexLoadError) as error:
            report.errors.append(f"cannot load index from {index_dir}: {error}")
        else:
            check_index(index, rows, report, confusable)
    return report


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--dataset", type=Path, default=Path("data/reference"))
    parser.add_argument("--index", type=Path, default=None)
    parser.add_argument("--albums", type=Path, default=None)
    parser.add_argument("--confusable", type=float, default=DEFAULT_CONFUSABLE)
    parser.add_argument("--report", type=Path, default=None)
    args = parser.parse_args()

    report = validate(args.dataset, args.index, args.albums, args.confusable)
    text = json.dumps({"ok": report.ok, **asdict(report)}, indent=2, ensure_ascii=False)
    if args.report is not None:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(text + "\n", encoding="utf-8")
    print(text)
    summary = (
        f"{report.rows} rows, {report.releases} releases, "
        f"{len(report.errors)} errors, {len(report.warnings)} warnings"
    )
    print(summary, file=sys.stderr)
    return 0 if report.ok else 1


if __name__ == "__main__":
    raise SystemExit(main())
