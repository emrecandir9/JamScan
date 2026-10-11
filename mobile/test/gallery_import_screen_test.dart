import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';
import 'package:jamscan/screens/camera_capture_screen.dart';
import 'package:jamscan/services/gallery_import_service.dart';

class FakeGalleryService extends GalleryImportService {
  GalleryImportResult result = const GalleryImportResult(
    GalleryImportStatus.cancelled,
  );

  Completer<GalleryImportResult>? pending;
  int importCalls = 0;

  @override
  Future<GalleryImportResult> importImage() async {
    importCalls++;

    if (pending != null) {
      return pending!.future;
    }

    return result;
  }
}

Future<void> showScreen(
  WidgetTester tester,
  FakeGalleryService galleryService, {
  CoverImageBuilder? imageBuilder,
}) async {
  await tester.pumpWidget(
    MaterialApp(
      home: CameraCaptureScreen(
        galleryService: galleryService,
        imageBuilder: imageBuilder,
      ),
    ),
  );

  await tester.pumpAndSettle();
}

void main() {
  testWidgets('gallery button is available', (tester) async {
    final galleryService = FakeGalleryService();

    await showScreen(tester, galleryService);

    expect(find.text('Choose from gallery'), findsOneWidget);
  });

  testWidgets('cancelling gallery selection allows another attempt', (
    tester,
  ) async {
    final galleryService = FakeGalleryService();

    await showScreen(tester, galleryService);

    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();

    expect(find.text('Gallery selection cancelled.'), findsOneWidget);

    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();

    expect(galleryService.importCalls, 2);

    expect(tester.takeException(), isNull);
  });

  testWidgets('gallery failure shows an error and allows retrying', (
    tester,
  ) async {
    final galleryService = FakeGalleryService()
      ..result = const GalleryImportResult(GalleryImportStatus.failed);

    await showScreen(tester, galleryService);

    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();

    expect(
      find.text('Could not import the image. Please try again.'),
      findsOneWidget,
    );

    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();

    expect(galleryService.importCalls, 2);
  });

  testWidgets('selected gallery image is displayed', (tester) async {
    const selectedPath = 'test/fixtures/album_cover.jpg';

    String? previewPath;

    final galleryService = FakeGalleryService()
      ..result = GalleryImportResult(
        GalleryImportStatus.selected,
        image: XFile(selectedPath),
      );

    await showScreen(
      tester,
      galleryService,
      imageBuilder: (imagePath) {
        previewPath = imagePath;

        return const SizedBox(
          key: Key('cover-image-preview'),
          width: 100,
          height: 100,
        );
      },
    );

    await tester.tap(find.text('Choose from gallery'));
    await tester.pumpAndSettle();

    expect(galleryService.importCalls, 1);

    expect(previewPath, selectedPath);

    expect(find.byKey(const Key('cover-image-preview')), findsOneWidget);

    expect(find.text('Cover image selected from gallery.'), findsOneWidget);

    expect(find.text('Choose another image'), findsOneWidget);

    expect(find.text('Retake photo'), findsOneWidget);

    expect(tester.takeException(), isNull);
  });

  testWidgets('does not start another gallery selection while one is pending', (
    tester,
  ) async {
    final pending = Completer<GalleryImportResult>();

    final galleryService = FakeGalleryService()..pending = pending;

    await showScreen(tester, galleryService);

    await tester.tap(find.text('Choose from gallery'));
    await tester.pump();

    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    expect(galleryService.importCalls, 1);

    final galleryButton = tester.widget<OutlinedButton>(
      find.widgetWithText(OutlinedButton, 'Choose from gallery'),
    );

    final cameraButton = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Photograph cover'),
    );

    expect(galleryButton.onPressed, isNull);

    expect(cameraButton.onPressed, isNull);

    pending.complete(const GalleryImportResult(GalleryImportStatus.cancelled));

    await tester.pumpAndSettle();

    expect(find.byType(CircularProgressIndicator), findsNothing);

    expect(find.text('Gallery selection cancelled.'), findsOneWidget);
  });
}
