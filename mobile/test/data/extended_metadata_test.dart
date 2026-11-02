import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jamscan/data/local/album_mapping.dart';
import 'package:jamscan/data/local/app_database.dart';
import 'package:jamscan/data/release_metadata.dart';
import 'package:jamscan/data/release_repository.dart';
import 'package:jamscan/models/album.dart' as model;

import '../support/test_database.dart';

/// Shape of `GET /releases/{release_id}` from the S2-04 backend.
Map<String, Object?> releaseJson({
  int id = 31621720,
  String title = 'Random Access Memories',
}) {
  return {
    'discogs_id': id,
    'artist': 'Daft Punk',
    'title': title,
    'year': 2013,
    'cover_url': 'https://i.discogs.com/ram.jpg',
    'label': 'Columbia',
    'catalog_number': '88883716861',
    'genres': ['Electronic', 'Funk / Soul'],
    'styles': ['Disco', 'Synth-pop'],
    'rating': 4.42,
    'tracks': [
      {
        'position': 'A1',
        'title': 'Give Life Back To Music',
        'duration': '4:34',
        'preview_url': 'https://audio.itunes.example/a1.m4a',
        'track_view_url': 'https://music.apple.example/a1',
      },
      {
        'position': 'A2',
        'title': 'The Game Of Love',
        'duration': '',
        'preview_url': null,
        'track_view_url': null,
      },
      {
        'position': 'D3',
        'title': 'Contact',
        'duration': '6:21',
        'preview_url': null,
        'track_view_url': null,
      },
    ],
    'preview_status': 'partial',
    'previews_checked': 3,
    'previews_available': 1,
    'preview_lookup_limit': 5,
  };
}

void main() {
  late AppDatabase db;

  setUp(() {
    db = createTestDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  group('parseTrackDuration', () {
    test('reads minutes and hours', () {
      expect(parseTrackDuration('4:13'), 253);
      expect(parseTrackDuration('0:59'), 59);
      expect(parseTrackDuration('1:02:03'), 3723);
      expect(parseTrackDuration(' 12:00 '), 720);
    });

    test('returns null for missing or unreadable values', () {
      for (final value in [null, '', '4', '4:75', 'a:10', '1:2:3:4', 42]) {
        expect(parseTrackDuration(value), isNull, reason: '$value');
      }
    });
  });

  group('ReleaseMetadata.fromJson', () {
    test('parses the backend response', () {
      final release = ReleaseMetadata.fromJson(releaseJson());

      expect(release.releaseId, '31621720');
      expect(release.label, 'Columbia');
      expect(release.catalogNumber, '88883716861');
      expect(release.genres, ['Electronic', 'Funk / Soul']);
      expect(release.styles, ['Disco', 'Synth-pop']);
      expect(release.rating, 4.42);
      expect(release.previewStatus, 'partial');
      expect(release.tracks.map((t) => t.positionLabel), ['A1', 'A2', 'D3']);
      expect(release.tracks.map((t) => t.durationSeconds), [274, null, 381]);
      expect(release.tracks.first.previewUrl, isNotNull);
    });

    test('accepts missing optional fields', () {
      final release = ReleaseMetadata.fromJson({
        'discogs_id': 1,
        'artist': 'Artist',
        'title': 'Title',
        'year': null,
        'label': '  ',
        'genres': null,
        'rating': 4,
      });

      expect(release.year, isNull);
      expect(release.label, isNull);
      expect(release.genres, isEmpty);
      expect(release.rating, 4.0);
      expect(release.tracks, isEmpty);
    });

    test('rejects a response without id, artist or title', () {
      expect(
        () => ReleaseMetadata.fromJson({'artist': 'A', 'title': 'T'}),
        throwsFormatException,
      );
      expect(
        () => ReleaseMetadata.fromJson({'discogs_id': '1', 'artist': 'A'}),
        throwsFormatException,
      );
    });
  });

  group('storing extended metadata', () {
    test('every new field is stored and read back', () async {
      final fetchedAt = DateTime(2026, 10, 20, 12);
      final albumId = await db.albumDao.saveRelease(
        ReleaseMetadata.fromJson(releaseJson()),
        fetchedAt: fetchedAt,
      );

      final stored = await db.albumDao.getReleaseWithTracks('31621720');

      expect(stored, isNotNull);
      final album = stored!.album;
      expect(album.id, albumId);
      expect(album.coverUrl, 'https://i.discogs.com/ram.jpg');
      expect(album.label, 'Columbia');
      expect(album.catalogNumber, '88883716861');
      expect(album.genres, ['Electronic', 'Funk / Soul']);
      expect(album.styles, ['Disco', 'Synth-pop']);
      expect(album.rating, 4.42);
      expect(album.previewStatus, 'partial');
      expect(album.metadataSource, 'discogs');
      expect(album.fetchedAt, fetchedAt);

      expect(stored.tracks.map((t) => t.position), [1, 2, 3]);
      expect(stored.tracks.map((t) => t.positionLabel), ['A1', 'A2', 'D3']);
      expect(stored.tracks.map((t) => t.durationSeconds), [274, null, 381]);
      expect(stored.tracks.first.previewSource, 'itunes');
      expect(stored.tracks.last.previewSource, isNull);
    });

    test('albums saved without the new fields get empty defaults', () async {
      final albumId = await db.albumDao.saveAlbumWithTracks(
        album: AlbumsCompanion.insert(artist: 'Someone', title: 'Manual'),
        tracklist: [
          TracksCompanion(position: const Value(1), title: const Value('One')),
        ],
      );

      final stored = await db.albumDao.getAlbumWithTracks(albumId);

      expect(stored!.album.genres, isEmpty);
      expect(stored.album.styles, isEmpty);
      expect(stored.album.label, isNull);
      expect(stored.album.rating, isNull);
      expect(stored.tracks.single.positionLabel, isNull);
      expect(stored.tracks.single.durationSeconds, isNull);
    });

    test('refreshing a release keeps the downloaded cover', () async {
      final firstId = await db.albumDao.saveRelease(
        ReleaseMetadata.fromJson(releaseJson()),
        fetchedAt: DateTime(2026, 10, 1),
      );
      await (db.update(db.albums)..where((a) => a.id.equals(firstId))).write(
        const AlbumsCompanion(coverPath: Value('covers/31621720.jpg')),
      );

      final json = releaseJson(title: 'Random Access Memories (Remaster)');
      (json['tracks']! as List).removeLast();
      final secondId = await db.albumDao.saveRelease(
        ReleaseMetadata.fromJson(json),
        fetchedAt: DateTime(2026, 10, 20),
      );

      final stored = await db.albumDao.getAlbumWithTracks(firstId);
      expect(secondId, firstId);
      expect(stored!.album.title, 'Random Access Memories (Remaster)');
      expect(stored.album.coverPath, 'covers/31621720.jpg');
      expect(stored.tracks, hasLength(2));
    });

    test('unknown release ids return null', () async {
      expect(await db.albumDao.getReleaseWithTracks('404'), isNull);
    });
  });

  group('ReleaseRepository cache', () {
    late DateTime now;
    late int fetches;
    late Object? failure;

    ReleaseRepository repository() {
      return ReleaseRepository(db, (releaseId) async {
        fetches++;
        if (failure != null) {
          throw failure!;
        }
        return releaseJson(id: int.parse(releaseId));
      }, clock: () => now);
    }

    setUp(() {
      now = DateTime(2026, 10, 20, 12);
      fetches = 0;
      failure = null;
    });

    test('fetches and stores a release that is not cached', () async {
      final result = await repository().load('31621720');

      expect(fetches, 1);
      expect(result.fromCache, isFalse);
      expect(result.isStale, isFalse);
      expect(result.release.album.label, 'Columbia');
      expect(await db.albumDao.allAlbums(), hasLength(1));
    });

    test('a fresh release is read from the cache without a request', () async {
      final repo = repository();
      await repo.load('31621720');
      now = now.add(const Duration(days: 6));

      final result = await repo.load('31621720');

      expect(fetches, 1);
      expect(result.fromCache, isTrue);
      expect(result.release.tracks, hasLength(3));
    });

    test('an old release is fetched again', () async {
      final repo = repository();
      await repo.load('31621720');
      now = now.add(const Duration(days: 8));

      final result = await repo.load('31621720');

      expect(fetches, 2);
      expect(result.fromCache, isFalse);
      expect(result.release.album.fetchedAt, now);
    });

    test('forceRefresh always fetches', () async {
      final repo = repository();
      await repo.load('31621720');

      await repo.load('31621720', forceRefresh: true);

      expect(fetches, 2);
    });

    test('an old copy is returned when the backend is unavailable', () async {
      final repo = repository();
      await repo.load('31621720');
      now = now.add(const Duration(days: 30));
      failure = Exception('backend unavailable');

      final result = await repo.load('31621720');

      expect(result.fromCache, isTrue);
      expect(result.isStale, isTrue);
      expect(result.release.album.title, 'Random Access Memories');
    });

    test('the error is rethrown when nothing is cached', () async {
      failure = Exception('backend unavailable');

      await expectLater(repository().load('31621720'), throwsException);
    });

    test('seed or manual albums are replaced by Discogs metadata', () async {
      await db.albumDao.saveAlbumWithTracks(
        album: AlbumsCompanion.insert(
          releaseId: const Value('31621720'),
          artist: 'Daft Punk',
          title: 'RAM',
          metadataSource: const Value('seed'),
        ),
        tracklist: const [],
      );

      final result = await repository().load('31621720');

      expect(fetches, 1);
      expect(result.release.album.title, 'Random Access Memories');
      expect(await db.albumDao.allAlbums(), hasLength(1));
    });
  });

  group('mapping to the Album Details view model', () {
    test('stored metadata becomes the screen model', () async {
      await db.albumDao.saveRelease(
        ReleaseMetadata.fromJson(releaseJson()),
        fetchedAt: DateTime(2026, 10, 20),
      );
      final stored = await db.albumDao.getReleaseWithTracks('31621720');

      final album = stored!.toViewModel();

      expect(album.id, '31621720');
      expect(album.artistYear, 'Daft Punk · 2013');
      expect(album.label, 'Columbia');
      expect(album.catalogNumber, '88883716861');
      expect(album.genres, ['Electronic', 'Funk / Soul', 'Disco', 'Synth-pop']);
      expect(album.rating, 4.42);
      expect(album.format, model.MediaFormat.vinyl);
      expect(album.tracks.map((t) => t.position), ['A1', 'A2', 'D3']);
      expect(
        album.tracks.first.duration,
        const Duration(minutes: 4, seconds: 34),
      );
      expect(album.tracks[1].duration, Duration.zero);
      expect(album.tracks.map((t) => t.hasPreview), [true, false, false]);
      expect(album.previewsAvailable, isTrue);
      expect(album.isPartial, isFalse);
      expect(stored.toViewModel(isPartial: true).isPartial, isTrue);
    });

    test('Discogs format strings', () {
      expect(shortFormatOf('Vinyl, LP, Album'), 'Vinyl LP');
      expect(shortFormatOf(null), 'Vinyl');
      expect(mediaFormatOf('CD, Album'), model.MediaFormat.cd);
      expect(mediaFormatOf('Cassette, Album'), model.MediaFormat.tape);
      expect(mediaFormatOf(null), model.MediaFormat.vinyl);
    });
  });

  test('a version 1 database is migrated without losing data', () async {
    final legacy = AppDatabase.withExecutor(
      NativeDatabase.memory(
        setup: (raw) {
          // Albums and tracks exactly as schema version 1 (S1-06) created them.
          raw.execute('''
            CREATE TABLE albums (
              id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
              release_id TEXT NULL UNIQUE,
              artist TEXT NOT NULL,
              title TEXT NOT NULL,
              year INTEGER NULL,
              cover_path TEXT NULL,
              discogs_format TEXT NULL,
              metadata_source TEXT NOT NULL DEFAULT 'manual',
              fetched_at INTEGER NOT NULL
            );
          ''');
          raw.execute('''
            CREATE TABLE tracks (
              id INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT,
              album_id INTEGER NOT NULL REFERENCES albums (id) ON DELETE CASCADE,
              position INTEGER NOT NULL,
              title TEXT NOT NULL,
              popularity_rank INTEGER NULL,
              preview_url TEXT NULL,
              preview_source TEXT NULL,
              UNIQUE (album_id, position)
            );
          ''');
          raw.execute(
            "INSERT INTO albums (release_id, artist, title, year, fetched_at) "
            "VALUES ('7964182', 'The Beatles', 'Abbey Road', 1969, 1760000000);",
          );
          raw.execute(
            "INSERT INTO tracks (album_id, position, title) "
            "VALUES (1, 1, 'Come Together');",
          );
          raw.execute('PRAGMA user_version = 1;');
        },
      ),
    );
    addTearDown(legacy.close);

    final stored = await legacy.albumDao.getReleaseWithTracks('7964182');
    final version = await legacy
        .customSelect('PRAGMA user_version')
        .getSingle();

    expect(version.data.values.single, 2);
    expect(stored!.album.title, 'Abbey Road');
    expect(stored.album.year, 1969);
    expect(stored.album.genres, isEmpty);
    expect(stored.album.label, isNull);
    expect(stored.tracks.single.title, 'Come Together');
    expect(stored.tracks.single.positionLabel, isNull);

    // The new columns are writable after the upgrade.
    await legacy.albumDao.saveRelease(
      ReleaseMetadata.fromJson({
        'discogs_id': 7964182,
        'artist': 'The Beatles',
        'title': 'Abbey Road',
        'label': 'Apple Records',
        'genres': ['Rock'],
        'tracks': [
          {'position': 'A1', 'title': 'Come Together', 'duration': '4:20'},
        ],
      }),
      fetchedAt: DateTime(2026, 10, 20),
    );
    final updated = await legacy.albumDao.getReleaseWithTracks('7964182');
    expect(updated!.album.label, 'Apple Records');
    expect(updated.album.genres, ['Rock']);
    expect(updated.tracks.single.durationSeconds, 260);
  });
}
