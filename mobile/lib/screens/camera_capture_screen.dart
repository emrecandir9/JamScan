import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/camera_capture_service.dart';
import '../services/gallery_import_service.dart';

typedef CoverImageBuilder = Widget Function(String imagePath);

class CameraCaptureScreen extends StatefulWidget {
  const CameraCaptureScreen({
    super.key,
    this.service,
    this.galleryService,
    this.imageBuilder,
  });

  final CameraCaptureService? service;
  final GalleryImportService? galleryService;

  /// Optional image builder mainly useful for widget tests.
  /// In production, Image.file is used by default.
  final CoverImageBuilder? imageBuilder;

  @override
  State<CameraCaptureScreen> createState() => _CameraCaptureScreenState();
}

class _CameraCaptureScreenState extends State<CameraCaptureScreen> {
  late final CameraCaptureService _service;
  late final GalleryImportService _galleryService;

  String? _photoPath;
  String? _message;
  bool _busy = true;
  bool _showSettings = false;

  @override
  void initState() {
    super.initState();

    _service = widget.service ?? CameraCaptureService();
    _galleryService = widget.galleryService ?? GalleryImportService();

    _recoverCapture();
  }

  Future<void> _recoverCapture() async {
    // Recovering pending captures is specific to Android.
    final result = Platform.isAndroid
        ? await _service.recoverLostCapture()
        : null;

    if (!mounted) return;

    setState(() {
      _busy = false;

      if (result != null) {
        _applyCameraResult(result);
      }
    });
  }

  void _applyCameraResult(CameraCaptureResult result) {
    _showSettings =
        result.status == CameraCaptureStatus.permissionPermanentlyDenied;

    switch (result.status) {
      case CameraCaptureStatus.captured:
        _photoPath = result.photo!.path;
        _message = 'Cover photo captured.';
        break;

      case CameraCaptureStatus.cancelled:
        _message = 'Capture cancelled.';
        break;

      case CameraCaptureStatus.permissionDenied:
        _message = 'Camera permission is needed to photograph the cover.';
        break;

      case CameraCaptureStatus.permissionPermanentlyDenied:
        _message = 'Enable camera permission in JamSCAN settings.';
        break;

      case CameraCaptureStatus.failed:
        _message = 'Could not capture the photo. Please try again.';
        break;
    }
  }

  void _applyGalleryResult(GalleryImportResult result) {
    switch (result.status) {
      case GalleryImportStatus.selected:
        _photoPath = result.image!.path;
        _message = 'Cover image selected from gallery.';
        break;

      case GalleryImportStatus.cancelled:
        _message = 'Gallery selection cancelled.';
        break;

      case GalleryImportStatus.failed:
        _message = 'Could not import the image. Please try again.';
        break;
    }
  }

  Future<void> _capture() async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _message = null;
      _showSettings = false;
    });

    final result = await _service.capture();

    if (!mounted) return;

    setState(() {
      _busy = false;
      _applyCameraResult(result);
    });
  }

  Future<void> _importFromGallery() async {
    if (_busy) return;

    setState(() {
      _busy = true;
      _message = null;
      _showSettings = false;
    });

    final result = await _galleryService.importImage();

    if (!mounted) return;

    setState(() {
      _busy = false;
      _applyGalleryResult(result);
    });
  }

  Future<void> _openSettings() async {
    if (_busy) return;

    setState(() => _busy = true);

    var opened = false;

    try {
      opened = await _service.openSettings();
    } on PlatformException {
      opened = false;
    }

    if (!mounted) return;

    setState(() {
      _busy = false;
      _message = opened
          ? 'After returning from settings, tap the button to take a photo.'
          : 'Could not open settings. Please open them from Android settings.';
    });
  }

  Widget _buildCoverPreview() {
    final imagePath = _photoPath!;

    if (widget.imageBuilder != null) {
      return widget.imageBuilder!(imagePath);
    }

    return Image.file(
      File(imagePath),
      height: 280,
      fit: BoxFit.contain,
      semanticLabel: 'Cover photo',
      errorBuilder: (context, error, stackTrace) {
        return const Text(
          'Cannot display this image. Please choose another one.',
          textAlign: TextAlign.center,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('JamSCAN')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text('Welcome to JamSCAN', textAlign: TextAlign.center),
              const SizedBox(height: 24),

              if (_photoPath != null) ...[
                _buildCoverPreview(),
                const SizedBox(height: 16),
              ],

              FilledButton.icon(
                onPressed: _busy ? null : _capture,
                icon: const Icon(Icons.camera_alt),
                label: Text(
                  _photoPath == null ? 'Photograph cover' : 'Retake photo',
                ),
              ),

              const SizedBox(height: 12),

              OutlinedButton.icon(
                onPressed: _busy ? null : _importFromGallery,
                icon: const Icon(Icons.photo_library),
                label: Text(
                  _photoPath == null
                      ? 'Choose from gallery'
                      : 'Choose another image',
                ),
              ),

              if (_busy) ...[
                const SizedBox(height: 16),
                const CircularProgressIndicator(),
              ],

              if (_message != null) ...[
                const SizedBox(height: 16),
                Semantics(
                  liveRegion: true,
                  child: Text(_message!, textAlign: TextAlign.center),
                ),
              ],

              if (_showSettings)
                TextButton(
                  onPressed: _busy ? null : _openSettings,
                  child: const Text('Open settings'),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
