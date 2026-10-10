import '../mock/mock_catalog.dart';
import '../models/album.dart';

/// Progress steps shown on the "Identifying album" screen.
enum RecognitionStep {
  checkingPhoto,
  matchingCover,
  loadingPreviews,
  loadingDetails,
}

enum RecognitionOutcomeKind { match, candidates, notRecognised, tooBlurry }

class RecognitionCandidate {
  const RecognitionCandidate(this.album, this.confidence);

  final Album album;

  /// Between 0 and 1.
  final double confidence;
}

class RecognitionOutcome {
  const RecognitionOutcome(this.kind, {this.candidates = const []});

  final RecognitionOutcomeKind kind;

  /// Best match first. One entry for [RecognitionOutcomeKind.match].
  final List<RecognitionCandidate> candidates;
}

/// Identifies an album from a cover photo.
abstract class RecognitionService {
  /// Identifies the cover at [imagePath].
  ///
  /// [onStep] is called as each step starts. When [skipQualityCheck] is true
  /// the photo is used even if it looks blurry or dark ("Use anyway").
  Future<RecognitionOutcome> identify({
    String? imagePath,
    bool skipQualityCheck = false,
    void Function(RecognitionStep step)? onStep,
  });
}

/// Stand-in until visual search is wired up.
///
/// Each call returns the next outcome from [script], so every screen of the
/// scan flow can be reached in the app. The default script is: match,
/// several candidates, not recognised, too blurry.
class MockRecognitionService implements RecognitionService {
  MockRecognitionService({
    List<RecognitionOutcomeKind>? script,
    this.stepDelay = const Duration(milliseconds: 600),
  }) : _script =
           script ??
           const [
             RecognitionOutcomeKind.match,
             RecognitionOutcomeKind.candidates,
             RecognitionOutcomeKind.notRecognised,
             RecognitionOutcomeKind.tooBlurry,
           ];

  final List<RecognitionOutcomeKind> _script;
  final Duration stepDelay;

  int _calls = 0;
  int _matches = 0;

  static const List<Album> _matchRotation = [
    MockCatalog.kindOfBlue,
    MockCatalog.rumours,
    MockCatalog.discovery,
    MockCatalog.liveAtTheGarage,
  ];

  @override
  Future<RecognitionOutcome> identify({
    String? imagePath,
    bool skipQualityCheck = false,
    void Function(RecognitionStep step)? onStep,
  }) async {
    var kind = _script[_calls % _script.length];
    _calls++;
    if (skipQualityCheck && kind == RecognitionOutcomeKind.tooBlurry) {
      kind = RecognitionOutcomeKind.match;
    }

    onStep?.call(RecognitionStep.checkingPhoto);
    await Future<void>.delayed(stepDelay);
    if (kind == RecognitionOutcomeKind.tooBlurry) {
      return const RecognitionOutcome(RecognitionOutcomeKind.tooBlurry);
    }

    onStep?.call(RecognitionStep.matchingCover);
    await Future<void>.delayed(stepDelay);

    switch (kind) {
      case RecognitionOutcomeKind.notRecognised:
        return const RecognitionOutcome(RecognitionOutcomeKind.notRecognised);
      case RecognitionOutcomeKind.candidates:
        return const RecognitionOutcome(
          RecognitionOutcomeKind.candidates,
          candidates: [
            RecognitionCandidate(MockCatalog.kindOfBlue, 0.74),
            RecognitionCandidate(MockCatalog.kindOfBlueReissue, 0.68),
            RecognitionCandidate(MockCatalog.blueTrain, 0.41),
          ],
        );
      case RecognitionOutcomeKind.match:
      case RecognitionOutcomeKind.tooBlurry:
        break;
    }

    onStep?.call(RecognitionStep.loadingPreviews);
    await Future<void>.delayed(stepDelay);
    onStep?.call(RecognitionStep.loadingDetails);
    await Future<void>.delayed(stepDelay);

    final album = _matchRotation[_matches % _matchRotation.length];
    _matches++;
    return RecognitionOutcome(
      RecognitionOutcomeKind.match,
      candidates: [RecognitionCandidate(album, 0.93)],
    );
  }
}
