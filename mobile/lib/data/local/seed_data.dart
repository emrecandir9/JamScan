import 'package:drift/drift.dart';

import 'app_database.dart';
import 'tables.dart';

/// Sample album together with its tracklist, used for seeding.
class SeedAlbum {
  const SeedAlbum({required this.album, required this.tracks});

  final AlbumsCompanion album;
  final List<TracksCompanion> tracks;
}

/// Builds a track companion without an album id; the DAO fills it in.
TracksCompanion _track(
  int position,
  String title, {
  int? popularityRank,
  String? previewUrl,
}) {
  return TracksCompanion(
    position: Value(position),
    title: Value(title),
    popularityRank: Value.absentIfNull(popularityRank),
    previewUrl: Value.absentIfNull(previewUrl),
    previewSource: previewUrl == null
        ? const Value.absent()
        : const Value('spotify'),
  );
}

/// Five albums with tracklists for local development and tests.
///
/// The metadata is illustrative sample data, not a Discogs export.
List<SeedAlbum> seedAlbums() {
  return [
    SeedAlbum(
      album: AlbumsCompanion.insert(
        releaseId: const Value('seed-1'),
        artist: 'Fleetwood Mac',
        title: 'Rumours',
        year: const Value(1977),
        coverPath: const Value('covers/seed-1.jpg'),
        discogsFormat: const Value('Vinyl, LP, Album'),
        metadataSource: const Value('seed'),
      ),
      tracks: [
        _track(1, 'Second Hand News', popularityRank: 6),
        _track(
          2,
          'Dreams',
          popularityRank: 1,
          previewUrl: 'https://example.invalid/preview/dreams',
        ),
        _track(3, 'Never Going Back Again', popularityRank: 5),
        _track(4, "Don't Stop", popularityRank: 2),
        _track(5, 'Go Your Own Way', popularityRank: 3),
        _track(6, 'The Chain', popularityRank: 4),
      ],
    ),
    SeedAlbum(
      album: AlbumsCompanion.insert(
        releaseId: const Value('seed-2'),
        artist: 'Daft Punk',
        title: 'Discovery',
        year: const Value(2001),
        coverPath: const Value('covers/seed-2.jpg'),
        discogsFormat: const Value('Vinyl, 2xLP, Album'),
        metadataSource: const Value('seed'),
      ),
      tracks: [
        _track(
          1,
          'One More Time',
          popularityRank: 1,
          previewUrl: 'https://example.invalid/preview/one-more-time',
        ),
        _track(2, 'Aerodynamic', popularityRank: 3),
        _track(3, 'Digital Love', popularityRank: 2),
        _track(4, 'Harder, Better, Faster, Stronger', popularityRank: 1),
        _track(5, 'Something About Us', popularityRank: 4),
      ],
    ),
    SeedAlbum(
      album: AlbumsCompanion.insert(
        releaseId: const Value('seed-3'),
        artist: 'Miles Davis',
        title: 'Kind of Blue',
        year: const Value(1959),
        coverPath: const Value('covers/seed-3.jpg'),
        discogsFormat: const Value('Vinyl, LP, Album, Reissue'),
        metadataSource: const Value('seed'),
      ),
      tracks: [
        _track(1, 'So What', popularityRank: 1),
        _track(2, 'Freddie Freeloader', popularityRank: 3),
        _track(3, 'Blue in Green', popularityRank: 2),
        _track(4, 'All Blues', popularityRank: 4),
        _track(5, 'Flamenco Sketches', popularityRank: 5),
      ],
    ),
    SeedAlbum(
      album: AlbumsCompanion.insert(
        releaseId: const Value('seed-4'),
        artist: 'Okean Elzy',
        title: 'Model',
        year: const Value(2001),
        coverPath: const Value('covers/seed-4.jpg'),
        discogsFormat: const Value('CD, Album'),
        metadataSource: const Value('seed'),
      ),
      tracks: [
        _track(1, 'Vidpusty', popularityRank: 2),
        _track(2, 'Kavachai', popularityRank: 3),
        _track(3, 'Tam, de nas nema', popularityRank: 1),
        _track(4, 'Susidka', popularityRank: 4),
      ],
    ),
    SeedAlbum(
      album: AlbumsCompanion.insert(
        // No external identifier: a manually added record.
        artist: 'Unknown Artist',
        title: 'Live at the Garage',
        year: const Value(1994),
        discogsFormat: const Value('Cassette, Album'),
        metadataSource: const Value('manual'),
      ),
      tracks: [
        _track(1, 'Opening'),
        _track(2, 'Second Set'),
        _track(3, 'Encore'),
      ],
    ),
  ];
}

/// Identifiers created by [insertSeedData].
class SeedResult {
  const SeedResult({
    required this.userId,
    required this.collectionId,
    required this.wishlistId,
    required this.albumIds,
  });

  final int userId;
  final int collectionId;
  final int wishlistId;
  final List<int> albumIds;
}

/// Inserts a sample user, a collection, a wishlist, and five albums.
Future<SeedResult> insertSeedData(AppDatabase db) {
  return db.transaction(() async {
    final userId = await db
        .into(db.users)
        .insert(
          UsersCompanion.insert(
            displayName: 'Sample Collector',
            email: 'collector@example.invalid',
            passwordHash: 'seed-not-a-real-hash',
          ),
        );

    final collectionId = await db.listDao.createList(
      userId: userId,
      name: 'My collection',
      type: ListType.collection,
    );
    final wishlistId = await db.listDao.createList(
      userId: userId,
      name: 'Wishlist',
      type: ListType.wishlist,
    );

    final albumIds = <int>[];
    for (final seed in seedAlbums()) {
      albumIds.add(
        await db.albumDao.saveAlbumWithTracks(
          album: seed.album,
          tracklist: seed.tracks,
        ),
      );
    }

    await db.listDao.addAlbumToList(
      listId: collectionId,
      albumId: albumIds[0],
      ownedFormat: 'Vinyl',
      condition: 'Very Good Plus',
    );
    await db.listDao.addAlbumToList(
      listId: collectionId,
      albumId: albumIds[2],
      ownedFormat: 'Vinyl',
      condition: 'Near Mint',
    );
    await db.listDao.addAlbumToList(
      listId: wishlistId,
      albumId: albumIds[1],
      priority: 1,
    );

    return SeedResult(
      userId: userId,
      collectionId: collectionId,
      wishlistId: wishlistId,
      albumIds: albumIds,
    );
  });
}
