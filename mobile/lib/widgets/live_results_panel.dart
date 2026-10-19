import 'package:flutter/material.dart';

import '../models/album.dart';
import '../services/live_scanner.dart';
import '../state/recognition_session.dart';
import '../vision/frame_quality.dart';

/// Compact recognition status for the live camera (FR-05, FR-09, FR-10):
/// one row per cover, newest first. Covers still being lined up show as
/// "Detected"; recognised ones become a small card that opens the album.
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
        final detected = scanner.covers.where(
          (c) => !c.captured && !c.touchesBorder,
        );
        final rows = <Widget>[
          for (final cover in detected)
            _StatusRow(
              key: ValueKey('detected-${cover.id}'),
              label: _hintLabel(cover.hint) ?? 'Detected',
              icon: Icons.crop_free,
            ),
          for (final job in session.liveJobs.reversed) _jobRow(job),
        ];
        if (rows.isEmpty) return const SizedBox.shrink();
        return ConstrainedBox(
          key: const Key('scan.liveResults'),
          constraints: const BoxConstraints(maxWidth: 230, maxHeight: 320),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                for (final row in rows)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 6),
                    child: row,
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _jobRow(RecognitionJob job) {
    final key = ValueKey('job-${job.id}');
    return switch (job.state) {
      JobState.queued => _StatusRow(key: key, label: 'Queued', busy: false),
      JobState.processing => _StatusRow(key: key, label: 'Processing'),
      JobState.identifying => _StatusRow(key: key, label: 'Identifying'),
      JobState.retrievingDetails => _StatusRow(
        key: key,
        label: 'Retrieving details',
      ),
      JobState.done => _ResultCard(
        key: key,
        job: job,
        onTap: () => onOpen(job.album!),
        onDismiss: () => session.dismiss(job),
      ),
      JobState.needsReview => _StatusRow(
        key: key,
        label: 'Needs review',
        icon: Icons.help_outline,
        onTap: () => onReview(job),
        onDismiss: () => session.dismiss(job),
      ),
      JobState.failed => _StatusRow(
        key: key,
        label: switch (job.failure) {
          JobFailure.poorQuality => 'Failed: unclear photo',
          JobFailure.unavailable => 'Failed: service unavailable',
          _ => 'Failed: not identified',
        },
        icon: Icons.error_outline,
        onDismiss: () => session.dismiss(job),
      ),
    };
  }
}

String? _hintLabel(CaptureHint? hint) => switch (hint) {
  CaptureHint.holdSteady => 'Detected · hold steady',
  CaptureHint.tooDark => 'Detected · too dark',
  CaptureHint.glare => 'Detected · avoid glare',
  CaptureHint.blurry => 'Detected · blurry',
  CaptureHint.moveCloser => 'Detected · move closer',
  null => null,
};

const _panelColour = Color(0xE6202020);

class _StatusRow extends StatelessWidget {
  const _StatusRow({
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
    return Material(
      color: _panelColour,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
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
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
              if (onDismiss != null) _DismissButton(onPressed: onDismiss!),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({
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
    return Material(
      color: _panelColour,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: Image.memory(
                  job.jpeg,
                  width: 44,
                  height: 44,
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
                    Text(
                      album.artist,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 12,
                      ),
                    ),
                    const Text(
                      'Done',
                      style: TextStyle(color: Color(0xFF81C784), fontSize: 11),
                    ),
                  ],
                ),
              ),
              _DismissButton(onPressed: onDismiss),
            ],
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
