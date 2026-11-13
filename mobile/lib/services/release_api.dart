import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

/// The release endpoints of the backend could not be reached or failed.
class ReleaseApiException implements Exception {
  const ReleaseApiException(this.reason, {this.statusCode});

  final String reason;

  /// HTTP status of the failed response, or null for network failures.
  final int? statusCode;

  @override
  String toString() => 'ReleaseApiException: $reason';
}

/// One hit of `GET /releases/search`.
class ReleaseSearchResult {
  const ReleaseSearchResult({
    required this.releaseId,
    required this.artist,
    required this.title,
    this.year,
    this.format,
    this.coverUrl,
  });

  /// Discogs release id.
  final String releaseId;
  final String artist;
  final String title;
  final int? year;

  /// Discogs format, for example `Vinyl, LP, Album`.
  final String? format;
  final String? coverUrl;
}

/// The backend's Discogs and iTunes endpoints (S2-04).
abstract interface class ReleaseApi {
  /// JSON body of `GET /releases/{releaseId}`: Discogs metadata with
  /// iTunes preview links. Parsed by `ReleaseMetadata.fromJson`.
  Future<Map<String, Object?>> release(String releaseId);

  /// `GET /releases/search?query=...`, best match first.
  Future<List<ReleaseSearchResult>> search(String query);
}

/// [ReleaseApi] over HTTP, using the same base URL as recognition
/// (`--dart-define=JAMSCAN_API_URL=...`).
class HttpReleaseApi implements ReleaseApi {
  HttpReleaseApi(
    this.baseUrl, {
    http.Client? client,
    // The backend looks up iTunes previews track by track before it
    // answers, so release details are slower than recognition.
    this.timeout = const Duration(seconds: 30),
  }) : _client = client ?? http.Client();

  final Uri baseUrl;
  final http.Client _client;
  final Duration timeout;

  @override
  Future<Map<String, Object?>> release(String releaseId) async {
    final body = await _get(
      baseUrl.resolve('releases/${Uri.encodeComponent(releaseId)}'),
    );
    if (body is! Map<String, Object?>) {
      throw const ReleaseApiException('bad response: expected an object');
    }
    return body;
  }

  @override
  Future<List<ReleaseSearchResult>> search(String query) async {
    final body = await _get(
      baseUrl
          .resolve('releases/search')
          .replace(queryParameters: {'query': query}),
    );
    try {
      return parseSearchResults(body);
    } on FormatException catch (error) {
      throw ReleaseApiException('bad response: ${error.message}');
    }
  }

  Future<Object?> _get(Uri url) async {
    final http.Response response;
    try {
      response = await _client.get(url).timeout(timeout);
    } on TimeoutException {
      throw const ReleaseApiException('timeout');
    } on http.ClientException catch (error) {
      throw ReleaseApiException(error.message);
    }
    if (response.statusCode != 200) {
      throw ReleaseApiException(
        'HTTP ${response.statusCode}',
        statusCode: response.statusCode,
      );
    }
    try {
      return jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException catch (error) {
      throw ReleaseApiException('bad response: ${error.message}');
    }
  }
}

/// Parses the JSON body of `GET /releases/search`.
///
/// Discogs titles search hits as `Artist - Title`; the artist is split off
/// at the first ` - `.
List<ReleaseSearchResult> parseSearchResults(Object? json) {
  if (json is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object.');
  }
  final results = json['results'];
  if (results is! List) throw const FormatException('Missing results.');
  return [
    for (final item in results.whereType<Map<String, Object?>>())
      if (item['discogs_id'] is int && item['title'] is String)
        _searchResult(item),
  ];
}

ReleaseSearchResult _searchResult(Map<String, Object?> item) {
  final fullTitle = (item['title']! as String).trim();
  final split = fullTitle.indexOf(' - ');
  final year = item['year'];
  final format = item['format'];
  final cover = item['cover_url'];
  return ReleaseSearchResult(
    releaseId: '${item['discogs_id']}',
    artist: split < 0 ? '' : fullTitle.substring(0, split).trim(),
    title: split < 0 ? fullTitle : fullTitle.substring(split + 3).trim(),
    year: year is int && year > 0 ? year : null,
    format: format is String && format.trim().isNotEmpty ? format : null,
    coverUrl: cover is String && cover.isNotEmpty ? cover : null,
  );
}
