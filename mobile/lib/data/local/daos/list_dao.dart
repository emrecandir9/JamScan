import 'package:drift/drift.dart';

import '../app_database.dart';
import '../tables.dart';

part 'list_dao.g.dart';

/// A saved list entry together with the album it points to.
class ListEntryWithAlbum {
  const ListEntryWithAlbum({required this.entry, required this.album});

  final ListEntry entry;
  final Album album;
}

@DriftAccessor(tables: [Lists, ListEntries, Albums])
class ListDao extends DatabaseAccessor<AppDatabase> with _$ListDaoMixin {
  ListDao(super.db);

  /// Creates a collection or wishlist for a user.
  Future<int> createList({
    required int userId,
    required String name,
    required ListType type,
  }) {
    return into(lists)
        .insert(ListsCompanion.insert(userId: userId, name: name, type: type));
  }

  /// True when the album is already saved in this list.
  Future<bool> listContainsAlbum({
    required int listId,
    required int albumId,
  }) async {
    final existing =
        await (select(listEntries)..where(
              (e) => e.listId.equals(listId) & e.albumId.equals(albumId),
            ))
            .getSingleOrNull();
    return existing != null;
  }

  /// Adds an album to a list.
  ///
  /// Throws if the album is already in that list: the unique key
  /// `(list_id, album_id)` is the duplicate rule agreed by the team.
  Future<int> addAlbumToList({
    required int listId,
    required int albumId,
    String? ownedFormat,
    String? condition,
    String? notes,
    int? priority,
  }) {
    return into(listEntries).insert(
      ListEntriesCompanion.insert(
        listId: listId,
        albumId: albumId,
        ownedFormat: Value.absentIfNull(ownedFormat),
        condition: Value.absentIfNull(condition),
        notes: Value.absentIfNull(notes),
        priority: Value.absentIfNull(priority),
      ),
    );
  }

  /// Adds an album only when it is not in the list yet.
  ///
  /// Returns the new entry id, or `null` when the album was already saved.
  /// Use this from the UI so a duplicate is a message, not an exception.
  Future<int?> addAlbumToListIfAbsent({
    required int listId,
    required int albumId,
    String? ownedFormat,
    String? condition,
    String? notes,
    int? priority,
  }) {
    return transaction(() async {
      if (await listContainsAlbum(listId: listId, albumId: albumId)) {
        return null;
      }
      return addAlbumToList(
        listId: listId,
        albumId: albumId,
        ownedFormat: ownedFormat,
        condition: condition,
        notes: notes,
        priority: priority,
      );
    });
  }

  /// Entries of a list with their albums, newest first.
  Future<List<ListEntryWithAlbum>> entriesForList(int listId) async {
    final query =
        select(listEntries)
            .join([innerJoin(albums, albums.id.equalsExp(listEntries.albumId))])
          ..where(listEntries.listId.equals(listId))
          ..orderBy([OrderingTerm.desc(listEntries.addedAt)]);

    final rows = await query.get();
    return rows
        .map(
          (row) => ListEntryWithAlbum(
            entry: row.readTable(listEntries),
            album: row.readTable(albums),
          ),
        )
        .toList();
  }

  /// Removes one saved album from a list.
  Future<int> removeEntry(int entryId) {
    return (delete(listEntries)..where((e) => e.id.equals(entryId))).go();
  }
}
