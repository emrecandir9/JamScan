import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

enum CameraCaptureStatus {
  captured,
  cancelled,
  permissionDenied,
  permissionPermanentlyDenied,
  failed,
}

class CameraCaptureResult {
  const CameraCaptureResult(this.status, {this.photo});

  final CameraCaptureStatus status;
  final XFile? photo;
}

class CameraCaptureService {
  CameraCaptureService({ImagePicker? picker})
    : _picker = picker ?? ImagePicker();

  final ImagePicker _picker;

  Future<CameraCaptureResult> capture() async {
    try {
      final permission = await Permission.camera.request();

      if (permission.isPermanentlyDenied) {
        return const CameraCaptureResult(
          CameraCaptureStatus.permissionPermanentlyDenied,
        );
      }

      if (!permission.isGranted) {
        return const CameraCaptureResult(CameraCaptureStatus.permissionDenied);
      }

      final photo = await _picker.pickImage(
        source: ImageSource.camera,
        requestFullMetadata: false,
      );

      if (photo == null) {
        return const CameraCaptureResult(CameraCaptureStatus.cancelled);
      }

      return CameraCaptureResult(CameraCaptureStatus.captured, photo: photo);
    } on PlatformException {
      return const CameraCaptureResult(CameraCaptureStatus.failed);
    }
  }

  // Android may terminate the app while the camera is open.
  // Check for a recovered capture when the screen starts.
  Future<CameraCaptureResult?> recoverLostCapture() async {
    try {
      final response = await _picker.retrieveLostData();

      if (response.isEmpty) {
        return null;
      }

      final photos = response.files;
      if (photos != null && photos.isNotEmpty) {
        return CameraCaptureResult(
          CameraCaptureStatus.captured,
          photo: photos.first,
        );
      }

      return const CameraCaptureResult(CameraCaptureStatus.failed);
    } on PlatformException {
      return const CameraCaptureResult(CameraCaptureStatus.failed);
    }
  }

  Future<bool> openSettings() => openAppSettings();
}
