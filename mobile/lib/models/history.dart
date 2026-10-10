import 'album.dart';

/// How a history entry was created. Mirrors `HistoryKind` in the drift tables.
enum HistoryKind { scan, search }

class HistoryItem {
  const HistoryItem({
    required this.id,
    required this.kind,
    required this.createdAt,
    this.album,
    this.query,
    this.afterFailedScan = false,
  });

  final String id;
  final HistoryKind kind;
  final DateTime createdAt;

  /// The album that was found, if any.
  final Album? album;

  /// The search text, for searches.
  final String? query;

  /// True when the cover was not recognised and the user searched instead.
  final bool afterFailedScan;

  String get title {
    final album = this.album;
    if (album != null) {
      return album.title;
    }
    final query = this.query;
    return query == null ? 'Unknown album' : '"$query"';
  }

  /// `Scan`, `Search "kind of blue"` or `Not recognised, then searched`.
  String get description {
    if (afterFailedScan) {
      return 'Not recognised, then searched';
    }
    if (kind == HistoryKind.scan) {
      return 'Scan';
    }
    final query = this.query;
    return query == null ? 'Search' : 'Search "$query"';
  }
}
