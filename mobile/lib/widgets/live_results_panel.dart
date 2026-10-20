import 'package:flutter/material.dart';

import '../models/album.dart';
import '../services/live_scanner.dart';
import '../state/recognition_session.dart';
import '../vision/frame_analyzer.dart';
import '../vision/frame_quality.dart';

/// Height of the results strip above the guide square. The scan page keeps
/// this space while the live camera runs, so the strip never covers an
/// album inside the guide square and the square does not move.
const liveResultsStripHeight = 60.0;

/// Compact recognition status for the live camera (FR-05, FR-09, FR-10):
/// one horizontal row of chips, newest first, scrolling sideways when full.
/// Covers still being lined up share one "Detected" chip; recognised ones
/// become a small card that opens the album.
///
/// Functional layout for S2-11; visual styling belongs to the UI work.
class LiveResultsPanel extends StatelessWidget {
  const LiveResultsPanel({
    super.key,
    required this.session,
    required this.scanner,
    required this.onOpen,
    required this.onReview,
  });

  final RecognitionSession session;
  final LiveScanner scanner;
  final ValueChanged<Album> onOpen;
  final ValueChanged<RecognitionJob> onReview;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([session, scanner]),
      builder: (context, _) {
        final detected = scanner.covers
            .where((c) => !c.captured && !c.touchesBorder)
            .toList();
        final chips = <Widget>[
          if (detected.isNotEmpty)
            _StatusChip(
              key: const ValueKey('detected'),
              label: _detectedLabel(detected),
              icon: Icons.crop_free,
            ),
          for (final job in session.liveJobs.reversed) _jobChip(job),
        ];
        if (chips.isEmpty) return const SizedBox.shrink();
        return SizedBox(
          key: const Key('scan.liveResults'),
          height: liveResultsStripHeight,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            itemCount: chips.length,
            separatorBuilder: (_, _) => const SizedBox(width: 8),
            itemBuilder: (_, i) => Center(child: chips[i]),
          ),
        );
      },
    );
  }

  Widget _jobChip(RecognitionJob job) {
    final key = ValueKey('job-${job.id}');
    return switch (job.state) {
      JobState.queued => _StatusChip(key: key, label: 'Queued', busy: false),
      JobState.processing => _StatusChip(key: key, label: 'Processing'),
      JobState.identifying => _StatusChip(key: key, label: 'Identifying'),
      JobState.retrievingDetails => _StatusChip(
        key: key,
        label: 'Retrieving details',
      ),
      JobState.done => _ResultChip(
        key: key,
        job: job,
        onTap: () => onOpen(job.album!),
        onDismiss: () => session.dismiss(job),
      ),
      JobState.needsReview => _StatusChip(
        key: key,
        label: 'Needs review',
        icon: Icons.help_outline,
        onTap: () => onReview(job),
        onDismiss: () => session.dismiss(job),
      ),
      JobState.failed => _StatusChip(
        key: key,
        label: switch (job.failure) {
          JobFailure.poorQuality => 'Unclear photo',
          JobFailure.unavailable => 'Service unavailable',
          _ => 'Not identified',
        },
        icon: Icons.error_outline,
        onDismiss: () => session.dismiss(job),
      ),
    };
  }
}

/// `Detected · hold steady` for one cover, `3 detected · move closer` for
/// several (the first hint shown).
String _detectedLabel(List<CoverSnapshot> covers) {
  final hint = covers
      .map((c) => _hintWords(c.hint))
      .firstWhere((h) => h != null, orElse: () => null);
  final base = covers.length == 1 ? 'Detected' : '${covers.length} detected';
  return hint == null ? base : '$base · $hint';
}

String? _hintWords(CaptureHint? hint) => switch (hint) {
  CaptureHint.holdSteady => 'hold steady',
  CaptureHint.tooDark => 'too dark',
  CaptureHint.glare => 'avoid glare',
  CaptureHint.blurry => 'blurry',
  CaptureHint.moveCloser => 'move closer',
  null => null,
};

const _chipColour = Color(0xE6202020);

class _StatusChip extends StatelessWidget {
  const _StatusChip({
    super.key,
    required this.label,
    this.icon,
    this.busy = true,
    this.onTap,
    this.onDismiss,
  });

  final String label;
  final IconData? icon;
  final bool busy;
  final VoidCallback? onTap;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    // Narrow phones: long labels shorten with "…" so the dismiss button
    // always stays on screen.
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 240),
      child: Material(
        color: _chipColour,
        borderRadius: BorderRadius.circular(20),
        child: InkWell(
          borderRadius: BorderRadius.circular(20),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(12, 8, onDismiss == null ? 14 : 4, 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (icon != null)
                  Icon(icon, color: Colors.white, size: 16)
                else if (busy)
                  const SizedBox.square(
                    dimension: 14,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                else
                  const Icon(Icons.schedule, color: Colors.white, size: 16),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white, fontSize: 13),
                  ),
                ),
                if (onDismiss != null) _DismissButton(onPressed: onDismiss!),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ResultChip extends StatelessWidget {
  const _ResultChip({
    super.key,
    required this.job,
    required this.onTap,
    required this.onDismiss,
  });

  final RecognitionJob job;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final album = job.album!;
    return ConstrainedBox(
      constraints: const BoxConstraints(maxWidth: 210),
      child: Material(
        color: _chipColour,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(4, 4, 2, 4),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.memory(
                    job.jpeg,
                    width: 40,
                    height: 40,
                    fit: BoxFit.cover,
                    gaplessPlayback: true,
                  ),
                ),
                const SizedBox(width: 8),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        album.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                        ),
                      ),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Done',
                            style: TextStyle(
                              color: Color(0xFF81C784),
                              fontSize: 11.5,
                            ),
                          ),
                          Flexible(
                            child: Text(
                              ' · ${album.artist}',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11.5,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                _DismissButton(onPressed: onDismiss),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DismissButton extends StatelessWidget {
  const _DismissButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Dismiss',
      onPressed: onPressed,
      visualDensity: VisualDensity.compact,
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints.tightFor(width: 28, height: 28),
      icon: const Icon(Icons.close, color: Colors.white70, size: 16),
    );
  }
}
