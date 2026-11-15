import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:jamscan/services/gallery_import_service.dart';
import 'package:jamscan/services/queued_recognition_service.dart';
import 'package:jamscan/services/recognition_api.dart';
import 'package:jamscan/state/preview_player.dart';
import 'package:jamscan/state/recognition_session.dart';
import 'package:jamscan/vision/frame_quality.dart';
import 'package:jamscan/vision/still_cover.dart';

import '../support/fake_preview_audio.dart';
import '../support/fake_release_api.dart';
import '../support/test_app.dart';

/// S2-08: the complete recognition workflow through the whole app.
///
/// Only the edges are fake: the camera and gallery, the recognition
/// endpoint (`POST /recognitions`), the release endpoints
/// (`GET /releases/...`) and the audio engine. Everything in between is the
/// real code: the photo flow, `QueuedRecognitionService`,
/// `RecognitionSession`, the S2-05 metadata cache, the S2-07 release
/// services, Album Details and the S2-06 preview player.

const _previewUrl = 'https://audio.itunes.example/so-what.m4a';
const _partialBanner = 'Showing saved info – some details may be missing';

/// Recognition backend that gives scripted answers in order. An answer is an
/// [ApiRecognition] or an exception to throw (backend unavailable).
class ScriptedRecognitionApi implements RecognitionApi {
  ScriptedRecognitionApi(this.answers);

  final List<Object> answers;
  int calls = 0;

  @override
  Future<ApiRecognition> recognize(
    Uint8List jpeg, {
    bool skipQualityCheck = false,
  }) async {
    final answer = answers[calls.clamp(0, answers.length - 1)];
    calls++;
    if (answer is ApiRecognition) return answer;
    throw answer;
  }
}

const _kindOfBlue = ApiCandidate(
  releaseId: kindOfBlueId,
  artist: 'Miles Davis',
  title: 'Kind Of Blue',
  year: 1959,
  score: 0.91,
);

const _blueTrain = ApiCandidate(
  releaseId: '2914120',
  artist: 'John Coltrane',
  title: 'Blue Train',
  year: 1957,
  score: 0.64,
);

/// A detected, sharp cover, as the real preparation step would return.
PreparedCover _preparedCover(Uint8List _) => PreparedCover(
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

/// The app wired to real services, with fakes only at the edges.
class Workflow {
  Workflow({required List<Object> recognitions, FakeReleaseApi? releases})
    : recognition = ScriptedRecognitionApi(recognitions),
      releases = releases ?? FakeReleaseApi();

  final ScriptedRecognitionApi recognition;
  final FakeReleaseApi releases;
  final camera = FakeCamera()..result = capturedPhoto();
  final gallery = FakeGallery();
  final engines = <FakePreviewAudio>[];
  late final PreviewPlayer player;

  Future<void> start(WidgetTester tester) async {
    final services = realServices(releases);
    final session = RecognitionSession(
      api: recognition,
      details: services.details,
    );
    player = PreviewPlayer(
      audioFactory: () {
        final audio = FakePreviewAudio();
        engines.add(audio);
        return audio;
      },
    );
    await pumpApp(
      tester,
      dependencies: testDependencies(
        camera: camera,
        gallery: gallery,
        session: session,
        recognition: QueuedRecognitionService(
          session,
          prepare: (bytes) async => _preparedCover(bytes),
          readPhoto: (path) async => Uint8List.fromList([0]),
        ),
        catalog: services.catalog,
        releaseDetails: services.details,
        player: player,
      ),
    );
  }
}

void main() {
  testWidgets('E2E-1 camera photo: match, Album Details and preview playback', (
    tester,
  ) async {
    final app = Workflow(
      recognitions: [
        const ApiRecognition(ApiDecision.match, [_kindOfBlue]),
      ],
    );
    await app.start(tester);

    await tapKey(tester, 'capture.shutter');

    expect(app.recognition.calls, 1);
    expect(app.releases.releaseRequests, [kindOfBlueId]);
    expect(inResultCard('Kind Of Blue'), findsOneWidget);

    await tester.tap(find.text('Learn more'));
    await tester.pumpAndSettle();

    // Real Discogs metadata from GET /releases/{id}, through the cache.
    expect(find.text('Columbia'), findsOneWidget);
    expect(find.text('CL 1355'), findsOneWidget);
    expect(find.text('So What'), findsOneWidget);
    expect(find.text('Freddie Freeloader'), findsOneWidget);
    expect(find.text(_partialBanner), findsNothing);

    // So What has a preview, Freddie Freeloader has none.
    expect(find.byTooltip('Preview unavailable'), findsOneWidget);
    await tester.tap(find.byTooltip('Play preview').first);
    await tester.pumpAndSettle();

    expect(app.player.isPlaying, isTrue);
    expect(app.engines.single.url, _previewUrl);
    expect(app.engines.single.limit, const Duration(seconds: 30));
    expect(find.byKey(const Key('miniPlayer')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('E2E-2 gallery import: match and Album Details', (tester) async {
    final app = Workflow(
      recognitions: [
        const ApiRecognition(ApiDecision.match, [_kindOfBlue]),
      ],
    );
    app.gallery.result = GalleryImportResult(
      GalleryImportStatus.selected,
      image: XFile(testPhotoPath),
    );
    await app.start(tester);

    await tapKey(tester, 'capture.gallery');

    expect(app.recognition.calls, 1);
    expect(inResultCard('Kind Of Blue'), findsOneWidget);
    await tester.tap(find.text('Learn more'));
    await tester.pumpAndSettle();
    expect(find.text('Columbia'), findsOneWidget);
  });

  testWidgets('E2E-3 ranked candidates: details load only for the pick', (
    tester,
  ) async {
    final app = Workflow(
      recognitions: [
        const ApiRecognition(ApiDecision.needsReview, [
          _kindOfBlue,
          _blueTrain,
        ]),
      ],
    );
    await app.start(tester);

    await tapKey(tester, 'capture.shutter');

    expect(find.text('Which one is it?'), findsOneWidget);
    expect(find.text('Kind Of Blue'), findsOneWidget);
    expect(find.text('Blue Train'), findsOneWidget);
    expect(app.releases.releaseRequests, isEmpty);

    await tester.tap(find.text('Kind Of Blue'));
    await tester.pumpAndSettle();

    expect(app.releases.releaseRequests, [kindOfBlueId]);
    expect(inResultCard('Kind Of Blue'), findsOneWidget);
    expect(inResultCard('So What'), findsOneWidget);
  });

  testWidgets('E2E-4 no match: manual search finds the album', (tester) async {
    final app = Workflow(
      recognitions: [const ApiRecognition(ApiDecision.noMatch, [])],
    );
    await app.start(tester);

    await tapKey(tester, 'capture.shutter');

    expect(find.text("We couldn't identify this album"), findsOneWidget);
    await tester.tap(find.text('Search manually'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('search.field')), 'kind');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Kind Of Blue'));
    await tester.pumpAndSettle();

    expect(app.releases.searchRequests, ['kind']);
    expect(inResultCard('Kind Of Blue'), findsOneWidget);
  });

  testWidgets('E2E-5 recognition backend unavailable: fallback still works', (
    tester,
  ) async {
    final app = Workflow(
      recognitions: [
        const RecognitionUnavailableException('connection refused'),
      ],
    );
    await app.start(tester);

    await tapKey(tester, 'capture.shutter');

    // Defect D1 (docs/S2-08.md): an unreachable backend is shown with the
    // same message as an unknown album. The fallbacks still work.
    expect(find.text("We couldn't identify this album"), findsOneWidget);
    expect(find.text('Search manually'), findsOneWidget);
    expect(find.text('Retake photo'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('E2E-6 metadata backend unavailable: album opens as partial', (
    tester,
  ) async {
    final app = Workflow(
      recognitions: [
        const ApiRecognition(ApiDecision.match, [_kindOfBlue]),
      ],
      releases: FakeReleaseApi()..failing = true,
    );
    await app.start(tester);

    await tapKey(tester, 'capture.shutter');

    // Identified from recognition data even though Discogs is down.
    expect(inResultCard('Kind Of Blue'), findsOneWidget);
    await tester.tap(find.text('Learn more'));
    await tester.pumpAndSettle();
    expect(find.text(_partialBanner), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('E2E-7 album without previews: playback is disabled', (
    tester,
  ) async {
    final json = kindOfBlueJson();
    json['tracks'] = [
      for (final track in json['tracks']! as List)
        {...(track as Map<String, Object?>), 'preview_url': null},
    ];
    json['preview_status'] = 'none_found';
    final app = Workflow(
      recognitions: [
        const ApiRecognition(ApiDecision.match, [_kindOfBlue]),
      ],
      releases: FakeReleaseApi(releases: {kindOfBlueId: json}),
    );
    await app.start(tester);

    await tapKey(tester, 'capture.shutter');
    await tester.tap(find.text('Learn more'));
    await tester.pumpAndSettle();

    expect(find.text('No previews available for this album.'), findsOneWidget);
    expect(find.byTooltip('Play preview'), findsNothing);
    expect(find.byTooltip('Preview unavailable'), findsNWidgets(2));
    expect(app.engines, isEmpty);
  });
}
