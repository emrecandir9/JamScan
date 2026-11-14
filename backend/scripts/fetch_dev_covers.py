"""Download album covers from Discogs for the reference dataset.

Reads ``artist,title,release_id`` rows. Rows without a release ID are looked
up with Discogs vinyl-release search; ``--save-ids`` writes the IDs found back
to the CSV so later runs fetch the same releases.

Rows from ``scripts.build_album_list`` also carry ``year`` and ``cover_url``:
those covers are downloaded directly, and an image already on disk needs no
request. A failing album is reported and skipped; ``covers.csv`` is written
even after Ctrl+C, so a long run is resumed by starting it again.
Covers are saved as
``<output>/images/<release_id>.jpg`` with a ``covers.csv`` that
``scripts.build_index`` reads. Cover art is copyrighted: keep the output out
of Git (``backend/data/`` is ignored).

Requires ``DISCOGS_TOKEN`` in the environment.
"""

import argparse
import csv
import os
import sys
import time
from pathlib import Path

import httpx

from scripts.api_checks import USER_AGENT
from scripts.discogs import DISCOGS_URL

# Authenticated Discogs requests are limited to 60 per minute.
REQUEST_INTERVAL_SECONDS = 1.1
MAX_RETRIES = 5


class DiscogsCovers:
    def __init__(self, client: httpx.Client, token: str) -> None:
        self._client = client
        self._headers = {
            "Authorization": f"Discogs token={token}",
            "User-Agent": USER_AGENT,
        }
        self._last_request = 0.0

    def _get(self, url: str, **params: str | int) -> httpx.Response:
        for attempt in range(MAX_RETRIES):
            wait = self._last_request + REQUEST_INTERVAL_SECONDS - time.monotonic()
            if wait > 0:
                time.sleep(wait)
            self._last_request = time.monotonic()
            try:
                response = self._client.get(
                    url, params=params, headers=self._headers, timeout=20
                )
            except httpx.TransportError:
                time.sleep(2**attempt)
                continue
            if response.status_code == 429:
                time.sleep(60)  # Rate limited: wait for the window to reset.
                continue
            if response.status_code >= 500:
                time.sleep(2**attempt)
                continue
            response.raise_for_status()
            return response
        raise RuntimeError(f"Discogs kept failing for {url}")

    def find_release_id(self, artist: str, title: str) -> str | None:
        results = (
            self._get(
                f"{DISCOGS_URL}/database/search",
                type="release",
                artist=artist,
                release_title=title,
                format="Vinyl",
                per_page=5,
            )
            .json()
            .get("results", [])
        )
        for result in results:
            if result.get("cover_image") and not result["cover_image"].endswith(
                "spacer.gif"
            ):
                return str(result["id"])
        return None

    def release(self, release_id: str) -> dict:
        return self._get(f"{DISCOGS_URL}/releases/{release_id}").json()

    def download(self, url: str) -> bytes:
        return self._get(url).content


def primary_image_url(release: dict) -> str | None:
    images = release.get("images") or []
    primary = [image for image in images if image.get("type") == "primary"]
    for image in primary or images:
        if image.get("uri"):
            return image["uri"]
    return None


def fetch_album(
    discogs: DiscogsCovers, album: dict[str, str], images_dir: Path
) -> dict[str, str] | None:
    """Download one cover and return its ``covers.csv`` row, or None."""
    release_id = (album.get("release_id") or "").strip()
    cover_url = (album.get("cover_url") or "").strip()
    year = (album.get("year") or "").strip()
    if not release_id:
        release_id = discogs.find_release_id(album["artist"], album["title"])
        if release_id is None:
            return None
        album["release_id"] = release_id
    image_path = images_dir / f"{release_id}.jpg"
    if not cover_url or (not year and not image_path.exists()):
        # Hand-written rows: the release gives the year and the cover.
        release = discogs.release(release_id)
        year = str(release.get("year") or "")
        cover_url = primary_image_url(release) or ""
        if not cover_url:
            return None
    if not image_path.exists():
        data = discogs.download(cover_url)
        temporary = image_path.with_suffix(".part")
        temporary.write_bytes(data)
        temporary.replace(image_path)  # No half-written images after a crash.
    return {
        "release_id": release_id,
        "artist": album["artist"],
        "title": album["title"],
        "year": year,
        "image": f"images/{release_id}.jpg",
    }

def write_covers(output: Path, rows: list[dict[str, str]]) -> None:
    with (output / "covers.csv").open("w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(
            file,
            fieldnames=["release_id", "artist", "title", "year", "image"],
            lineterminator="\n",
        )
        writer.writeheader()
        writer.writerows(rows)


def save_ids(path: Path, albums: list[dict[str, str]], fieldnames: list[str]) -> None:
    """Write the albums back with the release IDs found, keeping all columns."""
    with path.open("w", newline="", encoding="utf-8") as file:
        writer = csv.DictWriter(
            file, fieldnames=fieldnames, lineterminator="\n", extrasaction="ignore"
        )
        writer.writeheader()
        writer.writerows(albums)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--albums", type=Path, default=Path("datasets/dev_albums.csv"))
    parser.add_argument("--output", type=Path, default=Path("data/dev"))
    parser.add_argument("--save-ids", action="store_true")
    args = parser.parse_args()
    token = os.environ.get("DISCOGS_TOKEN", "").strip()
    if not token:
        parser.error("Set DISCOGS_TOKEN to fetch covers from Discogs.")

    with args.albums.open(newline="", encoding="utf-8") as file:
        reader = csv.DictReader(file)
        albums = list(reader)
        fieldnames = list(reader.fieldnames or ["artist", "title", "release_id"])
    images_dir = args.output / "images"
    images_dir.mkdir(parents=True, exist_ok=True)

    rows = []
    failed = 0
    try:
        with httpx.Client() as client:
            discogs = DiscogsCovers(client, token)
            for number, album in enumerate(albums, start=1):
                label = f"{album['artist']} - {album['title']}"
                try:
                    row = fetch_album(discogs, album, images_dir)
                except (httpx.HTTPError, RuntimeError, OSError) as error:
                    failed += 1
                    print(f"skip (error: {error}): {label}", file=sys.stderr)
                    continue
                if row is None:
                    print(f"skip (not found): {label}", file=sys.stderr)
                    continue
                rows.append(row)
                print(f"ok {row['release_id']} [{number}/{len(albums)}]: {label}")
    except KeyboardInterrupt:
        print("stopped: saving what was fetched so far", file=sys.stderr)
    finally:
        write_covers(args.output, rows)
        if args.save_ids:
            save_ids(args.albums, albums, fieldnames)
    print(
        f"{len(rows)} of {len(albums)} covers saved to {args.output}"
        + (f" ({failed} failed, run again to retry)" if failed else "")
    )
    return 0 if rows else 1


if __name__ == "__main__":
    raise SystemExit(main())
