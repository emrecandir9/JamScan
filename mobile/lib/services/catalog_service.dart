import '../mock/mock_catalog.dart';
import '../models/album.dart';

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

/// Searches [MockCatalog] until the Discogs client from S1-05 is wired in.
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
