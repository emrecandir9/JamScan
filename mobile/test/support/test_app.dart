import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:jamscan/app.dart';
import 'package:jamscan/app_scope.dart';
import 'package:jamscan/services/camera_capture_service.dart';
import 'package:jamscan/services/catalog_service.dart';
import 'package:jamscan/services/gallery_import_service.dart';
import 'package:jamscan/services/recognition_service.dart';
import 'package:jamscan/state/auth_controller.dart';
import 'package:jamscan/state/settings_controller.dart';

/// Camera service that never touches the platform.
class FakeCamera extends CameraCaptureService {
  CameraCaptureResult result = const CameraCaptureResult(
    CameraCaptureStatus.cancelled,
  );

  Completer<CameraCaptureResult>? pending;
  int captureCalls = 0;
  int settingsCalls = 0;

  @override
  Future<CameraCaptureResult> capture() async {
    captureCalls++;
    final pending = this.pending;
    return pending == null ? result : await pending.future;
  }

  @override
  Future<CameraCaptureResult?> recoverLostCapture() async => null;

  @override
  Future<bool> openSettings() async {
    settingsCalls++;
    return true;
  }
}

class FakeGallery extends GalleryImportService {
  GalleryImportResult result = const GalleryImportResult(
    GalleryImportStatus.cancelled,
  );

  @override
  Future<GalleryImportResult> importImage() async => result;
}

/// A captured photo whose file does not exist, so covers fall back to the
/// placeholder without loading anything.
const testPhotoPath = '/nonexistent/jamscan-test-cover.jpg';

CameraCaptureResult capturedPhoto() {
  return CameraCaptureResult(
    CameraCaptureStatus.captured,
    photo: XFile(testPhotoPath),
  );
}

/// Dependencies with fakes and fast mocks. Autoplay is off so no preview
/// timer runs unless a test starts one.
AppDependencies testDependencies({
  bool signedIn = false,
  FakeCamera? camera,
  FakeGallery? gallery,
  List<RecognitionOutcomeKind> script = const [RecognitionOutcomeKind.match],
  Duration stepDelay = const Duration(milliseconds: 10),
  MockCatalogService? catalog,
}) {
  return AppDependencies(
    auth: AuthController(signedInAsDemo: signedIn),
    camera: camera ?? FakeCamera(),
    gallery: gallery ?? FakeGallery(),
    recognition: MockRecognitionService(script: script, stepDelay: stepDelay),
    catalog:
        catalog ?? MockCatalogService(latency: const Duration(milliseconds: 10)),
    settings: SettingsController(autoplayTopTrack: false),
  );
}

/// Pumps the whole app on a 360 x 800 phone screen.
Future<AppDependencies> pumpApp(
  WidgetTester tester, {
  AppDependencies? dependencies,
}) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final deps = dependencies ?? testDependencies();
  await tester.pumpWidget(JamScanApp(dependencies: deps));
  await tester.pumpAndSettle();
  return deps;
}

/// Taps a widget by key and waits for animations to finish.
Future<void> tapKey(WidgetTester tester, String key) async {
  await tester.tap(find.byKey(Key(key)));
  await tester.pumpAndSettle();
}

/// Uses manual search from the camera page to show [title] as a result.
Future<void> showResultViaSearch(
  WidgetTester tester, {
  required String query,
  required String title,
}) async {
  await tapKey(tester, 'taskbar.search');
  await tester.enterText(find.byKey(const Key('search.field')), query);
  await tester.pumpAndSettle();
  await tester.tap(find.text(title));
  await tester.pumpAndSettle();
}

/// Finds [text] inside the result card on the camera page.
Finder inResultCard(String text) {
  return find.descendant(
    of: find.byKey(const Key('scan.resultCard')),
    matching: find.text(text),
  );
}

/// Waits until any snack bar has been dismissed.
Future<void> waitForSnackBarToClose(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 5));
  await tester.pumpAndSettle();
}
