import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:flutter_test/flutter_test.dart';
import 'package:jamscan/data/local/app_database.dart';
import 'package:jamscan/data/local/seed_data.dart';
import 'package:jamscan/data/local/tables.dart';
import 'package:sqlite3/common.dart';

import '../support/test_database.dart';

void main() {
  late AppDatabase db;

  setUp(() {
    db = createTestDatabase();
  });

  tearDown(() async {
    await db.close();
  });

  Future<int> insertUser() {
    return db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            displayName: 'Test User',
            email: 'test@example.invalid',
            passwordHash: 'not-a-real-hash',
          ),
        );
  }

  test('an album and its tracklist can be saved and read back', () async {
    final albumId = await db.albumDao.saveAlbumWithTracks(
      album: AlbumsCompanion.insert(
        releaseId: const Value('r-249504'),
        artist: 'Fleetwood Mac',
        title: 'Rumours',
        year: const Value(1977),
        coverPath: const Value('covers/r-249504.jpg'),
        discogsFormat: const Value('Vinyl, LP, Album'),
        metadataSource: const Value('discogs'),
      ),
      tracklist: [
        TracksCompanion(
          position: const Value(1),
          title: const Value('Second Hand News'),
        ),
        TracksCompanion(
          position: const Value(2),
          title: const Value('Dreams'),
          popularityRank: const Value(1),
          previewUrl: const Value('https://example.invalid/preview/dreams'),
          previewSource: const Value('spotify'),
        ),
      ],
    );

    final stored = await db.albumDao.getAlbumWithTracks(albumId);

    expect(stored, isNotNull);
    expect(stored!.album.releaseId, 'r-249504');
    expect(stored.album.artist, 'Fleetwood Mac');
    expect(stored.album.title, 'Rumours');
    expect(stored.album.year, 1977);
    expect(stored.album.coverPath, 'covers/r-249504.jpg');
    expect(stored.album.discogsFormat, 'Vinyl, LP, Album');
    expect(stored.album.metadataSource, 'discogs');
    expect(stored.tracks.map((t) => t.title), ['Second Hand News', 'Dreams']);
    expect(stored.tracks.last.previewUrl, isNotNull);
  });

  test(
    're-saving the same release updates it instead of duplicating',
    () async {
      final firstId = await db.albumDao.saveAlbumWithTracks(
        album: AlbumsCompanion.insert(
          releaseId: const Value('r-1'),
          artist: 'Daft Punk',
          title: 'Discovery',
        ),
        tracklist: [
          TracksCompanion(
            position: const Value(1),
            title: const Value('One More Time'),
          ),
        ],
      );

      final secondId = await db.albumDao.saveAlbumWithTracks(
        album: AlbumsCompanion.insert(
          releaseId: const Value('r-1'),
          artist: 'Daft Punk',
          title: 'Discovery',
          year: const Value(2001),
        ),
        tracklist: [
          TracksCompanion(
            position: const Value(1),
            title: const Value('One More Time'),
          ),
          TracksCompanion(
            position: const Value(2),
            title: const Value('Aerodynamic'),
          ),
        ],
      );

      expect(secondId, firstId);
      expect(await db.albumDao.allAlbums(), hasLength(1));

      final stored = await db.albumDao.getAlbumWithTracks(firstId);
      expect(stored!.album.year, 2001);
      expect(stored.tracks, hasLength(2));
    },
  );

  test('adding the same album to a list twice is rejected', () async {
    final userId = await insertUser();
    final listId = await db.listDao.createList(
      userId: userId,
      name: 'My collection',
      type: ListType.collection,
    );
    final albumId = await db.albumDao.saveAlbumWithTracks(
      album: AlbumsCompanion.insert(
        releaseId: const Value('r-2'),
        artist: 'Miles Davis',
        title: 'Kind of Blue',
      ),
      tracklist: const [],
    );

    await db.listDao.addAlbumToList(listId: listId, albumId: albumId);

    expect(
      () => db.listDao.addAlbumToList(listId: listId, albumId: albumId),
      throwsA(isA<SqliteException>()),
    );

    expect(
      await db.listDao.listContainsAlbum(listId: listId, albumId: albumId),
      isTrue,
    );
    expect(
      await db.listDao.addAlbumToListIfAbsent(listId: listId, albumId: albumId),
      isNull,
    );
    expect(await db.listDao.entriesForList(listId), hasLength(1));
  });

  test('deleting an album cascades to its tracks and list entries', () async {
    final userId = await insertUser();
    final listId = await db.listDao.createList(
      userId: userId,
      name: 'Wishlist',
      type: ListType.wishlist,
    );
    final albumId = await db.albumDao.saveAlbumWithTracks(
      album: AlbumsCompanion.insert(
        releaseId: const Value('r-3'),
        artist: 'Okean Elzy',
        title: 'Model',
      ),
      tracklist: [
        TracksCompanion(
          position: const Value(1),
          title: const Value('Vidpusty'),
        ),
        TracksCompanion(
          position: const Value(2),
          title: const Value('Kavachai'),
        ),
      ],
    );
    await db.listDao.addAlbumToList(listId: listId, albumId: albumId);

    await (db.delete(db.albums)..where((a) => a.id.equals(albumId))).go();

    expect(await db.albumDao.getAlbumWithTracks(albumId), isNull);
    expect(await db.select(db.tracks).get(), isEmpty);
    expect(await db.listDao.entriesForList(listId), isEmpty);
  });

  test('deleting a user cascades to lists and their entries', () async {
    final seed = await insertSeedData(db);

    expect(await db.select(db.lists).get(), hasLength(2));
    expect(await db.select(db.listEntries).get(), hasLength(3));

    await (db.delete(db.users)..where((u) => u.id.equals(seed.userId))).go();

    expect(await db.select(db.lists).get(), isEmpty);
    expect(await db.select(db.listEntries).get(), isEmpty);
    // Albums are shared metadata and are not removed with a user.
    expect(await db.albumDao.allAlbums(), hasLength(5));
  });

  test('seed data provides five albums with tracklists', () async {
    final seed = await insertSeedData(db);

    expect(seed.albumIds, hasLength(5));
    for (final albumId in seed.albumIds) {
      final stored = await db.albumDao.getAlbumWithTracks(albumId);
      expect(stored, isNotNull);
      expect(stored!.tracks, isNotEmpty);
    }

    final collection = await db.listDao.entriesForList(seed.collectionId);
    expect(collection, hasLength(2));
    expect(collection.first.album.artist, isNotEmpty);
  });
}
