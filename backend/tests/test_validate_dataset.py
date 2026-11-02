"""Tests for the S2-02 dataset and index consistency checks."""

import csv
from pathlib import Path

import numpy as np
from recognition_fakes import MeanColourEmbedder, entry, rgb_index, striped_jpeg

from app.recognition.index import ReferenceIndex
from app.recognition.preprocess import PREPROCESS_VERSION
from scripts.build_index import build
from scripts.validate_dataset import validate

COLOURS = {
    "101": ("Artist A", "Red Album", (200, 30, 30)),
    "102": ("Artist B", "Green Album", (30, 200, 30)),
    "103": ("Artist C", "Blue Album", (30, 30, 200)),
}


def make_dataset(folder: Path, rows: list[dict] | None = None) -> Path:
    images = folder / "images"
    images.mkdir(parents=True)
    if rows is None:
        rows = []
        for release_id, (artist, title, colour) in COLOURS.items():
            (images / f"{release_id}.jpg").write_bytes(striped_jpeg(colour, 400))
            rows.append(
                {
                    "release_id": release_id,
                    "artist": artist,
                    "title": title,
                    "year": "1999",
                    "image": f"images/{release_id}.jpg",
                }
            )
    with (folder / "covers.csv").open("w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(
            file, fieldnames=["release_id", "artist", "title", "year", "image"]
        )
        writer.writeheader()
        writer.writerows(rows)
    return folder


def rewrite_rows(folder: Path, change) -> None:
    path = folder / "covers.csv"
    with path.open(newline="", encoding="utf-8") as file:
        rows = list(csv.DictReader(file))
    change(rows)
    with path.open("w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, fieldnames=list(rows[0]))
        writer.writeheader()
        writer.writerows(rows)


def test_valid_dataset_and_index_pass(tmp_path):
    dataset = make_dataset(tmp_path / "ds")
    build(dataset, MeanColourEmbedder()).save(tmp_path / "index")

    report = validate(dataset, tmp_path / "index")

    assert report.ok, report.errors
    assert (report.rows, report.releases, report.images_checked) == (3, 3, 3)
    assert report.index["count"] == 3
    assert len(report.fingerprint) == 64


def test_fingerprint_is_reproducible_and_tracks_changes(tmp_path):
    first = validate(make_dataset(tmp_path / "a")).fingerprint
    second = validate(make_dataset(tmp_path / "b")).fingerprint
    assert first == second

    rewrite_rows(tmp_path / "b", lambda rows: rows[0].update(year="2001"))
    assert validate(tmp_path / "b").fingerprint != first


def test_missing_columns_are_an_error(tmp_path):
    folder = tmp_path / "ds"
    folder.mkdir()
    (folder / "covers.csv").write_text("release_id,image\n1,a.jpg\n", encoding="utf-8")

    report = validate(folder)

    assert not report.ok
    assert "missing columns" in report.errors[0]


def test_bad_rows_are_reported(tmp_path):
    dataset = make_dataset(tmp_path / "ds")

    def corrupt(rows):
        rows[0]["release_id"] = "r101"
        rows[1]["year"] = "0"
        rows[2]["image"] = "images/missing.jpg"

    rewrite_rows(dataset, corrupt)
    errors = " | ".join(validate(dataset).errors)

    assert "not numeric" in errors
    assert "implausible year" in errors
    assert "does not exist" in errors


def test_conflicting_names_and_shared_images_are_errors(tmp_path):
    dataset = make_dataset(tmp_path / "ds")
    (dataset / "images" / "copy.jpg").write_bytes(
        (dataset / "images" / "101.jpg").read_bytes()
    )

    def add(rows):
        rows.append({**rows[1], "title": "Other Title", "image": "images/101.jpg"})
        rows.append({**rows[2], "image": "images/copy.jpg"})

    rewrite_rows(dataset, add)
    errors = " | ".join(validate(dataset).errors)

    assert "is also listed as" in errors
    assert "listed twice" in errors
    assert "identical to a cover of release 101" in errors


def test_path_outside_dataset_and_unreadable_image(tmp_path):
    dataset = make_dataset(tmp_path / "ds")
    (tmp_path / "outside.jpg").write_bytes(striped_jpeg((1, 2, 3)))
    (dataset / "images" / "103.jpg").write_text("not an image", encoding="utf-8")
    rewrite_rows(dataset, lambda rows: rows[0].update(image="../outside.jpg"))

    errors = " | ".join(validate(dataset).errors)

    assert "outside the dataset" in errors
    assert "cannot be read" in errors


def test_orphans_small_images_and_missing_albums_are_warnings(tmp_path):
    dataset = make_dataset(tmp_path / "ds")
    (dataset / "images" / "stray.jpg").write_bytes(striped_jpeg((9, 9, 9)))
    (dataset / "images" / "102.jpg").write_bytes(striped_jpeg((30, 200, 30), 128))
    albums = tmp_path / "albums.csv"
    albums.write_text(
        "artist,title,release_id\nArtist A,Red Album,101\nNobody,Lost Album,\n",
        encoding="utf-8",
    )

    report = validate(dataset, albums=albums)
    warnings = " | ".join(report.warnings)

    assert report.ok, report.errors
    assert "stray.jpg is not listed" in warnings
    assert "is small (128 px" in warnings
    assert "Nobody - Lost Album" in warnings
    assert "Red Album" not in warnings


def test_stale_index_is_an_error(tmp_path):
    dataset = make_dataset(tmp_path / "ds")
    build(dataset, MeanColourEmbedder()).save(tmp_path / "index")
    rewrite_rows(dataset, lambda rows: rows.pop())

    errors = " | ".join(validate(dataset, tmp_path / "index").errors)

    assert "index entries do not match covers.csv" in errors


def test_missing_index_is_an_error(tmp_path):
    dataset = make_dataset(tmp_path / "ds")

    report = validate(dataset, tmp_path / "nothing-here")

    assert "cannot load index" in report.errors[0]


def test_confusable_releases_are_listed(tmp_path):
    index = ReferenceIndex(
        np.array([[1, 0, 0], [0.99, 0.141, 0], [0, 0, 1]], dtype=np.float32),
        [entry("1", "Red"), entry("2", "Almost Red"), entry("3", "Blue")],
        "fake",
        PREPROCESS_VERSION,
    )
    index.embeddings /= np.linalg.norm(index.embeddings, axis=1, keepdims=True)
    index.save(tmp_path / "index")
    rows = [{"release_id": e.release_id, "image": e.image} for e in index.entries]
    dataset = tmp_path / "ds"
    dataset.mkdir()

    from scripts.validate_dataset import Report, check_index

    report = Report(dataset=str(dataset))
    check_index(index, rows, report, confusable=0.9)

    assert report.ok, report.errors
    assert [pair["releases"] for pair in report.confusable_pairs] == [["1", "2"]]
    assert report.confusable_pairs[0]["score"] > 0.98


def test_index_lookup_by_release_id():
    index = rgb_index()

    assert index.release_ids() == ["1", "2", "3"]
    assert index.get("2").title == "Green"
    assert index.get("404") is None
    assert index.vectors_for("3").shape == (1, 3)
    assert index.vectors_for("404").shape == (0, 3)
