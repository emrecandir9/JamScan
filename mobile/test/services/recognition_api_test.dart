import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:image/image.dart' as img;
import 'package:jamscan/services/queued_recognition_service.dart';
import 'package:jamscan/services/recognition_api.dart';
import 'package:jamscan/services/recognition_service.dart';
import 'package:jamscan/state/recognition_session.dart';
import 'package:jamscan/vision/frame_quality.dart';
import 'package:jamscan/vision/still_cover.dart';

import '../support/fake_recognition_api.dart';

const matchBody = {
  'decision': 'match',
  'candidates': [
    {
      'release_id': '12643712',
      'artist': 'Fleetwood Mac',
      'title': 'Rumours',
      'year': 1977,
      'score': 0.9,
    },
  ],
  'quality': {'sharpness': 72.0, 'brightness': 116.1},
  'model_id': 'dinov2-small/cls/v1',
  'timings_ms': {'preprocess': 5.8, 'embed': 18.6, 'search': 0.1},
};

void main() {
  group('HttpRecognitionApi', () {
    test('uploads the crop and parses a match', () async {
      late http.BaseRequest sent;
      late String body;
      final client = MockClient((request) async {
        sent = request;
        body = latin1.decode(request.bodyBytes);
        return http.Response(jsonEncode(matchBody), 200);
      });
      final api = HttpRecognitionApi(
        Uri.parse('http://10.0.2.2:8000/'),
        client: client,
      );

      final result = await api.recognize(
        Uint8List.fromList([0xFF, 0xD8, 0xFF]),
        skipQualityCheck: true,
      );

      expect(sent.method, 'POST');
      expect(sent.url.toString(), 'http://10.0.2.2:8000/recognitions');
      expect(body, contains('name="image"; filename="cover.jpg"'));
      expect(body, contains('name="skip_quality_check"'));
      expect(body, contains('true'));
      expect(result.decision, ApiDecision.match);
      expect(result.candidates.single.releaseId, '12643712');
      expect(result.candidates.single.year, 1977);
    });

    test('maps every decision', () {
      for (final (name, decision) in [
        ('match', ApiDecision.match),
        ('needs_review', ApiDecision.needsReview),
        ('no_match', ApiDecision.noMatch),
        ('poor_quality', ApiDecision.poorQuality),
      ]) {
        expect(
          parseRecognition({'decision': name, 'candidates': []}).decision,
          decision,
        );
      }
      expect(
        () => parseRecognition({'decision': 'maybe', 'candidates': []}),
        throwsFormatException,
      );
    });

    test('server errors, bad bodies and timeouts mean unavailable', () async {
      Future<void> expectUnavailable(MockClient client, {Duration? timeout}) {
        final api = HttpRecognitionApi(
          Uri.parse('http://backend/'),
          client: client,
          timeout: timeout ?? const Duration(seconds: 5),
        );
        return expectLater(
          api.recognize(Uint8List(1)),
          throwsA(isA<RecognitionUnavailableException>()),
        );
      }

      await expectUnavailable(
        MockClient((_) async => http.Response('{"detail":"no model"}', 503)),
      );
      await expectUnavailable(
        MockClient((_) async => http.Response('not json', 200)),
      );
      await expectUnavailable(
        MockClient((_) => throw http.ClientException('connection refused')),
      );
      await expectUnavailable(
        MockClient((_) => Completer<http.Response>().future),
        timeout: const Duration(milliseconds: 50),
      );
    });
  });

  group('QueuedRecognitionService', () {
    late Directory dir;
    late String photoPath;

    setUp(() {
      dir = Directory.systemTemp.createTempSync('jamscan_test');
      photoPath = '${dir.path}/photo.jpg';
      File(photoPath)
          .writeAsBytesSync(img.encodeJpg(img.Image(width: 32, height: 32)));
    });

    tearDown(() => dir.deleteSync(recursive: true));

    PreparedCover fakePrepared(Uint8List _) => PreparedCover(
      jpeg: Uint8List.fromList([1, 2, 3]),
      hash: 7,
      quality: const CoverQuality(
        sharpness: 100,
        brightness: 120,
        highlights: 200,
        glare: 0,
        size: 0.3,
        skew: 0,
        motion: 0,
      ),
      detected: true,
    );

    test('a photo becomes a prioritised job and a match', () async {
      final api = FakeRecognitionApi();
      final session = RecognitionSession(api: api);
      final service = QueuedRecognitionService(
        session,
        prepare: (bytes) async => fakePrepared(bytes),
      );
      final steps = <RecognitionStep>[];

      final outcome = service.identify(
        imagePath: photoPath,
        skipQualityCheck: true,
        onStep: steps.add,
      );
      await api.untilWaiting();
      expect(session.jobs.single.source, JobSource.manual);
      api.answer(matchOf('12643712'));
      final result = await outcome;

      expect(result.kind, RecognitionOutcomeKind.match);
      expect(result.candidates.single.album.id, '12643712');
      expect(api.received.single, [1, 2, 3]);
      expect(api.skipFlags.single, isTrue);
      expect(steps, [
        RecognitionStep.checkingPhoto,
        RecognitionStep.matchingCover,
        RecognitionStep.loadingDetails,
      ]);
      // The scan flow shows the result; the live list stays clean.
      expect(session.jobs, isEmpty);
    });

    test('maps review, unclear photo and failures', () async {
      final api = FakeRecognitionApi();
      final session = RecognitionSession(api: api);
      final service = QueuedRecognitionService(
        session,
        prepare: (bytes) async => fakePrepared(bytes),
      );

      Future<RecognitionOutcome> run(void Function() reply) async {
        final outcome = service.identify(imagePath: photoPath);
        await api.untilWaiting();
        reply();
        return outcome;
      }

      final review = await run(
        () => api.answer(
          ApiRecognition(ApiDecision.needsReview, [
            candidate('1', score: 0.7),
            candidate('2', score: 0.66),
          ]),
        ),
      );
      final blurry = await run(
        () => api.answer(const ApiRecognition(ApiDecision.poorQuality, [])),
      );
      final unknown = await run(
        () => api.answer(const ApiRecognition(ApiDecision.noMatch, [])),
      );
      final offline = await run(api.fail);

      expect(review.kind, RecognitionOutcomeKind.candidates);
      expect(review.candidates.map((c) => c.album.id), ['1', '2']);
      expect(review.candidates.first.confidence, 0.7);
      expect(blurry.kind, RecognitionOutcomeKind.tooBlurry);
      expect(unknown.kind, RecognitionOutcomeKind.notRecognised);
      expect(offline.kind, RecognitionOutcomeKind.notRecognised);
    });

    test('prepares a real photo off the main isolate', () async {
      final api = FakeRecognitionApi();
      final session = RecognitionSession(api: api);
      final service = QueuedRecognitionService(session);

      final outcome = service.identify(imagePath: photoPath);
      await api.untilWaiting(timeout: const Duration(seconds: 10));
      api.answer(matchOf('1'));

      expect((await outcome).kind, RecognitionOutcomeKind.match);
      final crop = img.decodeJpg(api.received.single)!;
      expect(crop.width, 512);
    });
  });
}
