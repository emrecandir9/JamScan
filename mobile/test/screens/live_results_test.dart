import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:jamscan/mock/mock_catalog.dart';
import 'package:jamscan/services/recognition_api.dart';
import 'package:jamscan/state/recognition_session.dart';
import 'package:jamscan/vision/best_frame_selector.dart';
import 'package:jamscan/vision/frame_analyzer.dart';
import 'package:jamscan/vision/frame_quality.dart';
import 'package:jamscan/vision/geometry.dart';
import 'package:jamscan/widgets/viewfinder.dart';

import '../support/fake_live_scanner.dart';
import '../support/fake_recognition_api.dart';
import '../support/test_app.dart';

const _quality = CoverQuality(
  sharpness: 100,
  brightness: 120,
  highlights: 200,
  glare: 0,
  size: 0.3,
  skew: 0,
  motion: 0,
);

CoverCapture capture(int hash) => CoverCapture(
  trackId: 1,
  jpeg: img.encodeJpg(img.Image(width: 16, height: 16)),
  hash: hash,
  quality: _quality,
);

Finder inPanel(String text) => find.descendant(
  of: find.byKey(const Key('scan.liveResults')),
  matching: find.text(text),
);

void main() {
  late FakeLiveScanner live;
  late FakeRecognitionApi api;

  Future<void> pumpLive(WidgetTester tester) async {
    live = FakeLiveScanner();
    api = FakeRecognitionApi();
    await pumpApp(
      tester,
      dependencies: testDependencies(
        liveScanner: live,
        session: RecognitionSession(api: api),
      ),
    );
  }

  testWidgets('a detected cover is captured, identified and opened', (
    tester,
  ) async {
    await pumpLive(tester);

    live.covers = [
      CoverSnapshot(
        id: 1,
        quad: Quad(const [
          Point2(0.3, 0.3),
          Point2(0.6, 0.3),
          Point2(0.6, 0.6),
          Point2(0.3, 0.6),
        ]),
        touchesBorder: false,
        hint: CaptureHint.holdSteady,
      ),
    ];
    await tester.pump();
    expect(inPanel('Detected · hold steady'), findsOneWidget);

    live
      ..covers = const []
      ..captureController.add(capture(hashNumber(0)));
    // Let the session start the upload.
    await tester.pump(const Duration(milliseconds: 10));
    expect(inPanel('Identifying'), findsOneWidget);

    api.answer(matchOf(MockCatalog.rumours.id));
    await tester.pumpAndSettle();
    expect(inPanel('Rumours'), findsOneWidget);
    expect(inPanel('Done'), findsOneWidget);

    await tester.tap(inPanel('Rumours'));
    await tester.pumpAndSettle();
    expect(find.text('Tracklist'), findsOneWidget);
    expect(find.textContaining('Fleetwood Mac'), findsWidgets);

    // Back on the camera, the result is still there (FR-10).
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(inPanel('Rumours'), findsOneWidget);
  });

  testWidgets('the results strip stays above the guide square', (tester) async {
    await pumpLive(tester);
    final frameBefore = tester.getRect(find.byType(ViewfinderFrame));
    for (var i = 0; i < 3; i++) {
      live.captureController.add(capture(hashNumber(i)));
    }
    await tester.pump(const Duration(milliseconds: 10));
    api
      ..answer(matchOf(MockCatalog.rumours.id))
      ..answer(matchOf(MockCatalog.kindOfBlue.id))
      ..answer(matchOf(MockCatalog.discovery.id));
    await tester.pumpAndSettle();

    final strip = tester.getRect(find.byKey(const Key('scan.liveResults')));
    final frame = tester.getRect(find.byType(ViewfinderFrame));
    expect(strip.bottom, lessThanOrEqualTo(frame.top));
    // The guide square does not move when results arrive.
    expect(frame, frameBefore);
  });

  testWidgets('an uncertain result lets the user choose', (tester) async {
    await pumpLive(tester);
    live.captureController.add(capture(hashNumber(1)));
    // Let the session start the upload.
    await tester.pump(const Duration(milliseconds: 10));

    api.answer(
      ApiRecognition(ApiDecision.needsReview, [
        candidate(MockCatalog.kindOfBlue.id, score: 0.72),
        candidate(MockCatalog.kindOfBlueReissue.id, score: 0.69),
      ]),
    );
    await tester.pumpAndSettle();
    await tester.tap(inPanel('Needs review'));
    await tester.pumpAndSettle();
    expect(find.text('Which one is it?'), findsOneWidget);
    expect(find.text('72% match'), findsOneWidget);

    await tester.tap(find.byKey(const Key('review.candidate.0')));
    await tester.pumpAndSettle();

    expect(find.text('Tracklist'), findsOneWidget);
  });

  testWidgets('failures can be dismissed', (tester) async {
    await pumpLive(tester);
    live.captureController.add(capture(hashNumber(2)));
    // Let the session start the upload.
    await tester.pump(const Duration(milliseconds: 10));

    api.fail();
    await tester.pumpAndSettle();
    expect(inPanel('Service unavailable'), findsOneWidget);

    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('scan.liveResults')),
        matching: find.byTooltip('Dismiss'),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('scan.liveResults')), findsNothing);
  });
}
