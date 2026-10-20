# Album data model (S1-06, extended in S2-05)

> As a developer, I want an initial album data model so that recognition
> results can be represented consistently.

The model is implemented with [Drift](https://drift.simonbinder.eu/) over
SQLite, the local-storage stack named in the project README. Source files:

| Purpose | File |
| --- | --- |
| Table definitions | `mobile/lib/data/local/tables.dart` |
| Database and migration | `mobile/lib/data/local/app_database.dart` |
| Album and track access | `mobile/lib/data/local/daos/album_dao.dart` |
| List and duplicate access | `mobile/lib/data/local/daos/list_dao.dart` |
| Sample data | `mobile/lib/data/local/seed_data.dart` |
| Rows to Album Details view model (S2-05) | `mobile/lib/data/local/album_mapping.dart` |
| Backend release JSON to rows (S2-05) | `mobile/lib/data/release_metadata.dart` |
| Metadata cache (S2-05) | `mobile/lib/data/release_repository.dart` |
| Tests | `mobile/test/data/album_data_model_test.dart`, `mobile/test/data/extended_metadata_test.dart` |

The editable diagram is [`jamscan_ERdiagram.drawio`](jamscan_ERdiagram.drawio),
openable with [draw.io](https://app.diagrams.net/).

## Entity relationship diagram

```mermaid
erDiagram
    USERS ||--o{ LISTS : owns
    USERS ||--o{ HISTORY_ENTRIES : records
    LISTS ||--o{ LIST_ENTRIES : holds
    ALBUMS ||--o{ LIST_ENTRIES : "saved as"
    ALBUMS ||--o{ TRACKS : contains
    ALBUMS ||--o{ HISTORY_ENTRIES : "resolved to"

    USERS {
        INTEGER id PK
        TEXT display_name
        TEXT email UK
        TEXT password_hash
        DATETIME created_at
    }
    LISTS {
        INTEGER id PK
        INTEGER user_id FK
        TEXT name
        TEXT type "collection | wishlist"
        DATETIME created_at
    }
    LIST_ENTRIES {
        INTEGER id PK
        INTEGER list_id FK
        INTEGER album_id FK
        TEXT owned_format
        TEXT condition
        TEXT notes
        INTEGER priority
        DATETIME added_at
    }
    ALBUMS {
        INTEGER id PK
        TEXT release_id UK "nullable"
        TEXT artist
        TEXT title
        INTEGER year "nullable"
        TEXT cover_path "nullable"
        TEXT discogs_format "nullable"
        TEXT metadata_source
        DATETIME fetched_at
        TEXT cover_url "nullable, v2"
        TEXT label "nullable, v2"
        TEXT catalog_number "nullable, v2"
        TEXT genres "JSON array, v2"
        TEXT styles "JSON array, v2"
        REAL rating "nullable, v2"
        TEXT preview_status "nullable, v2"
    }
    }
    TRACKS {
        INTEGER id PK
        INTEGER album_id FK
        INTEGER position
        TEXT title
        INTEGER popularity_rank "nullable"
        TEXT preview_url "nullable"
        TEXT preview_source "nullable"
        TEXT position_label "nullable, v2"
        INTEGER duration_seconds "nullable, v2"
    }
    }
    HISTORY_ENTRIES {
        INTEGER id PK
        INTEGER user_id FK
        INTEGER album_id FK "nullable"
        TEXT kind "scan | manual_search"
        TEXT query_text "nullable"
        TEXT image_path "nullable"
        REAL confidence "nullable"
        DATETIME created_at
    }
```

## Team decisions

### 1. Synthetic integer primary key, Discogs id as a unique attribute

`albums.id` is an autoincrementing integer; the Discogs identifier is stored
separately in `albums.release_id` with a unique index and may be null.

A manual entry or an unrecognised scan has no Discogs identifier, so the
Discogs id cannot be the primary key. Keeping it as a unique attribute still
prevents the same release from being stored twice, and foreign keys in
`tracks`, `list_entries`, and `history_entries` stay narrow integers.

`AlbumDao.saveAlbumWithTracks` uses this rule: when an album with the same
`release_id` already exists, the row is updated and its tracklist replaced
rather than inserted again.

### 2. Duplicate rule: one album per list

`list_entries` has a unique key on `(list_id, album_id)`.

The team agreed the rule as "unique `(list_id, release_id)`". It is enforced on
`album_id` because that is the foreign key actually stored in the row, and
`albums.release_id` is itself unique, so the two are equivalent for any album
that has a Discogs identifier. Enforcing it on `album_id` additionally covers
manually added albums, which have no `release_id`.

The same album may appear in a collection and in a wishlist, since those are
two different lists.

Call `ListDao.addAlbumToListIfAbsent` from the UI: it returns `null` for a
duplicate so the screen can show a message. `ListDao.addAlbumToList` inserts
directly and lets the database reject a duplicate with an exception.

### 3. Delete behaviour: cascade

Deleting a row removes the rows that cannot exist without it:

| Parent | Child | Behaviour |
| --- | --- | --- |
| `albums` | `tracks` | cascade |
| `albums` | `list_entries` | cascade |
| `lists` | `list_entries` | cascade |
| `users` | `lists` | cascade |
| `users` | `history_entries` | cascade |
| `albums` | `history_entries` | set null |

A tracklist and a saved entry have no meaning without their album, so cascade
avoids orphaned rows and extra cleanup code. History is the exception: a scan
the user performed still happened even if the album is later removed, so
`history_entries.album_id` is set to null instead of deleting the record.

SQLite only enforces foreign keys when they are switched on per connection, so
`AppDatabase.migration` runs `PRAGMA foreign_keys = ON` in `beforeOpen`.

### 4. Cover images on disk, path stored in the database

`albums.cover_path` holds a path, not image bytes.

Cover art is large and binary. Storing it in SQLite inflates the database file,
slows queries that do not need the image, and complicates backups. Writing the
file to application storage and keeping a path keeps rows small and lets the
image be loaded lazily by the UI. A null path means no cover has been
downloaded yet.

### 5. Extended metadata (S2-05, schema version 2)

The Album Details screen needs the metadata the backend's
`GET /releases/{release_id}` (S2-04) returns. The columns follow that
response field by field:

| Backend field | Column | Notes |
| --- | --- | --- |
| `cover_url` | `albums.cover_url` | Remote URL; `cover_path` stays the local file (decision 4) |
| `label` | `albums.label` | First label of the release |
| `catalog_number` | `albums.catalog_number` | |
| `genres`, `styles` | `albums.genres`, `albums.styles` | JSON arrays, default `[]` |
| `rating` | `albums.rating` | Discogs community average out of 5 |
| `preview_status` | `albums.preview_status` | `available`, `partial`, `none_found`, `service_unavailable` |
| `tracks[].position` | `tracks.position_label` | Printed position such as `A1` |
| `tracks[].duration` | `tracks.duration_seconds` | `4:13` stored as 253 |
| `tracks[].preview_url` | `tracks.preview_url` | `preview_source` is set to `itunes` |

- **Genres and styles as JSON text** rather than separate tables: they are
  only ever read together with their album, and no screen filters by them
  yet. `StringListConverter` maps the column to `List<String>`. If filtering
  by genre is needed later, an `album_genres` table can be added with a
  migration.
- **Two track positions.** `tracks.position` stays an integer (1, 2, 3) and
  keeps ordering the tracklist and the unique key. Vinyl positions such as
  `A1` or `B2` do not sort as numbers, so the printed value is stored
  separately in `position_label`.
- **Durations in seconds** so they can be summed and formatted by the UI.
  Discogs often leaves durations blank; those are stored as null.

### 6. Caching fetched metadata (S2-05)

`ReleaseRepository.load(releaseId)` puts the database in front of the
backend:

1. A release with `metadata_source = 'discogs'` fetched less than **7 days**
   ago (`fetched_at`) is returned from the database without a request.
2. Otherwise the backend is called, the response is stored with
   `AlbumDao.saveRelease`, and the stored rows are returned.
3. If the request fails and an older copy exists, the old copy is returned
   with `isStale = true`; the screen shows it as partial metadata
   (`Album.isPartial`). With no copy, the error goes to the caller, which
   shows the "unavailable" state.

Seven days because a pressing's Discogs data rarely changes, while iTunes
preview links can. Refreshing keeps `cover_path`, so a downloaded cover is
not lost. The HTTP call itself is injected (`ReleaseFetcher`) and is wired up
by the integration story (S2-07).

`AlbumWithTracks.toViewModel()` converts stored rows into the `Album` view
model of `lib/models/album.dart`, which Album Details already uses.

### Migration from version 1

`schemaVersion` is 2. `AppDatabase.migration.onUpgrade` adds the nine
columns above with `ALTER TABLE ... ADD COLUMN` when upgrading from 1, so
albums, tracks, lists and history already on a device are kept. A test
creates a version 1 database, opens it with the current code, and checks
both the old rows and the new columns.

## Nullability note

The diagram marks only `release_id`, `album_id` in history, and the preview and
query columns as nullable. In the implementation `year`, `cover_path`,
`discogs_format`, `popularity_rank`, and `preview_source` are also nullable,
because a scan or a manual entry can produce an album before those values are
known. Everything else is `NOT NULL`.

## Generated code

Drift generates `*.g.dart` files next to the sources. They are committed so
that `flutter analyze` and `flutter test` work in CI without a code-generation
step. After changing a table or a DAO, run from `mobile/`:

```bash
dart run build_runner build
dart format lib test
```

Any change to a table also needs `schemaVersion` to be raised and a migration
added in `AppDatabase.migration`, once the app ships with real user data.

## Sample data

`insertSeedData` creates one user, a collection, a wishlist, and five albums
with tracklists, three of which are saved into the lists. It is used by the
tests and can be called from a development build to populate an empty database.

## Validation

From `mobile/`:

```bash
flutter pub get
dart run build_runner build
dart format lib test
flutter analyze
flutter test
flutter build apk --debug
```

The tests cover storing and reloading an album with its tracks, re-saving the
same release, rejection of a duplicate list entry, cascade on album delete,
cascade on user delete, and the seed data.


S2-05 adds tests for parsing the backend response and durations, storing and
reading every new field, default values, keeping a downloaded cover on
refresh, the cache rules (fresh, expired, forced refresh, offline fallback,
error without cache, replacing seed data), mapping to the view model, and the
version 1 to 2 migration.

## Still missing for the wireframes

From the list in [UI_SHELL.md](UI_SHELL.md): `albums.country` and the rating
count (not in the S2-04 response yet), and the `list_entries` ghost flag and
"looking for" note. Tracks have no popularity rank from Discogs or iTunes, so
`Album.topTracks` stays empty for fetched albums until a source for it is
chosen.