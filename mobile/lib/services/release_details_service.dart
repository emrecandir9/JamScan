import '../mock/mock_catalog.dart';
import '../models/album.dart';
import 'recognition_api.dart';

/// Turns a recognised release into the album shown on Album Details.
///
/// The Discogs metadata endpoint (S2-04) will implement this with full
/// release data. Until then [BasicReleaseDetails] shows what recognition
/// already knows.
abstract interface class ReleaseDetailsService {
  Future<Album> details(ApiCandidate release);
}

/// Uses the sample catalogue when it has the release, and otherwise the
/// artist, title and year returned by recognition, marked as partial.
class BasicReleaseDetails implements ReleaseDetailsService {
  const BasicReleaseDetails();

  @override
  Future<Album> details(ApiCandidate release) async {
    for (final album in MockCatalog.all) {
      if (album.id == release.releaseId) return album;
    }
    return albumFromCandidate(release);
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
