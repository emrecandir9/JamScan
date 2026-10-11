import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../models/album.dart';
import '../../routing/app_routes.dart';
import '../../services/recognition_service.dart';
import '../../theme/app_theme.dart';
import '../../widgets/album_art.dart';

enum ScanFlowAction { matched, retake, searchManually }

/// What the camera page should do after the scan flow closes.
/// The route pops with `null` for "Stop scan" and "Back to camera".
class ScanFlowResult {
  const ScanFlowResult.matched(Album this.album)
    : action = ScanFlowAction.matched;

  const ScanFlowResult.retake() : action = ScanFlowAction.retake, album = null;

  const ScanFlowResult.searchManually()
    : action = ScanFlowAction.searchManually,
      album = null;

  final ScanFlowAction action;
  final Album? album;
}

enum _Phase { identifying, tooBlurry, candidates, notRecognised }

/// Identifying an album after a photo was taken or imported.
///
/// 05 loading, 04 retake prompt, 06 candidate selection, 07 not recognised.
class ScanFlowScreen extends StatefulWidget {
  const ScanFlowScreen({super.key, required this.args});

  final ScanFlowArgs args;

  @override
  State<ScanFlowScreen> createState() => _ScanFlowScreenState();
}

class _ScanFlowScreenState extends State<ScanFlowScreen> {
  _Phase _phase = _Phase.identifying;
  RecognitionStep _step = RecognitionStep.checkingPhoto;
  List<RecognitionCandidate> _candidates = const [];

  @override
  void initState() {
    super.initState();
    // Start after the first frame so progress updates can call setState.
    scheduleMicrotask(_run);
  }

  Future<void> _run({bool skipQualityCheck = false}) async {
    final deps = AppScope.of(context);
    final outcome = await deps.recognition.identify(
      imagePath: widget.args.imagePath,
      skipQualityCheck: skipQualityCheck,
      onStep: (step) {
        if (mounted && step != _step) {
          setState(() => _step = step);
        }
      },
    );
    if (!mounted) return;

    switch (outcome.kind) {
      case RecognitionOutcomeKind.match:
        _finish(outcome.candidates.first.album);
      case RecognitionOutcomeKind.candidates:
        setState(() {
          _phase = _Phase.candidates;
          _candidates = outcome.candidates;
        });
      case RecognitionOutcomeKind.notRecognised:
        setState(() => _phase = _Phase.notRecognised);
      case RecognitionOutcomeKind.tooBlurry:
        setState(() => _phase = _Phase.tooBlurry);
    }
  }

  void _useAnyway() {
    setState(() {
      _phase = _Phase.identifying;
      _step = RecognitionStep.checkingPhoto;
    });
    _run(skipQualityCheck: true);
  }

  void _finish(Album album) {
    AppScope.of(context).history.recordScan(album);
    Navigator.of(context).pop(ScanFlowResult.matched(album));
  }

  void _close([ScanFlowResult? result]) {
    Navigator.of(context).pop(result);
  }

  @override
  Widget build(BuildContext context) {
    switch (_phase) {
      case _Phase.identifying:
        return _IdentifyingView(
          imagePath: widget.args.imagePath,
          step: _step,
          onStop: _close,
        );
      case _Phase.tooBlurry:
        return _PhotoBackdrop(
          imagePath: widget.args.imagePath,
          panel: _RetakePanel(
            onRetake: () => _close(const ScanFlowResult.retake()),
            onUseAnyway: _useAnyway,
            onSearch: () => _close(const ScanFlowResult.searchManually()),
          ),
        );
      case _Phase.candidates:
        return _PhotoBackdrop(
          imagePath: widget.args.imagePath,
          showClose: true,
          onClose: _close,
          panel: _CandidatesPanel(
            candidates: _candidates,
            onSelect: _finish,
            onSearch: () => _close(const ScanFlowResult.searchManually()),
            onRetake: () => _close(const ScanFlowResult.retake()),
          ),
        );
      case _Phase.notRecognised:
        return _PhotoBackdrop(
          imagePath: widget.args.imagePath,
          panel: _NotRecognisedPanel(
            onSearch: () => _close(const ScanFlowResult.searchManually()),
            onRetake: () => _close(const ScanFlowResult.retake()),
            onBack: _close,
          ),
        );
    }
  }
}

class _IdentifyingView extends StatelessWidget {
  const _IdentifyingView({
    required this.imagePath,
    required this.step,
    required this.onStop,
  });

  final String? imagePath;
  final RecognitionStep step;
  final VoidCallback onStop;

  static const _labels = {
    RecognitionStep.checkingPhoto: 'Photo checked',
    RecognitionStep.matchingCover: 'Matching cover',
    RecognitionStep.loadingPreviews: 'Loading previews',
    RecognitionStep.loadingDetails: 'Loading album details',
  };

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = (step.index + 1) / RecognitionStep.values.length;

    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.all(8),
                child: IconButton(
                  tooltip: 'Stop scan',
                  icon: const Icon(Icons.close),
                  onPressed: onStop,
                ),
              ),
            ),
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 32),
                child: Column(
                  children: [
                    const SizedBox(height: 16),
                    SizedBox.square(
                      dimension: 220,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          Positioned.fill(
                            child: TweenAnimationBuilder<double>(
                              tween: Tween(end: progress),
                              duration: const Duration(milliseconds: 400),
                              builder: (context, value, _) =>
                                  CircularProgressIndicator(
                                    value: value,
                                    strokeWidth: 4,
                                  ),
                            ),
                          ),
                          CoverPhoto(path: imagePath, size: 150),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),
                    Text(
                      'Identifying album…',
                      style: theme.textTheme.headlineSmall,
                    ),
                    const SizedBox(height: 20),
                    for (final value in RecognitionStep.values)
                      _StepRow(
                        label: _labels[value]!,
                        done: value.index < step.index,
                        active: value == step,
                      ),
                  ],
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24),
              child: OutlinedButton(
                onPressed: onStop,
                child: const Text('Stop scan'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  const _StepRow({
    required this.label,
    required this.done,
    required this.active,
  });

  final String label;
  final bool done;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final IconData icon;
    if (done) {
      icon = Icons.check_circle;
    } else if (active) {
      icon = Icons.radio_button_checked;
    } else {
      icon = Icons.radio_button_unchecked;
    }
    final pending = !done && !active;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 7),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: pending ? AppColors.divider : AppColors.ink,
            size: 26,
          ),
          const SizedBox(width: 14),
          SizedBox(
            width: 200,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 17,
                fontWeight: active ? FontWeight.w600 : FontWeight.w400,
                color: pending ? AppColors.textMuted : AppColors.inkDeep,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dimmed captured photo with a white panel docked at the bottom.
class _PhotoBackdrop extends StatelessWidget {
  const _PhotoBackdrop({
    required this.imagePath,
    required this.panel,
    this.showClose = false,
    this.onClose,
  });

  final String? imagePath;
  final Widget panel;
  final bool showClose;
  final VoidCallback? onClose;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.camera,
      body: Column(
        children: [
          Expanded(
            child: SafeArea(
              bottom: false,
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final side = (constraints.maxHeight - 32).clamp(0.0, 220.0);
                  return Stack(
                    children: [
                      Center(
                        child: Opacity(
                          opacity: 0.8,
                          child: CoverPhoto(path: imagePath, size: side),
                        ),
                      ),
                      if (showClose)
                        Positioned(
                          left: 8,
                          top: 8,
                          child: IconButton(
                            tooltip: 'Close',
                            icon: const Icon(Icons.close, color: Colors.white),
                            onPressed: onClose,
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
          Container(
            width: double.infinity,
            decoration: const BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.vertical(
                top: Radius.circular(AppSpacing.sheetRadius),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        decoration: BoxDecoration(
                          color: AppColors.divider,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    panel,
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _RetakePanel extends StatelessWidget {
  const _RetakePanel({
    required this.onRetake,
    required this.onUseAnyway,
    required this.onSearch,
  });

  final VoidCallback onRetake;
  final VoidCallback onUseAnyway;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const Icon(Icons.warning_rounded, size: 28),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Photo too blurry or dark',
                style: theme.textTheme.titleLarge,
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        Text(
          'Hold the phone steady, avoid glare and make sure the whole cover '
          'is in the frame.',
          style: theme.textTheme.bodyLarge?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 24),
        FilledButton(onPressed: onRetake, child: const Text('Retake photo')),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onUseAnyway,
                child: const Text('Use anyway'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextButton(
                onPressed: onSearch,
                child: const Text('Search manually'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _CandidatesPanel extends StatelessWidget {
  const _CandidatesPanel({
    required this.candidates,
    required this.onSelect,
    required this.onSearch,
    required this.onRetake,
  });

  final List<RecognitionCandidate> candidates;
  final ValueChanged<Album> onSelect;
  final VoidCallback onSearch;
  final VoidCallback onRetake;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Which one is it?', style: theme.textTheme.headlineSmall),
        Text('We found a few close matches', style: theme.textTheme.bodyLarge),
        const SizedBox(height: 12),
        for (final candidate in candidates)
          InkWell(
            onTap: () => onSelect(candidate.album),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(
                children: [
                  AlbumArt(album: candidate.album, size: 56),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          candidate.album.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                        Text(
                          candidate.album.artistYearFormat,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surfaceStrong,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      '${(candidate.confidence * 100).round()}% match',
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                  const Icon(Icons.chevron_right),
                ],
              ),
            ),
          ),
        const SizedBox(height: 16),
        OutlinedButton(
          onPressed: onSearch,
          child: const Text('None of these – search manually'),
        ),
        const SizedBox(height: 4),
        TextButton(onPressed: onRetake, child: const Text('Retake photo')),
      ],
    );
  }
}

class _NotRecognisedPanel extends StatelessWidget {
  const _NotRecognisedPanel({
    required this.onSearch,
    required this.onRetake,
    required this.onBack,
  });

  final VoidCallback onSearch;
  final VoidCallback onRetake;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: Container(
            width: 64,
            height: 64,
            decoration: const BoxDecoration(
              color: AppColors.surfaceMuted,
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.search, size: 30),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          "We couldn't identify this album",
          textAlign: TextAlign.center,
          style: theme.textTheme.titleLarge,
        ),
        const SizedBox(height: 8),
        Text(
          'The cover may be damaged, unusual or not in our catalogue yet.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge?.copyWith(
            color: AppColors.textSecondary,
          ),
        ),
        const SizedBox(height: 24),
        FilledButton.icon(
          onPressed: onSearch,
          icon: const Icon(Icons.search),
          label: const Text('Search manually'),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: onRetake,
                child: const Text('Retake photo'),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextButton(
                onPressed: onBack,
                child: const Text('Back to camera'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
