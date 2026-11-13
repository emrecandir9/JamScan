import '../data/local/album_mapping.dart';
import '../mock/mock_catalog.dart';
import '../models/album.dart';
import 'release_api.dart';

/// Thrown when the release catalogue (Discogs) cannot be reached.
class CatalogUnavailableException implements Exception {
  const CatalogUnavailableException();
}

/// Searches releases by text, for manual search.
abstract class CatalogService {
  /// Releases matching [query]. Throws [CatalogUnavailableException] when the
  /// catalogue does not respond.
  Future<List<Album>> search(String query);
}

/// Searches Discogs through the backend (`GET /releases/search`).
///
/// Hits carry only artist, title, year, format and cover, so they are
/// returned as partial albums; the full details are loaded when one is
/// selected (`ReleaseDetailsService.complete`).
class HttpCatalogService implements CatalogService {
  const HttpCatalogService(this.api);

  final ReleaseApi api;

  @override
  Future<List<Album>> search(String query) async {
    final List<ReleaseSearchResult> results;
    try {
      results = await api.search(query);
    } on ReleaseApiException {
      throw const CatalogUnavailableException();
    }
    return [for (final result in results) albumFromSearchResult(result)];
  }
}

/// A partial album for one search hit.
Album albumFromSearchResult(ReleaseSearchResult result) {
  return Album(
    id: result.releaseId,
    title: result.title,
    artist: result.artist,
    year: result.year ?? 0,
    format: mediaFormatOf(result.format),
    formatDescription: shortFormatOf(result.format),
    pressingFormat: result.format ?? '',
    label: '',
    catalogNumber: '',
    country: '',
    genres: const [],
    tracks: const [],
    isPartial: true,
    previewsAvailable: false,
    coverUrl: result.coverUrl,
  );
}

/// Searches [MockCatalog]; used when no backend is configured.
class MockCatalogService implements CatalogService {
  MockCatalogService({
    this.latency = const Duration(milliseconds: 300),
    this.failing = false,
  });

  final Duration latency;

  /// When true every search throws, to exercise the error state.
  bool failing;

  @override
  Future<List<Album>> search(String query) async {
    await Future<void>.delayed(latency);
    if (failing) {
      throw const CatalogUnavailableException();
    }

    final words = query
        .toLowerCase()
        .split(RegExp(r'\s+'))
        .where((word) => word.isNotEmpty)
        .toList();
    if (words.isEmpty) {
      return const [];
    }

    return MockCatalog.all.where((album) {
      final haystack = '${album.title} ${album.artist} ${album.year}'
          .toLowerCase();
      return words.every(haystack.contains);
    }).toList();
  }
}
