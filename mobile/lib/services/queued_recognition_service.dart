import 'dart:io';
import 'dart:isolate';
import 'dart:typed_data';

import '../models/album.dart';
import '../state/recognition_session.dart';
import '../vision/still_cover.dart';
import 'recognition_api.dart';
import 'recognition_service.dart';
import 'release_details_service.dart';

/// [RecognitionService] for photos the user takes or imports: prepares the
/// photo like the live camera does (find the cover, flatten it), then runs
/// it through the [RecognitionSession] queue with manual priority, so it
/// shares the three recognition slots with live scanning.
class QueuedRecognitionService implements RecognitionService {
  QueuedRecognitionService(
    this.session, {
    this.details = const BasicReleaseDetails(),
    Future<PreparedCover> Function(Uint8List bytes)? prepare,
  }) : _prepare = prepare ?? _prepareInBackground;

  final RecognitionSession session;
  final ReleaseDetailsService details;
  final Future<PreparedCover> Function(Uint8List bytes) _prepare;

  static Future<PreparedCover> _prepareInBackground(Uint8List bytes) =>
      Isolate.run(() => prepareStillCover(bytes));

  @override
  Future<RecognitionOutcome> identify({
    String? imagePath,
    bool skipQualityCheck = false,
    void Function(RecognitionStep step)? onStep,
  }) async {
    onStep?.call(RecognitionStep.checkingPhoto);
    if (imagePath == null) {
      return const RecognitionOutcome(RecognitionOutcomeKind.notRecognised);
    }
    final PreparedCover prepared;
    try {
      prepared = await _prepare(await File(imagePath).readAsBytes());
    } on Exception {
      return const RecognitionOutcome(RecognitionOutcomeKind.notRecognised);
    }

    final job = session.addManual(
      prepared.jpeg,
      prepared.hash,
      skipQualityCheck: skipQualityCheck,
    );
    void reportStep() {
      switch (job.state) {
        case JobState.identifying:
          onStep?.call(RecognitionStep.matchingCover);
        case JobState.retrievingDetails:
          onStep?.call(RecognitionStep.loadingDetails);
        case _:
          break;
      }
    }

    session.addListener(reportStep);
    try {
      await job.finished;
    } finally {
      session.removeListener(reportStep);
    }
    // The scan flow shows this result itself; it does not belong in the
    // live results list.
    session.dismiss(job);

    switch (job.state) {
      case JobState.done:
        return RecognitionOutcome(
          RecognitionOutcomeKind.match,
          candidates: [
            RecognitionCandidate(job.album!, job.candidates.first.score),
          ],
        );
      case JobState.needsReview:
        return RecognitionOutcome(
          RecognitionOutcomeKind.candidates,
          candidates: [
            for (final c in job.candidates)
              RecognitionCandidate(await _albumFor(c), c.score),
          ],
        );
      case _:
        return RecognitionOutcome(
          job.failure == JobFailure.poorQuality
              ? RecognitionOutcomeKind.tooBlurry
              : RecognitionOutcomeKind.notRecognised,
        );
    }
  }

  Future<Album> _albumFor(ApiCandidate candidate) async {
    try {
      return await details.details(candidate);
    } on Exception {
      return albumFromCandidate(candidate);
    }
  }
}
