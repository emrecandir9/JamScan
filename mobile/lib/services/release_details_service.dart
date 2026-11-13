import '../data/local/album_mapping.dart';
import '../data/release_repository.dart';
import '../mock/mock_catalog.dart';
import '../models/album.dart';
import 'recognition_api.dart';

/// Turns a recognised or searched release into the album shown on Album
/// Details.
abstract interface class ReleaseDetailsService {
  /// Full details of a release returned by recognition. Throws when they
  /// cannot be loaded; callers fall back to [albumFromCandidate].
  Future<Album> details(ApiCandidate release);

  /// Full details for [album] when it is partial (a search hit or a
  /// recognition candidate). Returns [album] unchanged when it is already
  /// complete or the details cannot be loaded, so selecting it always works.
  Future<Album> complete(Album album);
}

/// Offline details: the sample catalogue when it has the release, and
/// otherwise the artist, title and year returned by recognition, marked as
/// partial. Used when no backend is configured.
class BasicReleaseDetails implements ReleaseDetailsService {
  const BasicReleaseDetails();

  @override
  Future<Album> details(ApiCandidate release) async {
    return _sample(release.releaseId) ?? albumFromCandidate(release);
  }

  @override
  Future<Album> complete(Album album) async {
    return album.isPartial ? _sample(album.id) ?? album : album;
  }

  static Album? _sample(String releaseId) {
    for (final album in MockCatalog.all) {
      if (album.id == releaseId) return album;
    }
    return null;
  }
}

/// Discogs metadata and iTunes previews from the backend, through the local
/// cache of [ReleaseRepository] (S2-05): a release fetched within the last
/// week opens without a request, and an older copy is shown (marked
/// partial) when the backend cannot be reached.
class RepositoryReleaseDetails implements ReleaseDetailsService {
  const RepositoryReleaseDetails(this.repository);

  final ReleaseRepository repository;

  @override
  Future<Album> details(ApiCandidate release) => _load(release.releaseId);

  @override
  Future<Album> complete(Album album) async {
    // Only Discogs ids can be looked up; sample albums keep their data.
    if (!album.isPartial || int.tryParse(album.id) == null) {
      return album;
    }
    try {
      return await _load(album.id);
    } on Exception {
      return album;
    }
  }

  Future<Album> _load(String releaseId) async {
    final result = await repository.load(releaseId);
    return result.release.toViewModel(isPartial: result.isStale);
  }
}

/// A minimal album from recognition data alone.
Album albumFromCandidate(ApiCandidate release) {
  return Album(
    id: release.releaseId,
    title: release.title,
    artist: release.artist,
    year: release.year ?? 0,
    format: MediaFormat.vinyl,
    formatDescription: 'Vinyl',
    pressingFormat: 'Vinyl',
    label: '',
    catalogNumber: '',
    country: '',
    genres: const [],
    tracks: const [],
    isPartial: true,
    previewsAvailable: false,
  );
}
