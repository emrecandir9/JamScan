import 'dart:async';
import 'dart:typed_data';

import 'package:jamscan/services/recognition_api.dart';

/// A recognition backend whose answers the test releases one by one.
class FakeRecognitionApi implements RecognitionApi {
  final List<Completer<ApiRecognition>> pending = [];
  final List<Uint8List> received = [];
  final List<bool> skipFlags = [];

  int get calls => received.length;

  @override
  Future<ApiRecognition> recognize(
    Uint8List jpeg, {
    bool skipQualityCheck = false,
  }) {
    received.add(jpeg);
    skipFlags.add(skipQualityCheck);
    final completer = Completer<ApiRecognition>();
    pending.add(completer);
    return completer.future;
  }

  /// Answers the oldest unanswered request.
  void answer(ApiRecognition result) =>
      pending.firstWhere((c) => !c.isCompleted).complete(result);

  void fail([Object error = const RecognitionUnavailableException('down')]) =>
      pending.firstWhere((c) => !c.isCompleted).completeError(error);
}

ApiCandidate candidate(String id, {double score = 0.9}) => ApiCandidate(
  releaseId: id,
  artist: 'Artist $id',
  title: 'Album $id',
  year: 1977,
  score: score,
);

ApiRecognition matchOf(String id) =>
    ApiRecognition(ApiDecision.match, [candidate(id)]);

/// Distinct 64-bit hashes, far apart in Hamming distance.
int hashNumber(int n) => [
  0x0000000000000000,
  0x00000000FFFFFFFF,
  0xFFFFFFFF00000000,
  0x0F0F0F0F0F0F0F0F,
  0x3333333333333333,
  0x5555555555555555,
][n];

Uint8List bytes(int n) => Uint8List.fromList([n]);
