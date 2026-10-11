import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

enum GalleryImportStatus { selected, cancelled, failed }

class GalleryImportResult {
  const GalleryImportResult(this.status, {this.image});

  final GalleryImportStatus status;
  final XFile? image;
}

class GalleryImportService {
  GalleryImportService({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  Future<GalleryImportResult> importImage() async {
    try {
      final image = await _picker.pickImage(
        source: ImageSource.gallery,
        requestFullMetadata: false,
      );

      if (image == null) {
        return const GalleryImportResult(GalleryImportStatus.cancelled);
      }

      return GalleryImportResult(GalleryImportStatus.selected, image: image);
    } on PlatformException {
      return const GalleryImportResult(GalleryImportStatus.failed);
    }
  }
}
