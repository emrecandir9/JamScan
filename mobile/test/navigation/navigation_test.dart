import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:jamscan/mock/mock_catalog.dart';
import 'package:jamscan/models/library.dart';
import 'package:jamscan/services/recognition_service.dart';
import 'package:jamscan/state/auth_controller.dart';

import '../support/test_app.dart';

void main() {
  group('tabs and taskbars', () {
    testWidgets('capture card Library opens the Library tab', (tester) async {
      await pumpApp(tester);

      await tapKey(tester, 'capture.library');

      expect(find.text('Sign in to build your library'), findsOneWidget);
      // Library uses the Profile / Scan / Library taskbar.
      expect(find.byKey(const Key('taskbar.profile')), findsOneWidget);
      expect(find.byKey(const Key('taskbar.history')), findsNothing);

      await tapKey(tester, 'taskbar.scan');

      expect(find.byKey(const Key('taskbar.history')), findsOneWidget);
      expect(find.text('Fit the album cover inside the frame'), findsOneWidget);
    });

    testWidgets('profile button and taskbar switch between tabs', (
      tester,
    ) async {
      await pumpApp(tester);

      await tapKey(tester, 'scan.profile');
      expect(find.text("You're browsing as a guest"), findsOneWidget);

      await tapKey(tester, 'taskbar.library');
      expect(find.text('Sign in to build your library'), findsOneWidget);

      await tapKey(tester, 'taskbar.profile');
      expect(find.text("You're browsing as a guest"), findsOneWidget);
    });

    testWidgets('back from another tab returns to the Scan tab', (
      tester,
    ) async {
      await pumpApp(tester);
      await tapKey(tester, 'scan.profile');

      await tester.state<NavigatorState>(find.byType(Navigator)).maybePop();
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('taskbar.history')), findsOneWidget);
    });

    testWidgets('a taskbar tap on a pushed page closes it', (tester) async {
      await pumpApp(tester, dependencies: testDependencies(signedIn: true));
      await tapKey(tester, 'capture.library');
      await tester.tap(find.text('My Vinyl'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('list.search')), findsOneWidget);

      await tapKey(tester, 'taskbar.profile');

      expect(find.byKey(const Key('list.search')), findsNothing);
      expect(find.text('Demo Collector'), findsOneWidget);
    });
  });

  group('scan flow', () {
    testWidgets('a photo is identified and shown over the camera', (
      tester,
    ) async {
      final camera = FakeCamera()..result = capturedPhoto();
      await pumpApp(tester, dependencies: testDependencies(camera: camera));

      await tapKey(tester, 'capture.shutter');

      expect(find.byKey(const Key('scan.resultCard')), findsOneWidget);
      expect(inResultCard('Miles Davis · 1959 · Vinyl LP'), findsOneWidget);
      expect(find.text('Match found'), findsOneWidget);
    });

    testWidgets('stop scan returns to the camera', (tester) async {
      final camera = FakeCamera()..result = capturedPhoto();
      await pumpApp(
        tester,
        dependencies: testDependencies(
          camera: camera,
          stepDelay: const Duration(seconds: 2),
        ),
      );

      await tester.tap(find.byKey(const Key('capture.shutter')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('Identifying album…'), findsOneWidget);

      await tester.tap(find.text('Stop scan'));
      await tester.pumpAndSettle();
      expect(find.text('Fit the album cover inside the frame'), findsOneWidget);
      expect(find.byKey(const Key('scan.resultCard')), findsNothing);

      // Let the abandoned recognition finish.
      await tester.pump(const Duration(seconds: 10));
      expect(find.byKey(const Key('scan.resultCard')), findsNothing);
    });

    testWidgets('several matches let the user pick one', (tester) async {
      final camera = FakeCamera()..result = capturedPhoto();
      await pumpApp(
        tester,
        dependencies: testDependencies(
          camera: camera,
          script: const [RecognitionOutcomeKind.candidates],
        ),
      );

      await tapKey(tester, 'capture.shutter');
      expect(find.text('Which one is it?'), findsOneWidget);

      await tester.tap(find.text('Blue Train'));
      await tester.pumpAndSettle();

      expect(inResultCard('John Coltrane · 1957 · Vinyl LP'), findsOneWidget);
    });

    testWidgets('an unrecognised cover leads to manual search', (
      tester,
    ) async {
      final camera = FakeCamera()..result = capturedPhoto();
      await pumpApp(
        tester,
        dependencies: testDependencies(
          camera: camera,
          script: const [RecognitionOutcomeKind.notRecognised],
        ),
      );

      await tapKey(tester, 'capture.shutter');
      expect(find.text("We couldn't identify this album"), findsOneWidget);

      await tester.tap(find.text('Search manually'));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('search.field')), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('search.field')),
        'blue train',
      );
      await tester.pumpAndSettle();
      await tester.tap(find.text('Blue Train'));
      await tester.pumpAndSettle();

      expect(inResultCard('John Coltrane · 1957 · Vinyl LP'), findsOneWidget);
    });

    testWidgets('a blurry photo can be used anyway', (tester) async {
      final camera = FakeCamera()..result = capturedPhoto();
      await pumpApp(
        tester,
        dependencies: testDependencies(
          camera: camera,
          script: const [RecognitionOutcomeKind.tooBlurry],
        ),
      );

      await tapKey(tester, 'capture.shutter');
      expect(find.text('Photo too blurry or dark'), findsOneWidget);

      await tester.tap(find.text('Use anyway'));
      await tester.pumpAndSettle();

      expect(inResultCard('Miles Davis · 1959 · Vinyl LP'), findsOneWidget);
    });

    testWidgets('All tracks expands the top tracks list', (tester) async {
      await pumpApp(tester);
      await showResultViaSearch(tester, query: 'rumours', title: 'Rumours');

      await tapKey(tester, 'scan.allTracks');
      expect(find.text('Top tracks · by popularity'), findsOneWidget);
      expect(inResultCard('Go Your Own Way'), findsOneWidget);

      await tapKey(tester, 'scan.collapseTracks');
      expect(find.text('Top tracks · by popularity'), findsNothing);
    });

    testWidgets('Learn more opens album details with the main taskbar', (
      tester,
    ) async {
      await pumpApp(tester);
      await showResultViaSearch(tester, query: 'rumours', title: 'Rumours');

      await tester.tap(find.text('Learn more'));
      await tester.pumpAndSettle();

      expect(find.text('Tracklist'), findsOneWidget);
      expect(find.byKey(const Key('taskbar.library')), findsOneWidget);

      await tapKey(tester, 'taskbar.scan');
      expect(find.byKey(const Key('scan.resultCard')), findsOneWidget);
    });
  });

  group('accounts', () {
    testWidgets('a guest signs in from the save prompt and saves', (
      tester,
    ) async {
      final deps = await pumpApp(tester);
      await showResultViaSearch(
        tester,
        query: 'discovery',
        title: 'Discovery',
      );

      await tester.tap(find.byTooltip('Add to collection'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in to save albums'), findsOneWidget);

      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('login.email')),
        AuthController.demoEmail,
      );
      await tester.enterText(
        find.byKey(const Key('login.password')),
        AuthController.demoPassword,
      );
      await tapKey(tester, 'login.submit');

      expect(deps.auth.isSignedIn, isTrue);
      expect(find.text('Save album'), findsOneWidget);

      await tapKey(tester, 'saveAlbum.save');

      expect(find.text('Saved to My Vinyl'), findsOneWidget);
      final myVinyl = deps.library.listsOf(ListKind.collection).first;
      expect(myVinyl.containsAlbum(MockCatalog.discovery.id), isTrue);
    });

    testWidgets('an album already in the list cannot be saved twice', (
      tester,
    ) async {
      await pumpApp(tester, dependencies: testDependencies(signedIn: true));
      await showResultViaSearch(tester, query: 'rumours', title: 'Rumours');

      await tester.tap(find.byTooltip('Add to collection'));
      await tester.pumpAndSettle();

      expect(find.text("Already in 'My Vinyl'"), findsOneWidget);
      final save = tester.widget<FilledButton>(
        find.byKey(const Key('saveAlbum.save')),
      );
      expect(save.onPressed, isNull);
    });

    testWidgets('wrong password shows an error', (tester) async {
      final deps = await pumpApp(tester);
      await tapKey(tester, 'scan.profile');
      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('login.email')),
        AuthController.demoEmail,
      );
      await tester.enterText(
        find.byKey(const Key('login.password')),
        'not-the-password',
      );
      await tapKey(tester, 'login.submit');

      expect(find.text('Incorrect email or password'), findsOneWidget);
      expect(deps.auth.isSignedIn, isFalse);
    });

    testWidgets('a new account starts with an empty library', (tester) async {
      await pumpApp(tester);
      await tapKey(tester, 'capture.library');
      await tester.tap(find.text('Create account'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byKey(const Key('login.name')), 'Sam');
      await tester.enterText(
        find.byKey(const Key('login.email')),
        'sam@example.com',
      );
      await tester.enterText(
        find.byKey(const Key('login.password')),
        'longenough',
      );
      await tapKey(tester, 'login.submit');

      expect(find.text('Your library is empty'), findsOneWidget);
    });

    testWidgets('log out from settings returns to the guest profile', (
      tester,
    ) async {
      final deps = await pumpApp(
        tester,
        dependencies: testDependencies(signedIn: true),
      );
      await tapKey(tester, 'scan.profile');
      expect(find.text('Demo Collector'), findsOneWidget);

      await tester.tap(find.byTooltip('Settings'));
      await tester.pumpAndSettle();
      expect(find.text('Autoplay top track'), findsOneWidget);

      await tester.tap(find.text('Log out'));
      await tester.pumpAndSettle();

      expect(deps.auth.isSignedIn, isFalse);
      expect(find.text("You're browsing as a guest"), findsOneWidget);
    });

    testWidgets('history needs an account', (tester) async {
      await pumpApp(tester);

      await tapKey(tester, 'taskbar.history');

      expect(find.text('Sign in to keep your history'), findsOneWidget);
      await tester.tap(find.text('Not now'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in to keep your history'), findsNothing);
    });

    testWidgets('opening a past scan shows it on the camera', (tester) async {
      await pumpApp(tester, dependencies: testDependencies(signedIn: true));

      await tapKey(tester, 'taskbar.history');
      expect(find.text('Clear all'), findsOneWidget);

      await tester.tap(find.text('Kind of Blue'));
      await tester.pumpAndSettle();

      expect(inResultCard('Miles Davis · 1959 · Vinyl LP'), findsOneWidget);
    });
  });
}
