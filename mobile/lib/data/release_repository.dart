import 'local/app_database.dart';
import 'local/daos/album_dao.dart';
import 'release_metadata.dart';

/// Fetches the JSON body of `GET /releases/{release_id}` from the backend.
///
/// Injected so the HTTP client can be added by the integration story (S2-07)
/// and replaced by a fake in tests.
typedef ReleaseFetcher = Future<Map<String, Object?>> Function(
  String releaseId,
);

/// A release read through [ReleaseRepository], with where it came from.
class CachedRelease {
  const CachedRelease({
    required this.release,
    required this.fromCache,
    required this.isStale,
  });

  final AlbumWithTracks release;

  /// True when the data was read from the local database without a request.
  final bool fromCache;

  /// True when the cached copy is older than the freshness limit and the
  /// backend could not be reached. The UI shows it as partial metadata.
  final bool isStale;
}

/// Album metadata with a local cache in front of the backend.
///
/// - A release fetched within [maxAge] is read from the database only.
/// - Otherwise it is fetched, stored, and read back.
/// - If the fetch fails and an older copy exists, that copy is returned with
///   [CachedRelease.isStale] set, so the app still works offline.
/// - If the fetch fails and nothing is cached, the error is rethrown.
class ReleaseRepository {
  ReleaseRepository(
    this._db,
    this._fetch, {
    this.maxAge = defaultMaxAge,
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  /// Discogs metadata of a pressing rarely changes; previews may, so a week
  /// keeps preview links reasonably current without refetching every scan.
  static const Duration defaultMaxAge = Duration(days: 7);

  final AppDatabase _db;
  final ReleaseFetcher _fetch;
  final Duration maxAge;
  final DateTime Function() _clock;

  Future<CachedRelease> load(
    String releaseId, {
    bool forceRefresh = false,
  }) async {
    final cached = await _db.albumDao.getReleaseWithTracks(releaseId);
    if (!forceRefresh && cached != null && isFresh(cached.album)) {
      return CachedRelease(release: cached, fromCache: true, isStale: false);
    }

    final ReleaseMetadata metadata;
    try {
      metadata = ReleaseMetadata.fromJson(await _fetch(releaseId));
    } catch (_) {
      if (cached != null) {
        return CachedRelease(release: cached, fromCache: true, isStale: true);
      }
      rethrow;
    }

    final albumId = await _db.albumDao.saveRelease(
      metadata,
      fetchedAt: _clock(),
    );
    final stored = await _db.albumDao.getAlbumWithTracks(albumId);
    return CachedRelease(release: stored!, fromCache: false, isStale: false);
  }

  /// Whether [album] came from Discogs within [maxAge].
  ///
  /// Albums from other sources (seed data, manual entries) are never fresh,
  /// so they are replaced by Discogs metadata when it is available.
  bool isFresh(Album album) {
    return album.metadataSource == 'discogs' &&
        _clock().difference(album.fetchedAt) < maxAge;
  }
}
