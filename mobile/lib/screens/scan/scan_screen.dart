import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../app_scope.dart';
import '../../models/album.dart';
import '../../models/library.dart';
import '../../routing/app_navigation.dart';
import '../../services/camera_capture_service.dart';
import '../../services/gallery_import_service.dart';
import '../../state/shell_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/album_art.dart';
import '../../widgets/capture_card.dart';
import '../../widgets/common.dart';
import '../../widgets/sign_in_prompt.dart';
import '../../widgets/taskbars.dart';
import '../../widgets/viewfinder.dart';
import '../album/save_album_sheet.dart';
import '../history/history_sheet.dart';
import 'result_card.dart';
import 'scan_flow_screen.dart';

/// The Scan tab and start page of the app.
///
/// Wireframes 01 (camera), 02b (camera access off) and 10a-c (result
/// overlaid on the camera). There is no camera package in the project yet,
/// so the viewfinder is a placeholder and the shutter opens the system
/// camera through [CameraCaptureService] (S1-03).
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanResult {
  const _ScanResult(this.album, this.photoPath);

  final Album album;
  final String? photoPath;
}

class _ScanScreenState extends State<ScanScreen> {
  late final AppDependencies _deps = AppScope.of(context);

  /// Set when the camera permission was refused.
  CameraCaptureStatus? _permissionProblem;
  bool _busy = false;
  _ScanResult? _result;

  @override
  void initState() {
    super.initState();
    _deps.shell.addListener(_onShellChanged);
    // Android may stop the app while the system camera is open.
    if (Platform.isAndroid) {
      _recoverCapture();
    }
  }

  @override
  void dispose() {
    _deps.shell.removeListener(_onShellChanged);
    super.dispose();
  }

  void _onShellChanged() {
    final shell = _deps.shell;
    if (shell.tab != AppTab.scan) {
      _deps.player.pause();
      return;
    }
    final album = shell.takePendingResult();
    if (album != null) {
      _showResult(album, null);
    }
  }

  Future<void> _recoverCapture() async {
    final result = await _deps.camera.recoverLostCapture();
    if (!mounted || result == null) return;
    await _handleCapture(result);
  }

  Future<void> _capture() async {
    if (_busy) return;
    setState(() => _busy = true);
    _deps.player.pause();

    final result = await _deps.camera.capture();
    if (!mounted) return;
    setState(() => _busy = false);
    await _handleCapture(result);
  }

  Future<void> _handleCapture(CameraCaptureResult result) async {
    switch (result.status) {
      case CameraCaptureStatus.captured:
        setState(() => _permissionProblem = null);
        await _identify(result.photo!.path);
      case CameraCaptureStatus.cancelled:
        _showMessage('Capture cancelled.');
      case CameraCaptureStatus.permissionDenied:
      case CameraCaptureStatus.permissionPermanentlyDenied:
        setState(() => _permissionProblem = result.status);
      case CameraCaptureStatus.failed:
        _showMessage('Could not capture the photo. Please try again.');
    }
  }

  Future<void> _importFromGallery() async {
    if (_busy) return;
    setState(() => _busy = true);
    _deps.player.pause();

    final result = await _deps.gallery.importImage();
    if (!mounted) return;
    setState(() => _busy = false);

    switch (result.status) {
      case GalleryImportStatus.selected:
        await _identify(result.image!.path);
      case GalleryImportStatus.cancelled:
        break;
      case GalleryImportStatus.failed:
        _showMessage('Could not import the image. Please try again.');
    }
  }

  Future<void> _identify(String? photoPath) async {
    final outcome = await AppNav.identify(context, imagePath: photoPath);
    if (!mounted || outcome == null) return;

    switch (outcome.action) {
      case ScanFlowAction.matched:
        _showResult(outcome.album!, photoPath);
      case ScanFlowAction.retake:
        await _capture();
      case ScanFlowAction.searchManually:
        await _search(afterFailedScan: true);
    }
  }

  Future<void> _search({bool afterFailedScan = false}) async {
    _deps.player.pause();
    final album = await AppNav.search(
      context,
      afterFailedScan: afterFailedScan,
    );
    if (!mounted || album == null) return;
    _showResult(album, null);
  }

  Future<void> _openHistory() async {
    if (!_deps.auth.isSignedIn) {
      await showSignInPrompt(
        context,
        title: 'Sign in to keep your history',
        message:
            'Your scans and searches are saved to your account. '
            'Scanning and previews stay available without one.',
      );
      return;
    }
    final album = await showHistorySheet(context);
    if (!mounted || album == null) return;
    _showResult(album, null);
  }

  void _showResult(Album album, String? photoPath) {
    final player = _deps.player..stop();
    setState(() => _result = _ScanResult(album, photoPath));
    final top = album.topTracks;
    if (_deps.settings.autoplayTopTrack && top.isNotEmpty) {
      player.play(album, top.first);
    }
  }

  void _clearResult() {
    if (_result == null) return;
    _deps.player.stop();
    setState(() => _result = null);
  }

  Future<void> _openSettings() async {
    var opened = false;
    try {
      opened = await _deps.camera.openSettings();
    } on PlatformException {
      opened = false;
    }
    if (!mounted) return;
    _showMessage(
      opened
          ? 'After returning from settings, tap the shutter to take a photo.'
          : 'Could not open settings. Please open them from Android settings.',
    );
  }

  void _showMessage(String message) {
    showAppSnackBar(ScaffoldMessenger.of(context), message);
  }

  @override
  Widget build(BuildContext context) {
    final permissionOff = _permissionProblem != null;
    return Scaffold(
      backgroundColor: permissionOff ? Colors.white : AppColors.camera,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: _ProfileButton(light: permissionOff),
              ),
            ),
            Expanded(
              child: permissionOff
                  ? _buildPermissionOff()
                  : _buildViewfinder(),
            ),
            CaptureCard(
              busy: _busy,
              light: permissionOff,
              onGallery: _importFromGallery,
              onShutter: _capture,
              onLibrary: () => AppNav.switchTab(context, AppTab.library),
            ),
          ],
        ),
      ),
      bottomNavigationBar: ScanTaskbar(
        onHistory: _openHistory,
        onScan: _clearResult,
        onSearch: _search,
      ),
    );
  }

  Widget _buildViewfinder() {
    final result = _result;
    return LayoutBuilder(
      builder: (context, constraints) {
        return Column(
          children: [
            Expanded(child: _FramingArea(result: result)),
            if (result != null)
              ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: constraints.maxHeight * 0.85,
                ),
                child: ResultCard(
                  key: ObjectKey(result),
                  album: result.album,
                  onAdd: () => startSaveAlbum(
                    context,
                    result.album,
                    ListKind.collection,
                  ),
                  onWishlist: () =>
                      startSaveAlbum(context, result.album, ListKind.wishlist),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildPermissionOff() {
    final permanentlyDenied =
        _permissionProblem == CameraCaptureStatus.permissionPermanentlyDenied;
    return EmptyState(
      icon: Icons.photo_camera_outlined,
      title: 'Camera access is off',
      message: permanentlyDenied
          ? 'Allow camera access in your phone settings to scan album '
                'covers. You can still import a photo or search manually.'
          : 'JamSCAN uses the camera to photograph album covers. You can '
                'still import a photo or search manually.',
      actions: [
        if (permanentlyDenied)
          FilledButton(
            onPressed: _openSettings,
            child: const Text('Open settings'),
          )
        else
          FilledButton(
            onPressed: _capture,
            child: const Text('Allow camera access'),
          ),
        OutlinedButton.icon(
          onPressed: _search,
          icon: const Icon(Icons.search),
          label: const Text('Search manually'),
        ),
      ],
    );
  }
}

class _ProfileButton extends StatelessWidget {
  const _ProfileButton({required this.light});

  final bool light;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: const Key('scan.profile'),
      tooltip: 'Profile',
      onPressed: () => AppNav.switchTab(context, AppTab.profile),
      icon: Icon(
        Icons.person_outline,
        color: light ? AppColors.inkDeep : Colors.white,
      ),
      style: IconButton.styleFrom(
        backgroundColor: light ? AppColors.surfaceMuted : AppColors.cameraChrome,
        fixedSize: const Size(52, 52),
      ),
    );
  }
}

/// Viewfinder with corner brackets, the captured photo once a match is
/// found, and the hint pill underneath. Shrinks away when the result card
/// needs the space.
class _FramingArea extends StatelessWidget {
  const _FramingArea({required this.result});

  final _ScanResult? result;

  @override
  Widget build(BuildContext context) {
    final result = this.result;
    return LayoutBuilder(
      builder: (context, constraints) {
        final available = constraints.maxHeight;
        if (available < 72) {
          return const SizedBox.shrink();
        }
        final showHint = available > 140;
        final side = math
            .min(constraints.maxWidth - 64, available - (showHint ? 84 : 24))
            .clamp(48.0, 300.0);

        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ViewfinderFrame(
                inset: 10,
                child: SizedBox.square(
                  dimension: side,
                  child: result == null
                      ? const _LiveFeedPlaceholder()
                      : CoverPhoto(
                          path: result.photoPath,
                          album: result.album,
                          size: side,
                        ),
                ),
              ),
              if (showHint) ...[
                const SizedBox(height: 14),
                result == null
                    ? const _HintPill(
                        label: 'Fit the album cover inside the frame',
                      )
                    : const _HintPill(label: 'Match found', icon: Icons.check),
              ],
            ],
          ),
        );
      },
    );
  }
}

class _LiveFeedPlaceholder extends StatelessWidget {
  const _LiveFeedPlaceholder();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Text(
          'Tap the shutter to photograph a cover',
          textAlign: TextAlign.center,
          style: TextStyle(color: AppColors.onDarkSecondary, fontSize: 15),
        ),
      ),
    );
  }
}

class _HintPill extends StatelessWidget {
  const _HintPill({required this.label, this.icon});

  final String label;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.cameraChrome,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, color: Colors.white, size: 18),
            const SizedBox(width: 8),
          ],
          Text(
            label,
            style: const TextStyle(color: Colors.white, fontSize: 15),
          ),
        ],
      ),
    );
  }
}
