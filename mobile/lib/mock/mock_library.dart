import '../models/album.dart';
import '../models/history.dart';
import '../models/library.dart';
import 'mock_catalog.dart';

/// Sample lists and history for the demo account.
abstract final class MockLibrary {
  static List<AlbumList> demoLists({required String Function() nextId}) {
    ListEntry owned(
      Album album,
      MediaFormat format,
      int daysAgo, {
      String? condition,
      String notes = '',
    }) {
      return ListEntry(
        id: nextId(),
        album: album,
        addedAt: DateTime(2026, 10, 1).subtract(Duration(days: daysAgo)),
        format: format,
        condition: condition,
        notes: notes,
      );
    }

    ListEntry ghost(Album album, int daysAgo, {String lookingFor = ''}) {
      return ListEntry(
        id: nextId(),
        album: album,
        addedAt: DateTime(2026, 10, 1).subtract(Duration(days: daysAgo)),
        isGhost: true,
        lookingFor: lookingFor,
      );
    }

    ListEntry wanted(Album album, int daysAgo) {
      return ListEntry(
        id: nextId(),
        album: album,
        addedAt: DateTime(2026, 10, 1).subtract(Duration(days: daysAgo)),
      );
    }

    return [
      AlbumList(
        id: nextId(),
        name: 'My Vinyl',
        kind: ListKind.collection,
        entries: [
          owned(
            MockCatalog.kindOfBlue,
            MediaFormat.vinyl,
            1,
            condition: 'VG+',
            notes: 'Bought at local record fair',
          ),
          owned(
            MockCatalog.rumours,
            MediaFormat.vinyl,
            4,
            condition: 'NM',
          ),
          ghost(
            MockCatalog.loveSupreme,
            6,
            lookingFor: 'Original 1965 pressing, VG+ or better',
          ),
          owned(
            MockCatalog.blueTrain,
            MediaFormat.vinyl,
            9,
            condition: 'VG',
          ),
          owned(
            MockCatalog.ledZeppelinIV,
            MediaFormat.vinyl,
            15,
            condition: 'VG+',
          ),
          ghost(MockCatalog.moanin, 20),
        ],
      ),
      AlbumList(
        id: nextId(),
        name: 'Jazz Shelf',
        kind: ListKind.collection,
        entries: [
          owned(MockCatalog.kindOfBlueLegacy, MediaFormat.cd, 2),
          owned(MockCatalog.moanin, MediaFormat.vinyl, 12, condition: 'G+'),
          owned(MockCatalog.blueTrain, MediaFormat.vinyl, 30, condition: 'VG'),
        ],
      ),
      AlbumList(
        id: nextId(),
        name: 'CDs',
        kind: ListKind.collection,
        entries: [
          owned(MockCatalog.discovery, MediaFormat.cd, 3, condition: 'NM'),
          ghost(MockCatalog.kindOfBlueReissue, 8),
        ],
      ),
      AlbumList(
        id: nextId(),
        name: 'Gifts',
        kind: ListKind.collection,
        entries: [
          owned(MockCatalog.liveAtTheGarage, MediaFormat.tape, 40),
        ],
      ),
      AlbumList(
        id: nextId(),
        name: 'Wishlist',
        kind: ListKind.wishlist,
        entries: [
          wanted(MockCatalog.discovery, 2),
          wanted(MockCatalog.loveSupreme, 7),
        ],
      ),
    ];
  }

  static List<HistoryItem> demoHistory(
    DateTime now, {
    required String Function() nextId,
  }) {
    DateTime at(int daysAgo, int hour, int minute) {
      final day = DateTime(now.year, now.month, now.day - daysAgo);
      return DateTime(day.year, day.month, day.day, hour, minute);
    }

    return [
      HistoryItem(
        id: nextId(),
        kind: HistoryKind.scan,
        createdAt: at(0, 14, 32),
        album: MockCatalog.kindOfBlue,
      ),
      HistoryItem(
        id: nextId(),
        kind: HistoryKind.search,
        createdAt: at(0, 14, 20),
        album: MockCatalog.kindOfBlueLegacy,
        query: 'kind of blue',
      ),
      HistoryItem(
        id: nextId(),
        kind: HistoryKind.search,
        createdAt: at(0, 14, 5),
        album: MockCatalog.blueTrain,
        query: 'blue train',
        afterFailedScan: true,
      ),
      HistoryItem(
        id: nextId(),
        kind: HistoryKind.scan,
        createdAt: at(1, 18, 47),
        album: MockCatalog.rumours,
      ),
      HistoryItem(
        id: nextId(),
        kind: HistoryKind.scan,
        createdAt: at(1, 18, 40),
        album: MockCatalog.discovery,
      ),
      HistoryItem(
        id: nextId(),
        kind: HistoryKind.scan,
        createdAt: at(4, 11, 2),
        album: MockCatalog.ledZeppelinIV,
      ),
    ];
  }
}
