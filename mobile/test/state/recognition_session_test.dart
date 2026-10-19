import 'package:flutter_test/flutter_test.dart';
import 'package:jamscan/services/recognition_api.dart';
import 'package:jamscan/state/recognition_session.dart';

import '../support/fake_recognition_api.dart';

/// Lets queued microtasks and zero-length timers run.
Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 1));

void main() {
  late FakeRecognitionApi api;
  late RecognitionSession session;

  setUp(() {
    api = FakeRecognitionApi();
    session = RecognitionSession(api: api);
  });

  tearDown(() => session.dispose());

  test('runs at most three jobs and queues the rest', () async {
    final jobs = [
      for (var i = 0; i < 5; i++)
        session.addLiveCapture(bytes(i), hashNumber(i))!,
    ];
    await settle();

    expect(api.calls, 3);
    expect(session.activeCount, 3);
    expect(jobs.map((j) => j.state), [
      JobState.identifying,
      JobState.identifying,
      JobState.identifying,
      JobState.queued,
      JobState.queued,
    ]);

    api.answer(matchOf('a'));
    await settle();

    expect(jobs[0].state, JobState.done);
    expect(jobs[3].state, JobState.identifying);
    expect(jobs[4].state, JobState.queued);
    expect(session.activeCount, 3);
  });

  test('a manual photo goes ahead of queued live captures', () async {
    final live = [
      for (var i = 0; i < 4; i++)
        session.addLiveCapture(bytes(i), hashNumber(i))!,
    ];
    final manual = session.addManual(bytes(9), hashNumber(5));
    await settle();
    expect(manual.state, JobState.queued);
    expect(live[3].state, JobState.queued);

    api.answer(matchOf('a'));
    await settle();

    expect(manual.state, JobState.identifying);
    expect(live[3].state, JobState.queued);
    expect(session.activeCount, 3);
  });

  test('goes through identifying and retrieving details to done', () async {
    final states = <JobState>[];
    final job = session.addLiveCapture(bytes(0), hashNumber(0))!;
    session.addListener(() => states.add(job.state));
    await settle();

    api.answer(matchOf('12643712'));
    final finished = await job.finished;

    expect(
      states.toSet(),
      containsAll([
        JobState.identifying,
        JobState.retrievingDetails,
        JobState.done,
      ]),
    );
    expect(finished.album!.id, '12643712');
    expect(finished.album!.title, 'Album 12643712');
    expect(session.activeCount, 0);
  });

  test('uncertain results wait for the user to choose', () async {
    final job = session.addLiveCapture(bytes(0), hashNumber(0))!;
    await settle();

    api.answer(
      ApiRecognition(ApiDecision.needsReview, [
        candidate('1', score: 0.7),
        candidate('2', score: 0.68),
      ]),
    );
    await job.finished;
    expect(job.state, JobState.needsReview);
    expect(job.candidates, hasLength(2));
    expect(session.activeCount, 0);

    final album = await session.resolve(job, job.candidates[1]);

    expect(album.id, '2');
    expect(job.state, JobState.done);
  });

  test('failures are reported and free the slot', () async {
    final noMatch = session.addLiveCapture(bytes(0), hashNumber(0))!;
    final blurry = session.addLiveCapture(bytes(1), hashNumber(1))!;
    final offline = session.addLiveCapture(bytes(2), hashNumber(2))!;
    await settle();

    api
      ..answer(const ApiRecognition(ApiDecision.noMatch, []))
      ..answer(const ApiRecognition(ApiDecision.poorQuality, []))
      ..fail();
    await Future.wait([noMatch.finished, blurry.finished, offline.finished]);

    expect(noMatch.failure, JobFailure.notRecognised);
    expect(blurry.failure, JobFailure.poorQuality);
    expect(offline.failure, JobFailure.unavailable);
    expect(session.activeCount, 0);
  });

  test('the same cover is not submitted twice', () async {
    final first = session.addLiveCapture(bytes(0), 0x00FF00FF00FF00FF);
    // Five bits differ: another photo of the same cover.
    final again = session.addLiveCapture(bytes(1), 0x00FF00FF00FF001F);
    final other = session.addLiveCapture(bytes(2), hashNumber(5));

    expect(first, isNotNull);
    expect(again, isNull);
    expect(other, isNotNull);

    // After a failure, the same cover may be tried again.
    await settle();
    api.fail();
    await first!.finished;
    expect(session.addLiveCapture(bytes(3), 0x00FF00FF00FF00FF), isNotNull);
  });

  test('an album the backend did not know is not sent again', () async {
    final unknown = session.addLiveCapture(bytes(0), hashNumber(3))!;
    await settle();
    api.answer(const ApiRecognition(ApiDecision.noMatch, []));
    await unknown.finished;

    expect(session.addLiveCapture(bytes(1), hashNumber(3)), isNull);
  });

  test('an unclear photo of a cover may be retried', () async {
    final blurry = session.addLiveCapture(bytes(0), hashNumber(4))!;
    await settle();
    api.answer(const ApiRecognition(ApiDecision.poorQuality, []));
    await blurry.finished;

    expect(session.addLiveCapture(bytes(1), hashNumber(4)), isNotNull);
  });

  test('a second result for the same album keeps one card', () async {
    final a = session.addLiveCapture(bytes(0), hashNumber(0))!;
    final b = session.addLiveCapture(bytes(1), hashNumber(1))!;
    await settle();

    api
      ..answer(matchOf('42'))
      ..answer(matchOf('42'));
    await Future.wait([a.finished, b.finished]);

    expect(session.liveJobs, [a]);
  });

  test('results stay until dismissed', () async {
    final job = session.addLiveCapture(bytes(0), hashNumber(0))!;
    await settle();
    api.answer(matchOf('1'));
    await job.finished;
    expect(session.liveJobs, [job]);

    session.dismiss(job);

    expect(session.liveJobs, isEmpty);
  });

  test('running jobs cannot be dismissed or cleared', () async {
    final running = session.addLiveCapture(bytes(0), hashNumber(0))!;
    final done = session.addLiveCapture(bytes(1), hashNumber(1))!;
    await settle();
    api
      ..answer(matchOf('1'))
      ..answer(matchOf('2'));
    await running.finished;
    await done.finished;
    final still = session.addLiveCapture(bytes(2), hashNumber(2))!;
    await settle();

    session
      ..dismiss(still)
      ..clearFinished();

    expect(session.liveJobs, [still]);
  });
}
