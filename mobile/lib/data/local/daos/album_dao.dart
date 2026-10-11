import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'album_dao.g.dart';

/// An album together with its ordered tracklist.
class AlbumWithTracks {
  const AlbumWithTracks({required this.album, required this.tracks});

  final Album album;
  final List<Track> tracks;
}

@DriftAccessor(tables: [Albums, Tracks])
class AlbumDao extends DatabaseAccessor<AppDatabase> with _$AlbumDaoMixin {
  AlbumDao(super.db);

  /// Saves an album and its tracklist in one transaction.
  ///
  /// When an album with the same [AlbumsCompanion.releaseId] already exists it
  /// is updated and its tracklist is replaced, so re-scanning a record does not
  /// create a second row. Returns the album id.
  Future<int> saveAlbumWithTracks({
    required AlbumsCompanion album,
    required List<TracksCompanion> tracklist,
  }) {
    return transaction(() async {
      final releaseId = album.releaseId;
      final hasReleaseId = releaseId.present && releaseId.value != null;

      Album? existing;
      if (hasReleaseId) {
        existing =
            await (select(albums)
                  ..where((a) => a.releaseId.equals(releaseId.value!)))
                .getSingleOrNull();
      }

      final int albumId;
      if (existing != null) {
        albumId = existing.id;
        await (update(albums)..where((a) => a.id.equals(albumId))).write(album);
        await (delete(tracks)..where((t) => t.albumId.equals(albumId))).go();
      } else {
        albumId = await into(albums).insert(album);
      }

      await batch((batch) {
        batch.insertAll(
          tracks,
          tracklist.map((track) => track.copyWith(albumId: Value(albumId))),
        );
      });

      return albumId;
    });
  }

  /// Reads one album with its tracklist ordered by track position.
  Future<AlbumWithTracks?> getAlbumWithTracks(int albumId) async {
    final album = await (select(
      albums,
    )..where((a) => a.id.equals(albumId))).getSingleOrNull();
    if (album == null) {
      return null;
    }

    final tracklist =
        await (select(tracks)
              ..where((t) => t.albumId.equals(albumId))
              ..orderBy([(t) => OrderingTerm.asc(t.position)]))
            .get();

    return AlbumWithTracks(album: album, tracks: tracklist);
  }

  /// Looks up a stored album by its external Discogs release id.
  Future<Album?> findByReleaseId(String releaseId) {
    return (select(
      albums,
    )..where((a) => a.releaseId.equals(releaseId))).getSingleOrNull();
  }

  /// All stored albums, newest metadata first.
  Future<List<Album>> allAlbums() {
    return (select(
      albums,
    )..orderBy([(a) => OrderingTerm.desc(a.fetchedAt)])).get();
  }
}
