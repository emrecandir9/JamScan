import 'package:flutter_test/flutter_test.dart';
import 'package:jamscan/mock/mock_catalog.dart';
import 'package:jamscan/services/recognition_api.dart';
import 'package:jamscan/services/release_details_service.dart';

void main() {
  test('an unknown year is left out instead of showing 0', () {
    final partial = albumFromCandidate(
      const ApiCandidate(
        releaseId: '25094227',
        artist: 'Miles Davis',
        title: 'Kind Of Blue',
        score: 0.9,
      ),
    );

    expect(partial.artistYear, 'Miles Davis');
    expect(partial.artistYearFormat, 'Miles Davis · Vinyl');
    expect(MockCatalog.rumours.artistYear, 'Fleetwood Mac · 1977');
  });
}
