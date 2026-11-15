"""Tests for the automatic album list and the faster cover download."""

import csv

import httpx
import pytest

from scripts.build_album_list import (
    DiscogsSearch,
    build_list,
    clean_artist,
    is_sorted_by_have,
    normalise,
    parse_result,
    write_rows,
)
from scripts.fetch_dev_covers import DiscogsCovers, fetch_album, save_ids


def result(
    release_id: int,
    title: str,
    have: int,
    master_id: int = 0,
    formats: tuple[str, ...] = ("Vinyl", "LP", "Album"),
    cover: str | None = None,
) -> dict:
    return {
        "id": release_id,
        "title": title,
        "year": "1977",
        "format": list(formats),
        "cover_image": cover or f"https://i.discogs.com/{release_id}.jpg",
        "community": {"have": have, "want": 10},
        "master_id": master_id,
    }


class FakeSearch:
    """Serves fixed pages per genre, like DiscogsSearch.page."""

    def __init__(self, pages: dict[str, list[list[dict]]]) -> None:
        self.pages = pages
        self.requests = 0

    def page(self, genre: str, page: int) -> tuple[list[dict], int]:
        self.requests += 1
        genre_pages = self.pages.get(genre, [])
        if page > len(genre_pages):
            return [], len(genre_pages)
        return genre_pages[page - 1], len(genre_pages)


def test_normalise_and_clean_artist():
    assert normalise("Björk – Homogenic!") == "bjork homogenic"
    assert normalise("AC/DC") == "ac dc"
    assert clean_artist("Nirvana (2)") == "Nirvana"
    assert clean_artist("Prince*") == "Prince"


def test_parse_result_keeps_vinyl_albums_only():
    album = parse_result(result(1, "Fleetwood Mac - Rumours", 900, 42), "Rock")
    assert album is not None
    assert (album.artist, album.title, album.release_id) == (
        "Fleetwood Mac",
        "Rumours",
        "1",
    )
    assert (album.have, album.master_id, album.genre) == (900, "42", "Rock")

    compilation = ("Vinyl", "LP", "Album", "Compilation")
    unusable = [
        result(2, "Various - Hits", 999),
        result(3, "A - B", 999, formats=compilation),
        result(4, "A - B", 999, formats=("Vinyl", '7"', "Single")),
        result(5, "A - B", 999, formats=("CD", "Album")),
        result(6, "No Separator", 999),
        result(7, "A - B", 999, cover="https://s.discogs.com/spacer.gif"),
    ]
    assert [parse_result(item, "Rock") for item in unusable] == [None] * 6


def test_build_list_dedupes_and_alternates_genres():
    search = FakeSearch(
        {
            "Rock": [
                [
                    result(10, "Queen - A Night At The Opera", 900, master_id=100),
                    result(11, "Queen - A Night At The Opera", 800, master_id=100),
                    result(12, "Led Zeppelin (2) - IV", 700, master_id=101),
                ]
            ],
            "Jazz": [[result(20, "Miles Davis - Kind Of Blue", 600, master_id=200)]],
        }
    )
    included = [{"artist": "Led Zeppelin", "title": "IV", "release_id": "999"}]

    rows = build_list(search, 10, ["Rock", "Jazz"], included, min_have=0)

    assert [(row["artist"], row["title"]) for row in rows] == [
        ("Led Zeppelin", "IV"),
        ("Queen", "A Night At The Opera"),
        ("Miles Davis", "Kind Of Blue"),
    ]
    assert rows[0]["release_id"] == "999"
    assert rows[1]["release_id"] == "10"  # The most collected pressing wins.
    assert rows[2]["genre"] == "Jazz"


def test_build_list_stops_at_target_and_applies_min_have():
    rock = [result(i, f"Artist {i} - Album {i}", 1000 - i) for i in range(1, 50)]
    search = FakeSearch({"Rock": [rock], "Pop": [[result(99, "P - Pop", 50)]]})
    warnings: list[str] = []

    rows = build_list(search, 5, ["Rock", "Pop"], min_have=100, warn=warnings.append)
    assert len(rows) == 5
    assert all(int(row["have"]) >= 100 for row in rows)

    short = build_list(
        FakeSearch({"Pop": [[result(99, "P - Pop", 50)]]}),
        5,
        ["Pop"],
        min_have=100,
        warn=warnings.append,
    )
    assert short == []
    assert any("only 0 albums found" in warning for warning in warnings)


def test_unsorted_results_are_reported():
    search = FakeSearch(
        {"Rock": [[result(1, "A - One", 10), result(2, "B - Two", 900)]]}
    )
    warnings: list[str] = []

    rows = build_list(search, 5, ["Rock"], min_have=0, warn=warnings.append)

    assert [row["title"] for row in rows] == ["Two", "One"]
    assert any("did not sort by popularity" in warning for warning in warnings)


def test_small_swaps_still_count_as_sorted():
    nearly = [result(i, f"A{i} - T{i}", 1000 - i) for i in range(20)]
    nearly[5], nearly[6] = nearly[6], nearly[5]
    random_order = [result(i, f"A{i} - T{i}", h) for i, h in enumerate([5, 9, 1, 7])]

    assert is_sorted_by_have(nearly)
    assert not is_sorted_by_have(random_order)
    assert is_sorted_by_have([])


def test_discogs_search_sends_filters_and_retries_rate_limits():
    calls: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        calls.append(request)
        if len(calls) == 1:
            return httpx.Response(429)
        body = {"pagination": {"pages": 3}, "results": [result(1, "A - B", 5)]}
        return httpx.Response(200, json=body)

    sleeps: list[float] = []
    with httpx.Client(transport=httpx.MockTransport(handler)) as client:
        search = DiscogsSearch(client, "token", sleep=sleeps.append, interval=0)
        results, pages = search.page("Hip Hop", 2)

    assert (len(results), pages, search.requests) == (1, 3, 2)
    assert 60 in sleeps
    params = calls[-1].url.params
    assert params["genre"] == "Hip Hop"
    assert params["format"] == "Vinyl"
    assert params["sort"] == "have"
    assert params["page"] == "2"
    assert calls[-1].headers["Authorization"] == "Discogs token=token"


def test_write_rows_has_fetch_columns(tmp_path):
    rows = build_list(
        FakeSearch({"Rock": [[result(1, "A - B", 5, master_id=7)]]}),
        1,
        ["Rock"],
        min_have=0,
    )
    path = tmp_path / "albums.csv"
    write_rows(path, rows)

    with path.open(encoding="utf-8") as file:
        stored = list(csv.DictReader(file))
    assert stored[0]["release_id"] == "1"
    assert stored[0]["cover_url"] == "https://i.discogs.com/1.jpg"
    assert {"artist", "title", "release_id", "year"} <= set(stored[0])


class CountingCovers(DiscogsCovers):
    def __init__(self) -> None:
        self.calls: list[str] = []

    def find_release_id(self, artist: str, title: str) -> str | None:
        self.calls.append("search")
        return "55"

    def release(self, release_id: str) -> dict:
        self.calls.append("release")
        return {"year": 1969, "images": [{"type": "primary", "uri": "https://x/p"}]}

    def download(self, url: str) -> bytes:
        self.calls.append(f"download {url}")
        return b"jpeg"


@pytest.fixture
def images(tmp_path):
    folder = tmp_path / "images"
    folder.mkdir()
    return folder


def test_rows_with_cover_url_need_one_request(images):
    covers = CountingCovers()
    album = {
        "artist": "A",
        "title": "B",
        "release_id": "1",
        "year": "1977",
        "cover_url": "https://i.discogs.com/1.jpg",
    }

    row = fetch_album(covers, album, images)

    assert covers.calls == ["download https://i.discogs.com/1.jpg"]
    assert row == {
        "release_id": "1",
        "artist": "A",
        "title": "B",
        "year": "1977",
        "image": "images/1.jpg",
    }
    assert (images / "1.jpg").read_bytes() == b"jpeg"

    covers.calls.clear()
    fetch_album(covers, album, images)
    assert covers.calls == []  # Already on disk: nothing is requested.


def test_hand_written_rows_still_use_search_and_release(images):
    covers = CountingCovers()
    album = {"artist": "The Beatles", "title": "Abbey Road", "release_id": ""}

    row = fetch_album(covers, album, images)

    assert covers.calls == ["search", "release", "download https://x/p"]
    assert album["release_id"] == "55"
    assert row["year"] == "1969"


def test_save_ids_keeps_extra_columns(tmp_path):
    path = tmp_path / "albums.csv"
    albums = [{"artist": "A", "title": "B", "release_id": "1", "have": "5"}]

    save_ids(path, albums, ["artist", "title", "release_id", "have"])

    assert path.read_text(encoding="utf-8").splitlines() == [
        "artist,title,release_id,have",
        "A,B,1,5",
    ]
