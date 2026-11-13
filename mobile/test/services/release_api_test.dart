import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:jamscan/app_scope.dart';
import 'package:jamscan/data/release_repository.dart';
import 'package:jamscan/models/album.dart';
import 'package:jamscan/services/catalog_service.dart';
import 'package:jamscan/services/queued_recognition_service.dart';
import 'package:jamscan/services/recognition_api.dart';
import 'package:jamscan/services/release_api.dart';
import 'package:jamscan/services/release_details_service.dart';
import 'package:jamscan/services/live_scanner.dart';

import '../support/fake_release_api.dart';
import '../support/test_database.dart';

final backend = Uri.parse('http://10.0.2.2:8000/');

http.Response json(Object? body, {int status = 200}) {
  return http.Response(
    jsonEncode(body),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

void main() {
  group('HttpReleaseApi', () {
    test('requests release details by Discogs id', () async {
      late Uri requested;
      final api = HttpReleaseApi(
        backend,
        client: MockClient((request) async {
          requested = request.url;
          return json(kindOfBlueJson());
        }),
      );

      final body = await api.release(kindOfBlueId);

      expect(requested.toString(), 'http://10.0.2.2:8000/releases/1544165');
      expect(body['title'], 'Kind Of Blue');
    });

    test('searches and splits Discogs "Artist - Title" titles', () async {
      late Uri requested;
      final api = HttpReleaseApi(
        backend,
        client: MockClient((request) async {
          requested = request.url;
          return json({
            'results': [
              {
                'discogs_id': 1544165,
                'title': 'Miles Davis - Kind Of Blue',
                'cover_url': 'https://i.discogs.com/kob.jpg',
                'year': 1959,
                'format': 'Vinyl, LP, Album',
              },
              // Hits from a backend without year/format, or without an
              // artist in the title, still parse.
              {'discogs_id': 2, 'title': 'Untitled', 'cover_url': null},
              {'title': 'no id'},
            ],
          });
        }),
      );

      final results = await api.search('kind of blue');

      expect(requested.path, '/releases/search');
      expect(requested.queryParameters, {'query': 'kind of blue'});
      expect(results, hasLength(2));
      expect(results.first.releaseId, '1544165');
      expect(results.first.artist, 'Miles Davis');
      expect(results.first.title, 'Kind Of Blue');
      expect(results.first.year, 1959);
      expect(results.first.format, 'Vinyl, LP, Album');
      expect(results.first.coverUrl, 'https://i.discogs.com/kob.jpg');
      expect(results.last.artist, '');
      expect(results.last.title, 'Untitled');
      expect(results.last.year, isNull);
    });

    test('decodes UTF-8 names', () async {
      final api = HttpReleaseApi(
        backend,
        client: MockClient(
          (_) async => json({
            'results': [
              {'discogs_id': 3, 'title': 'Björk - Début'},
            ],
          }),
        ),
      );

      final result = (await api.search('bjork')).single;

      expect(result.artist, 'Björk');
      expect(result.title, 'Début');
    });

    Future<void> expectFailure(
      MockClient client, {
      int? status,
      Duration timeout = const Duration(seconds: 30),
    }) {
      final api = HttpReleaseApi(backend, client: client, timeout: timeout);
      return expectLater(
        api.release('1'),
        throwsA(
          isA<ReleaseApiException>().having(
            (e) => e.statusCode,
            'statusCode',
            status,
          ),
        ),
      );
    }

    test('HTTP errors, bad JSON, network failures and timeouts fail', () async {
      await expectFailure(
        MockClient((_) async => json({'detail': 'x'}, status: 503)),
        status: 503,
      );
      await expectFailure(
        MockClient((_) async => json({'detail': 'x'}, status: 404)),
        status: 404,
      );
      await expectFailure(MockClient((_) async => http.Response('{', 200)));
      await expectFailure(MockClient((_) async => json([1, 2])));
      await expectFailure(
        MockClient((_) async => throw http.ClientException('refused')),
      );
      await expectFailure(
        MockClient((_) => Completer<http.Response>().future),
        timeout: const Duration(milliseconds: 10),
      );
    });
  });

  group('HttpCatalogService', () {
    test('returns search hits as partial albums with covers', () async {
      final albums = await HttpCatalogService(FakeReleaseApi()).search('kind');

      final album = albums.single;
      expect(album.id, kindOfBlueId);
      expect(album.artistYearFormat, 'Miles Davis · 1959 · Vinyl LP');
      expect(album.format, MediaFormat.vinyl);
      expect(album.coverUrl, 'https://i.discogs.com/kind-of-blue-thumb.jpg');
      expect(album.isPartial, isTrue);
      expect(album.tracks, isEmpty);
    });

    test('a CD hit is filtered as a CD', () async {
      final api = FakeReleaseApi(
        hits: const [
          ReleaseSearchResult(
            releaseId: '9',
            artist: 'A',
            title: 'B',
            format: 'CD, Album',
          ),
        ],
      );

      final album = (await HttpCatalogService(api).search('a b')).single;

      expect(album.format, MediaFormat.cd);
      expect(album.formatDescription, 'CD Album');
    });

    test('a backend failure is reported as an unavailable catalogue', () {
      final api = FakeReleaseApi()..failing = true;

      expect(
        HttpCatalogService(api).search('kind'),
        throwsA(isA<CatalogUnavailableException>()),
      );
    });
  });

  group('RepositoryReleaseDetails', () {
    late FakeReleaseApi api;
    late RepositoryReleaseDetails details;

    setUp(() {
      api = FakeReleaseApi();
      final db = createTestDatabase();
      addTearDown(db.close);
      details = RepositoryReleaseDetails(ReleaseRepository(db, api.release));
    });

    const candidate = ApiCandidate(
      releaseId: kindOfBlueId,
      artist: 'Miles Davis',
      title: 'Kind Of Blue',
      score: 0.91,
    );

    test('loads Discogs metadata, previews and cover', () async {
      final album = await details.details(candidate);

      expect(album.id, kindOfBlueId);
      expect(album.title, 'Kind Of Blue');
      expect(album.label, 'Columbia');
      expect(album.catalogNumber, 'CL 1355');
      expect(album.genres, ['Jazz', 'Modal']);
      expect(album.rating, 4.71);
      expect(album.coverUrl, 'https://i.discogs.com/kind-of-blue.jpg');
      expect(album.tracks.map((t) => t.title), [
        'So What',
        'Freddie Freeloader',
      ]);
      expect(album.topTracks.single.title, 'So What');
      expect(album.isPartial, isFalse);
    });

    test('a release fetched before opens from the cache', () async {
      await details.details(candidate);
      await details.details(candidate);

      expect(api.releaseRequests, [kindOfBlueId]);
    });

    test('a failure with nothing cached is thrown', () {
      api.failing = true;

      expect(details.details(candidate), throwsA(isA<ReleaseApiException>()));
    });

    test('complete loads a partial album and keeps a full one', () async {
      final partial = albumFromCandidate(candidate);

      final full = await details.complete(partial);
      expect(full.label, 'Columbia');
      expect(full.tracks, hasLength(2));

      expect(await details.complete(full), same(full));
      expect(api.releaseRequests, [kindOfBlueId]);
    });

    test('complete returns the partial album when loading fails', () async {
      api.failing = true;
      final partial = albumFromCandidate(candidate);

      expect(await details.complete(partial), same(partial));
    });

    test('complete does not look up ids that are not Discogs ids', () async {
      final partial = albumFromCandidate(
        const ApiCandidate(
          releaseId: 'mock-rumours-1977',
          artist: 'Fleetwood Mac',
          title: 'Rumours',
          score: 0.9,
        ),
      );

      expect(await details.complete(partial), same(partial));
      expect(api.releaseRequests, isEmpty);
    });
  });

  group('configuration', () {
    test('backend URLs get a trailing slash; empty means none', () {
      expect(configuredBackendUrl(''), isNull);
      expect(configuredBackendUrl('  '), isNull);
      expect(
        configuredBackendUrl('http://10.0.2.2:8000').toString(),
        'http://10.0.2.2:8000/',
      );
      expect(
        configuredBackendUrl('http://host/api')!
            .resolve('releases/1')
            .toString(),
        'http://host/api/releases/1',
      );
    });

    test('without a backend the offline mocks are used', () {
      final deps = AppDependencies(liveScanner: UnavailableLiveScanner());
      addTearDown(deps.dispose);

      expect(deps.catalog, isA<MockCatalogService>());
      expect(deps.releaseDetails, isA<BasicReleaseDetails>());
      expect(deps.session.api, isA<MockRecognitionApi>());
      expect(deps.database, isNull);
    });

    test('with a backend every service is real', () {
      final db = createTestDatabase();
      addTearDown(db.close);
      final deps = AppDependencies(
        liveScanner: UnavailableLiveScanner(),
        backendUrl: backend,
        database: db,
      );
      addTearDown(deps.dispose);

      expect(deps.catalog, isA<HttpCatalogService>());
      expect(deps.releaseDetails, isA<RepositoryReleaseDetails>());
      expect(deps.session.api, isA<HttpRecognitionApi>());
      expect(deps.session.details, same(deps.releaseDetails));
      expect(deps.recognition, isA<QueuedRecognitionService>());
      expect(deps.database, same(db));
    });
  });
}
