import 'package:flutter_test/flutter_test.dart';
import 'package:jamscan/data/release_repository.dart';
import 'package:jamscan/services/catalog_service.dart';
import 'package:jamscan/services/release_api.dart';
import 'package:jamscan/services/release_details_service.dart';

import 'test_database.dart';

/// Discogs id of the release in [kindOfBlueJson].
const kindOfBlueId = '1544165';

/// `GET /releases/1544165` as the S2-04 backend returns it.
Map<String, Object?> kindOfBlueJson() {
  return {
    'discogs_id': 1544165,
    'artist': 'Miles Davis',
    'title': 'Kind Of Blue',
    'year': 1959,
    'cover_url': 'https://i.discogs.com/kind-of-blue.jpg',
    'label': 'Columbia',
    'catalog_number': 'CL 1355',
    'genres': ['Jazz'],
    'styles': ['Modal'],
    'rating': 4.71,
    'tracks': [
      {
        'position': 'A1',
        'title': 'So What',
        'duration': '9:22',
        'preview_url': 'https://audio.itunes.example/so-what.m4a',
        'track_view_url': null,
      },
      {
        'position': 'A2',
        'title': 'Freddie Freeloader',
        'duration': '9:46',
        'preview_url': null,
        'track_view_url': null,
      },
    ],
    'preview_status': 'available',
    'previews_checked': 2,
    'previews_available': 1,
    'preview_lookup_limit': 5,
  };
}

/// Search hit for [kindOfBlueJson].
const kindOfBlueHit = ReleaseSearchResult(
  releaseId: kindOfBlueId,
  artist: 'Miles Davis',
  title: 'Kind Of Blue',
  year: 1959,
  format: 'Vinyl, LP, Album, Mono',
  coverUrl: 'https://i.discogs.com/kind-of-blue-thumb.jpg',
);

/// In-memory stand-in for the backend's release endpoints.
class FakeReleaseApi implements ReleaseApi {
  FakeReleaseApi({
    Map<String, Map<String, Object?>>? releases,
    this.hits = const [kindOfBlueHit],
  }) : releases = releases ?? {kindOfBlueId: kindOfBlueJson()};

  final Map<String, Map<String, Object?>> releases;
  List<ReleaseSearchResult> hits;

  /// When true every request fails as if the backend were down.
  bool failing = false;
  final List<String> releaseRequests = [];
  final List<String> searchRequests = [];

  @override
  Future<Map<String, Object?>> release(String releaseId) async {
    releaseRequests.add(releaseId);
    if (failing) throw const ReleaseApiException('offline');
    final json = releases[releaseId];
    if (json == null) {
      throw const ReleaseApiException('HTTP 404', statusCode: 404);
    }
    return json;
  }

  @override
  Future<List<ReleaseSearchResult>> search(String query) async {
    searchRequests.add(query);
    if (failing) throw const ReleaseApiException('offline');
    final words = query.toLowerCase().split(' ');
    return [
      for (final hit in hits)
        if (words.every('${hit.artist} ${hit.title}'.toLowerCase().contains))
          hit,
    ];
  }
}

/// The real S2-07 services over [api], with an in-memory cache database
/// that is closed when the test ends.
({CatalogService catalog, ReleaseDetailsService details}) realServices(
  FakeReleaseApi api,
) {
  final db = createTestDatabase();
  addTearDown(db.close);
  return (
    catalog: HttpCatalogService(api),
    details: RepositoryReleaseDetails(ReleaseRepository(db, api.release)),
  );
}
