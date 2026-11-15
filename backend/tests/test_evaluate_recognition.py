from app.recognition.config import Thresholds
from scripts.evaluate_recognition import (
    evaluate,
    folder_queries,
    release_id_of,
    without_releases,
)
from tests.recognition_fakes import (
    MeanColourEmbedder,
    fake_recognizer,
    rgb_index,
    striped_jpeg,
)


def test_release_id_comes_from_the_file_name(tmp_path) -> None:
    assert release_id_of(tmp_path / "12643712__phone.jpg") == "12643712"
    assert release_id_of(tmp_path / "12643712.jpg") == "12643712"


def test_report_counts_matches_reviews_and_unknown_albums(tmp_path) -> None:
    (tmp_path / "1__red.jpg").write_bytes(striped_jpeg((200, 10, 10)))
    (tmp_path / "3__purple.jpg").write_bytes(striped_jpeg((200, 10, 200)))
    (tmp_path / "9__unknown.jpg").write_bytes(striped_jpeg((160, 160, 160)))
    (tmp_path / "notes.txt").write_text("ignored")

    report = evaluate(
        folder_queries(tmp_path),
        MeanColourEmbedder(),
        rgb_index(),
        fake_recognizer(),
        Thresholds(),
    )

    assert report["queries"] == 3
    assert report["known_releases"] == 2
    assert report["top1_accuracy"] == 0.5  # purple ranks red first
    assert report["top5_accuracy"] == 1.0
    assert report["decisions"]["match"] == 1
    assert report["decisions"]["needs_review"] == 1
    assert report["needs_review_containing_truth"] == 1
    assert report["user_reaches_correct_album"] == 1.0
    assert report["wrong_matches"] == []
    assert report["unknown_albums"]["decisions"]["no_match"] == 1


def test_holdout_hides_whole_releases() -> None:
    index = without_releases(rgb_index(), 1, seed=1)

    assert len(index) == 2
    assert index.embeddings.shape == (2, 3)
