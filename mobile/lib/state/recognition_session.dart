import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/album.dart';
import '../services/recognition_api.dart';
import '../services/release_details_service.dart';
import '../vision/cover_crop.dart';

/// Where a recognition request came from.
enum JobSource {
  /// Picked automatically from the live camera (S2-10).
  live,

  /// A photo the user took or imported; served before live requests.
  manual,
}

/// Recognition states from the Sprint 1 review (section 4.4.3). The
/// "Detected" state belongs to covers that are tracked but not captured yet,
/// so the scan page takes it from the live scanner rather than from a job.
enum JobState {
  /// Waiting for a free recognition slot.
  queued,

  /// Taking a slot; the image is being prepared for upload.
  processing,

  /// The backend is searching for the album.
  identifying,

  /// Identified; album details are being fetched.
  retrievingDetails,

  /// Recognised: [RecognitionJob.album] is set.
  done,

  /// Several plausible albums: the user picks from
  /// [RecognitionJob.candidates].
  needsReview,

  /// Not identified: see [RecognitionJob.failure].
  failed,
}

enum JobFailure { notRecognised, poorQuality, unavailable }

/// One album being recognised.
class RecognitionJob {
  RecognitionJob._(
    this.id,
    this.source,
    this.jpeg,
    this.hash, {
    this.skipQualityCheck = false,
  });

  final int id;
  final JobSource source;

  /// The cover crop sent for recognition; also shown as the card image.
  final Uint8List jpeg;

  /// [differenceHash] of the crop.
  final int hash;
  final bool skipQualityCheck;

  JobState _state = JobState.queued;
  JobState get state => _state;

  List<ApiCandidate> _candidates = const [];
  List<ApiCandidate> get candidates => _candidates;

  Album? _album;
  Album? get album => _album;

  JobFailure? _failure;
  JobFailure? get failure => _failure;

  final _finished = Completer<RecognitionJob>();

  /// Completes when the job is done, needs review or failed.
  Future<RecognitionJob> get finished => _finished.future;

  /// Holds one of the recognition slots.
  bool get isActive =>
      _state == JobState.processing ||
      _state == JobState.identifying ||
      _state == JobState.retrievingDetails;

  bool get isFinished =>
      _state == JobState.done ||
      _state == JobState.needsReview ||
      _state == JobState.failed;
}

/// The recognition jobs of one scanning session (S2-11).
///
/// - At most [maxActive] jobs run at once (FR-06); the rest wait in a queue
///   (FR-07), manual requests first, then live ones in arrival order.
/// - A job keeps going after its cover leaves the camera view (FR-08): it
///   only needs the captured crop.
/// - Finished jobs free their slot but stay listed until dismissed or the
///   app closes (FR-09, FR-10).
/// - The same album is not recognised twice: a live crop whose hash is
///   within [duplicateBits] of an earlier one is ignored, and a second
///   result for an album already found is merged into the first.
class RecognitionSession extends ChangeNotifier {
  RecognitionSession({
    required this.api,
    this.details = const BasicReleaseDetails(),
    this.maxActive = 3,
    this.duplicateBits = 10,
  });

  final RecognitionApi api;
  final ReleaseDetailsService details;
  final int maxActive;
  final int duplicateBits;

  final List<RecognitionJob> _jobs = [];
  int _nextId = 1;
  bool _disposed = false;

  List<RecognitionJob> get jobs => List.unmodifiable(_jobs);

  /// Jobs from the live camera, oldest first, for the scan page.
  List<RecognitionJob> get liveJobs =>
      _jobs.where((j) => j.source == JobSource.live).toList(growable: false);

  int get activeCount => _jobs.where((j) => j.isActive).length;

  /// Queues a cover captured by the live camera. Returns `null` when the
  /// same cover was already submitted in this session.
  RecognitionJob? addLiveCapture(Uint8List jpeg, int hash) {
    final seen = _jobs.any(
      (j) =>
          j.source == JobSource.live &&
          j.state != JobState.failed &&
          hammingDistance(j.hash, hash) <= duplicateBits,
    );
    if (seen) return null;
    return _add(RecognitionJob._(_nextId++, JobSource.live, jpeg, hash));
  }

  /// Queues a photo the user took or imported, ahead of live requests.
  RecognitionJob addManual(
    Uint8List jpeg,
    int hash, {
    bool skipQualityCheck = false,
  }) {
    return _add(
      RecognitionJob._(
        _nextId++,
        JobSource.manual,
        jpeg,
        hash,
        skipQualityCheck: skipQualityCheck,
      ),
    );
  }

  RecognitionJob _add(RecognitionJob job) {
    _jobs.add(job);
    _notify();
    _pump();
    return job;
  }

  /// The user picked [choice] for a job that needed review.
  Future<Album> resolve(RecognitionJob job, ApiCandidate choice) async {
    job
      .._state = JobState.retrievingDetails
      .._candidates = [choice];
    _notify();
    job
      .._album = await _albumFor(choice)
      .._state = JobState.done;
    _notify();
    return job._album!;
  }

  void dismiss(RecognitionJob job) {
    if (job.isActive) return;
    _jobs.remove(job);
    _notify();
  }

  /// Ends the session: forgets every job that is not running.
  void clearFinished() {
    _jobs.removeWhere((j) => !j.isActive && j.state != JobState.queued);
    _notify();
  }

  void _pump() {
    while (!_disposed && activeCount < maxActive) {
      final next =
          _firstQueued(JobSource.manual) ?? _firstQueued(JobSource.live);
      if (next == null) return;
      next._state = JobState.processing;
      unawaited(_run(next));
    }
  }

  RecognitionJob? _firstQueued(JobSource source) {
    for (final job in _jobs) {
      if (job.source == source && job.state == JobState.queued) return job;
    }
    return null;
  }

  Future<void> _run(RecognitionJob job) async {
    _notify();
    // The crop is already flattened and encoded; this step yields once so
    // the state is visible before the upload starts.
    await Future<void>.delayed(Duration.zero);
    job._state = JobState.identifying;
    _notify();
    try {
      final result = await api.recognize(
        job.jpeg,
        skipQualityCheck: job.skipQualityCheck,
      );
      job._candidates = result.candidates;
      switch (result.decision) {
        case ApiDecision.match:
          job._state = JobState.retrievingDetails;
          _notify();
          job._album = await _albumFor(result.candidates.first);
          job._state = JobState.done;
          _mergeDuplicate(job);
        case ApiDecision.needsReview:
          job._state = JobState.needsReview;
        case ApiDecision.noMatch:
          _fail(job, JobFailure.notRecognised);
        case ApiDecision.poorQuality:
          _fail(job, JobFailure.poorQuality);
      }
    } on Exception {
      // Network errors, timeouts and server errors all mean "try again".
      _fail(job, JobFailure.unavailable);
    }
    job._finished.complete(job);
    _notify();
    _pump();
  }

  Future<Album> _albumFor(ApiCandidate release) async {
    try {
      return await details.details(release);
    } on Exception {
      // Details are a bonus: the album is identified even if they fail.
      return albumFromCandidate(release);
    }
  }

  void _fail(RecognitionJob job, JobFailure failure) {
    job
      .._state = JobState.failed
      .._failure = failure;
  }

  /// Drops a live result for an album that an earlier live job already
  /// found, keeping the earlier card.
  void _mergeDuplicate(RecognitionJob job) {
    if (job.source != JobSource.live) return;
    final duplicate = _jobs.any(
      (j) =>
          j != job &&
          j.source == JobSource.live &&
          j.state == JobState.done &&
          j.album?.id == job.album?.id,
    );
    if (duplicate) _jobs.remove(job);
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    super.dispose();
  }
}
