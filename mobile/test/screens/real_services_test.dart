import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jamscan/services/recognition_api.dart';
import 'package:jamscan/services/recognition_service.dart';
import 'package:jamscan/services/release_details_service.dart';

import '../support/fake_release_api.dart';
import '../support/test_app.dart';

/// Finds the network cover image loaded from [url].
Finder coverImage(String url) {
  return find.byWidgetPredicate(
    (widget) =>
        widget is Image &&
        widget.image is NetworkImage &&
        (widget.image as NetworkImage).url == url,
  );
}

/// Recognition that is unsure between two releases, answering with the
/// partial albums the queued service builds from recognition data.
class UnsureRecognition implements RecognitionService {
  @override
  Future<RecognitionOutcome> identify({
    String? imagePath,
    bool skipQualityCheck = false,
    void Function(RecognitionStep step)? onStep,
  }) async {
    return RecognitionOutcome(
      RecognitionOutcomeKind.candidates,
      candidates: [
        RecognitionCandidate(
          albumFromCandidate(
            const ApiCandidate(
              releaseId: kindOfBlueId,
              artist: 'Miles Davis',
              title: 'Kind Of Blue',
              year: 1959,
              score: 0.72,
            ),
          ),
          0.72,
        ),
        RecognitionCandidate(
          albumFromCandidate(
            const ApiCandidate(
              releaseId: '2914120',
              artist: 'John Coltrane',
              title: 'Blue Train',
              score: 0.64,
            ),
          ),
          0.64,
        ),
      ],
    );
  }
}

void main() {
  group('manual search with the backend', () {
    testWidgets('shows Discogs hits with covers and opens full details', (
      tester,
    ) async {
      final api = FakeReleaseApi();
      final services = realServices(api);
      await pumpApp(
        tester,
        dependencies: testDependencies(
          catalog: services.catalog,
          releaseDetails: services.details,
        ),
      );

      await tapKey(tester, 'taskbar.search');
      await tester.enterText(
        find.byKey(const Key('search.field')),
        'kind of blue',
      );
      await tester.pumpAndSettle();

      expect(find.text('1 result from Discogs'), findsOneWidget);
      expect(find.text('Miles Davis · 1959 · Vinyl LP'), findsOneWidget);
      expect(
        coverImage('https://i.discogs.com/kind-of-blue-thumb.jpg'),
        findsOneWidget,
      );
      expect(api.releaseRequests, isEmpty);

      await tester.tap(find.text('Kind Of Blue'));
      await tester.pumpAndSettle();

      // Selecting the hit loaded its details: the preview track is there.
      expect(api.releaseRequests, [kindOfBlueId]);
      expect(find.byKey(const Key('scan.resultCard')), findsOneWidget);
      expect(inResultCard('So What'), findsOneWidget);

      await tester.tap(find.text('Learn more'));
      await tester.pumpAndSettle();

      expect(find.text('Columbia'), findsOneWidget);
      expect(find.text('CL 1355'), findsOneWidget);
      expect(find.text('Freddie Freeloader'), findsOneWidget);
      expect(find.text('Jazz'), findsOneWidget);
      expect(
        coverImage('https://i.discogs.com/kind-of-blue.jpg'),
        findsOneWidget,
      );
      expect(
        find.text('Showing saved info – some details may be missing'),
        findsNothing,
      );
    });

    testWidgets('a backend failure offers a retry', (tester) async {
      final api = FakeReleaseApi()..failing = true;
      final services = realServices(api);
      await pumpApp(
        tester,
        dependencies: testDependencies(
          catalog: services.catalog,
          releaseDetails: services.details,
        ),
      );

      await tapKey(tester, 'taskbar.search');
      await tester.enterText(find.byKey(const Key('search.field')), 'kind');
      await tester.pumpAndSettle();

      expect(find.text("Discogs isn't responding."), findsOneWidget);
      expect(find.text('RETRY'), findsOneWidget);

      api.failing = false;
      await tester.tap(find.text('RETRY'));
      await tester.pumpAndSettle();
      expect(find.text('1 result from Discogs'), findsOneWidget);
    });

    testWidgets('a hit whose details fail still opens, marked partial', (
      tester,
    ) async {
      final api = FakeReleaseApi(releases: {});
      final services = realServices(api);
      await pumpApp(
        tester,
        dependencies: testDependencies(
          catalog: services.catalog,
          releaseDetails: services.details,
        ),
      );

      await showResultViaSearch(tester, query: 'kind', title: 'Kind Of Blue');

      expect(inResultCard('Kind Of Blue'), findsOneWidget);
      await tester.tap(find.text('Learn more'));
      await tester.pumpAndSettle();
      expect(
        find.text('Showing saved info – some details may be missing'),
        findsOneWidget,
      );
    });
  });

  group('candidate selection with the backend', () {
    testWidgets('loads details only for the album the user picks', (
      tester,
    ) async {
      final api = FakeReleaseApi();
      final services = realServices(api);
      await pumpApp(
        tester,
        dependencies: testDependencies(
          camera: FakeCamera()..result = capturedPhoto(),
          recognition: UnsureRecognition(),
          releaseDetails: services.details,
        ),
      );

      await tapKey(tester, 'capture.shutter');
      expect(find.text('Which one is it?'), findsOneWidget);
      expect(api.releaseRequests, isEmpty);

      await tester.tap(find.text('Kind Of Blue'));
      await tester.pumpAndSettle();

      expect(api.releaseRequests, [kindOfBlueId]);
      expect(inResultCard('So What'), findsOneWidget);
    });
  });
}
