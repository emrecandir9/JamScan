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

import re
import unicodedata
from dataclasses import dataclass

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
