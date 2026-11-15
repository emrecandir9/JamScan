# Large reference dataset

Extends the S2-02 reference dataset from a hand-picked list of 154 albums
to 5,000, chosen automatically from Discogs.

## How albums are chosen

`backend/scripts/build_album_list.py` searches Discogs for vinyl album
releases genre by genre, most collected first (`community.have`, the number
of Discogs users who own the release).

- One row per album: pressings of the same album share a Discogs master and
  are merged; the most collected pressing is kept.
- Skipped: compilations, singles, EPs, promos, test pressings, unofficial
  releases, "Various" artists, and releases without a cover.
- Genres take turns (rock, pop, electronic, hip hop, jazz, funk and soul,
  reggae, latin, blues, folk, classical, soundtracks), so no genre fills the
  whole list.
- `--min-have` (default 200) drops releases few people own.
- `--include datasets/reference_albums.csv` keeps the 154 hand-picked albums
  first, with their pinned release IDs, and never adds them twice.

The Discogs API documentation does not list popularity sorting for search.
A trial run showed that `sort=have` does work, with a few neighbouring
results swapped (Discogs' sort index lags behind the counts it shows). The
script treats a page as sorted when at least 90% of neighbouring pairs are
in order, and warns otherwise.

## Build it

From `backend/`, with the virtual environment active and `DISCOGS_TOKEN` set:

```bash
python -m scripts.build_album_list --target 5000 \
    --include datasets/reference_albums.csv \
    --output datasets/reference_albums_5k.csv
python -m scripts.fetch_dev_covers --albums datasets/reference_albums_5k.csv \
    --output data/reference_5k --save-ids
python -m scripts.build_index --dataset data/reference_5k --output data/index_5k
```

Rows from `build_album_list` carry the cover URL, so `fetch_dev_covers`
downloads each cover with one request instead of three. Covers already on
disk are not downloaded again, a failing album is reported and skipped,
requests are retried on rate limits and server errors, and `covers.csv` is
written even after Ctrl+C. To resume or retry failures, run the same command
again.

To use the large index in the backend, set `JAMSCAN_INDEX_DIR=data/index_5k`.

## Results

First full build on 2026-11-14 (Windows laptop, CPU):

| Item | Value |
| --- | --- |
| Albums in the list | 5,000 (154 hand-picked + 4,846 automatic) |
| Covers saved / failed | 5,000 / 0 |
| Images on disk | 506 MB |
| Index size (`embeddings.npy` + `manifest.json`) | 8.2 MB |
| Index rows, dimension | 5,000 × 384 |

Albums per genre: 404 each for Rock, Pop, Electronic, Hip Hop, Jazz,
Funk / Soul, Reggae, Latin, Blues and Folk, World, & Country; 403 each for
Classical and Stage & Screen; plus the 154 hand-picked albums. Every genre
reached its share above the default `--min-have 200`.

Albums per genre: Rock …, Pop …, Electronic …, Hip Hop …, Jazz …,
Funk / Soul …, Reggae …, Latin …, Blues …, Folk, World, & Country …,
Classical …, Stage & Screen …

## Size

- The phone is not affected: the dataset and model live on the backend,
  the app only sends the photo.
- The backend loads only the index (a few MB); recognition compares a photo
  with all 5,000 covers in a few milliseconds.
- Cover images are needed only to rebuild the index.

## Sharing

Cover images stay out of Git (`backend/data/` is ignored). The album list
`datasets/reference_albums_5k.csv` is committed, so anyone can rebuild the
same dataset. The index folder (`embeddings.npy` and `manifest.json`) is
shared as a zip file; unzip it into `backend/data/index_5k`.

## Next

- Measure accuracy again with the S2-03 evaluation: more albums means more
  look-alike covers, so a small drop is expected and worth reporting.
- Run `scripts/validate_dataset.py` on this dataset once S2-02 (PR #16) is
  merged into main.