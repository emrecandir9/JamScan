import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../mock/mock_catalog.dart';

/// The backend's verdict on one cover image (`POST /recognitions`, S2-03).
enum ApiDecision { match, needsReview, noMatch, poorQuality }

class ApiCandidate {
  const ApiCandidate({
    required this.releaseId,
    required this.artist,
    required this.title,
    required this.score,
    this.year,
  });

  /// Discogs release id.
  final String releaseId;
  final String artist;
  final String title;
  final int? year;

  /// Cosine similarity, 0-1.
  final double score;
}

class ApiRecognition {
  const ApiRecognition(this.decision, this.candidates);

  final ApiDecision decision;

  /// Best first. Empty for [ApiDecision.noMatch] and
  /// [ApiDecision.poorQuality].
  final List<ApiCandidate> candidates;
}

/// The recognition service could not be reached or failed.
class RecognitionUnavailableException implements Exception {
  const RecognitionUnavailableException(this.reason);

  final String reason;

  @override
  String toString() => 'RecognitionUnavailableException: $reason';
}

/// Sends cover crops to the recognition backend.
abstract interface class RecognitionApi {
  Future<ApiRecognition> recognize(
    Uint8List jpeg, {
    bool skipQualityCheck = false,
  });
}

/// [RecognitionApi] over HTTP. The base URL comes from
/// `--dart-define=JAMSCAN_API_URL=...`; on the Android emulator the host
/// machine is `http://10.0.2.2:8000`.
class HttpRecognitionApi implements RecognitionApi {
  HttpRecognitionApi(
    this.baseUrl, {
    http.Client? client,
    this.timeout = const Duration(seconds: 15),
  }) : _client = client ?? http.Client();

  final Uri baseUrl;
  final http.Client _client;
  final Duration timeout;

  @override
  Future<ApiRecognition> recognize(
    Uint8List jpeg, {
    bool skipQualityCheck = false,
  }) async {
    final request =
        http.MultipartRequest('POST', baseUrl.resolve('recognitions'))
          ..fields['skip_quality_check'] = '$skipQualityCheck'
          ..files.add(
            http.MultipartFile.fromBytes('image', jpeg, filename: 'cover.jpg'),
          );
    final http.Response response;
    try {
      response = await http.Response.fromStream(
        await _client.send(request).timeout(timeout),
      ).timeout(timeout);
    } on TimeoutException {
      throw const RecognitionUnavailableException('timeout');
    } on http.ClientException catch (error) {
      throw RecognitionUnavailableException(error.message);
    }
    if (response.statusCode != 200) {
      throw RecognitionUnavailableException('HTTP ${response.statusCode}');
    }
    try {
      return parseRecognition(jsonDecode(response.body));
    } on FormatException catch (error) {
      throw RecognitionUnavailableException('bad response: ${error.message}');
    }
  }
}

/// Parses the JSON body of `POST /recognitions`.
ApiRecognition parseRecognition(Object? json) {
  if (json is! Map<String, Object?>) {
    throw const FormatException('Expected a JSON object.');
  }
  final decision = switch (json['decision']) {
    'match' => ApiDecision.match,
    'needs_review' => ApiDecision.needsReview,
    'no_match' => ApiDecision.noMatch,
    'poor_quality' => ApiDecision.poorQuality,
    final other => throw FormatException('Unknown decision: $other'),
  };
  final candidates = json['candidates'];
  if (candidates is! List) throw const FormatException('Missing candidates.');
  return ApiRecognition(decision, [
    for (final c in candidates.cast<Map<String, Object?>>())
      ApiCandidate(
        releaseId: '${c['release_id']}',
        artist: c['artist'] as String? ?? '',
        title: c['title'] as String? ?? '',
        year: (c['year'] as num?)?.toInt(),
        score: (c['score'] as num?)?.toDouble() ?? 0,
      ),
  ]);
}

/// Offline stand-in used when no backend URL is configured: answers with
/// albums from [MockCatalog] in turn, so the live flow can be demonstrated.
class MockRecognitionApi implements RecognitionApi {
  MockRecognitionApi({this.delay = const Duration(milliseconds: 900)});

  final Duration delay;
  int _calls = 0;

  @override
  Future<ApiRecognition> recognize(
    Uint8List jpeg, {
    bool skipQualityCheck = false,
  }) async {
    await Future<void>.delayed(delay);
    final album = MockCatalog.all[_calls++ % MockCatalog.all.length];
    return ApiRecognition(ApiDecision.match, [
      ApiCandidate(
        releaseId: album.id,
        artist: album.artist,
        title: album.title,
        year: album.year,
        score: 0.9,
      ),
    ]);
  }
}
