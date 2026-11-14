"""Build a large list of popular vinyl albums from Discogs search.

Searches Discogs for vinyl album releases genre by genre, asking for the most
collected releases first (``community.have``). Pressings of the same album
are merged (one row per Discogs master), compilations and singles are
skipped, and the genres take turns so rock does not fill the whole list.

The output has the same ``artist,title,release_id`` columns as
``datasets/reference_albums.csv`` plus ``year``, ``cover_url``, ``have``,
``genre`` and ``master_id``. ``scripts.fetch_dev_covers`` reads it and, thanks
to ``cover_url``, downloads each cover with one request instead of three.

Albums from ``--include`` (for example the hand-picked list) come first and
are never duplicated.

Example::

    python -m scripts.build_album_list --target 3000 \\
        --include datasets/reference_albums.csv \\
        --output datasets/reference_albums_3k.csv

Requires ``DISCOGS_TOKEN`` in the environment.
"""

import argparse
import csv
import os
import re
import sys
import time
import unicodedata
from collections.abc import Callable, Iterable, Iterator
from dataclasses import dataclass
from pathlib import Path

import httpx

from scripts.api_checks import USER_AGENT
from scripts.discogs import DISCOGS_URL

# Authenticated Discogs requests are limited to 60 per minute.
REQUEST_INTERVAL_SECONDS = 1.1
MAX_RETRIES = 5
PER_PAGE = 100
# Discogs search stops returning results after about 100 pages.
MAX_PAGES = 100

GENRES = (
    "Rock",
    "Pop",
    "Electronic",
    "Hip Hop",
    "Jazz",
    "Funk / Soul",
    "Reggae",
    "Latin",
    "Blues",
    "Folk, World, & Country",
    "Classical",
    "Stage & Screen",
)
SKIP_FORMATS = {
    "compilation",
    "single",
    "ep",
    "promo",
    "test pressing",
    "unofficial release",
    "sampler",
    "transcription",
}
OUTPUT_COLUMNS = (
    "artist",
    "title",
    "release_id",
    "year",
    "cover_url",
    "have",
    "genre",
    "master_id",
)


@dataclass
class Candidate:
    artist: str
    title: str
    release_id: str
    year: str
    cover_url: str
    have: int
    genre: str
    master_id: str

    def row(self) -> dict[str, str]:
        return {
            "artist": self.artist,
            "title": self.title,
            "release_id": self.release_id,
            "year": self.year,
            "cover_url": self.cover_url,
            "have": str(self.have),
            "genre": self.genre,
            "master_id": self.master_id,
        }


def normalise(text: str) -> str:
    """Lowercase ASCII words only, for comparing album names."""
    ascii_text = unicodedata.normalize("NFKD", text).encode("ascii", "ignore").decode()
    return " ".join(re.findall(r"[a-z0-9]+", ascii_text.lower()))


def clean_artist(name: str) -> str:
    """Remove Discogs disambiguation: ``Nirvana (2)`` and ``Prince*``."""
    return re.sub(r"\s*\(\d+\)$", "", name.strip().rstrip("*")).strip()


def parse_result(result: dict, genre: str) -> Candidate | None:
    """Turn one search result into a candidate, or None if it is unusable."""
    formats = {str(item).strip().lower() for item in result.get("format") or []}
    if "vinyl" not in formats or "album" not in formats or formats & SKIP_FORMATS:
        return None
    cover = result.get("cover_image") or ""
    if not cover.startswith("https://") or cover.endswith("spacer.gif"):
        return None
    artist, separator, title = str(result.get("title") or "").partition(" - ")
    artist, title = clean_artist(artist), title.strip()
    if not separator or not artist or not title or artist.lower() == "various":
        return None
    release_id = result.get("id")
    if not isinstance(release_id, int) or release_id <= 0:
        return None
    community = result.get("community") or {}
    have = community.get("have")
    master_id = result.get("master_id")
    return Candidate(
        artist=artist,
        title=title,
        release_id=str(release_id),
        year=str(result.get("year") or ""),
        cover_url=cover,
        have=have if isinstance(have, int) else 0,
        genre=genre,
        master_id=str(master_id) if isinstance(master_id, int) and master_id else "",
    )


class DiscogsSearch:
    def __init__(
        self,
        client: httpx.Client,
        token: str,
        sleep: Callable[[float], None] = time.sleep,
        interval: float = REQUEST_INTERVAL_SECONDS,
    ) -> None:
        self._client = client
        self._headers = {
            "Authorization": f"Discogs token={token}",
            "User-Agent": USER_AGENT,
        }
        self._sleep = sleep
        self._interval = interval
        self._last_request = 0.0
        self.requests = 0

    def page(self, genre: str, page: int) -> tuple[list[dict], int]:
        """One page of vinyl album releases; returns results and page count."""
        params = {
            "type": "release",
            "format": "Vinyl",
            "genre": genre,
            "sort": "have",
            "sort_order": "desc",
            "per_page": PER_PAGE,
            "page": page,
        }
        for attempt in range(MAX_RETRIES):
            wait = self._last_request + self._interval - time.monotonic()
            if wait > 0:
                self._sleep(wait)
            self._last_request = time.monotonic()
            self.requests += 1
            try:
                response = self._client.get(
                    f"{DISCOGS_URL}/database/search",
                    params=params,
                    headers=self._headers,
                    timeout=30,
                )
            except httpx.TransportError:
                self._sleep(2**attempt)
                continue
            if response.status_code == 429 or response.status_code >= 500:
                self._sleep(max(2**attempt, 60 if response.status_code == 429 else 0))
                continue
            response.raise_for_status()
            body = response.json()
            pages = (body.get("pagination") or {}).get("pages") or 0
            return body.get("results") or [], int(pages)
        raise RuntimeError(f"Discogs search kept failing for {genre!r} page {page}")


def is_sorted_by_have(results: list[dict]) -> bool:
    haves = [(result.get("community") or {}).get("have") or 0 for result in results]
    return all(a >= b for a, b in zip(haves, haves[1:], strict=False))


def genre_candidates(
    search: DiscogsSearch,
    genre: str,
    min_have: int,
    warn: Callable[[str], None],
) -> Iterator[Candidate]:
    """Usable candidates of one genre, most collected first, page by page."""
    page, pages = 1, 1
    while page <= min(pages, MAX_PAGES):
        results, pages = search.page(genre, page)
        if not results:
            return
        if page == 1 and not is_sorted_by_have(results):
            warn(
                f"{genre}: Discogs did not sort by popularity; "
                "results are filtered by --min-have instead"
            )
        page_candidates = [
            candidate
            for result in results
            if (candidate := parse_result(result, genre)) is not None
        ]
        yield from sorted(page_candidates, key=lambda c: -c.have)
        if is_sorted_by_have(results) and all(
            ((r.get("community") or {}).get("have") or 0) < min_have for r in results
        ):
            return  # Sorted results only get less popular from here.
        page += 1


def read_included(path: Path | None) -> list[dict[str, str]]:
    if path is None:
        return []
    with path.open(newline="", encoding="utf-8") as file:
        return [
            {key: (value or "").strip() for key, value in row.items()}
            for row in csv.DictReader(file)
        ]


def build_list(
    search: DiscogsSearch,
    target: int,
    genres: Iterable[str] = GENRES,
    included: list[dict[str, str]] | None = None,
    min_have: int = 200,
    warn: Callable[[str], None] = lambda message: print(message, file=sys.stderr),
) -> list[dict[str, str]]:
    """Included albums first, then genres in turn until ``target`` rows."""
    rows: list[dict[str, str]] = []
    seen_names: set[tuple[str, str]] = set()
    seen_ids: set[str] = set()
    seen_masters: set[str] = set()

    def add(row: dict[str, str]) -> bool:
        name = (normalise(row["artist"]), normalise(row["title"]))
        release_id = row.get("release_id", "")
        master_id = row.get("master_id", "")
        if (
            name in seen_names
            or (release_id and release_id in seen_ids)
            or (master_id and master_id in seen_masters)
        ):
            return False
        seen_names.add(name)
        if release_id:
            seen_ids.add(release_id)
        if master_id:
            seen_masters.add(master_id)
        rows.append({column: row.get(column, "") for column in OUTPUT_COLUMNS})
        return True

    for row in included or []:
        add(row)

    streams = {
        genre: genre_candidates(search, genre, min_have, warn) for genre in genres
    }
    while len(rows) < target and streams:
        for genre in list(streams):
            if len(rows) >= target:
                break
            for candidate in streams[genre]:
                if candidate.have >= min_have and add(candidate.row()):
                    break
            else:
                del streams[genre]  # This genre has no usable albums left.
    if len(rows) < target:
        warn(
            f"only {len(rows)} albums found; lower --min-have or add genres "
            f"to reach {target}"
        )
    return rows


def write_rows(path: Path, rows: list[dict[str, str]]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(file, fieldnames=OUTPUT_COLUMNS, lineterminator="\n")
        writer.writeheader()
        writer.writerows(rows)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--target", type=int, default=3000)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--include", type=Path, default=None)
    parser.add_argument("--min-have", type=int, default=200)
    parser.add_argument("--genres", nargs="+", default=list(GENRES))
    args = parser.parse_args()
    token = os.environ.get("DISCOGS_TOKEN", "").strip()
    if not token:
        parser.error("Set DISCOGS_TOKEN to search Discogs.")

    with httpx.Client() as client:
        search = DiscogsSearch(client, token)
        rows = build_list(
            search,
            args.target,
            args.genres,
            read_included(args.include),
            args.min_have,
        )
    write_rows(args.output, rows)
    by_genre: dict[str, int] = {}
    for row in rows:
        key = row["genre"] or "(included)"
        by_genre[key] = by_genre.get(key, 0) + 1
    for genre, count in sorted(by_genre.items(), key=lambda item: -item[1]):
        print(f"{count:6d}  {genre}")
    print(
        f"{len(rows)} albums written to {args.output} "
        f"({search.requests} Discogs requests)"
    )
    return 0 if rows else 1


if __name__ == "__main__":
    raise SystemExit(main())
