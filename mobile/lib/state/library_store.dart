import 'package:flutter/foundation.dart';

import '../mock/mock_library.dart';
import '../models/album.dart';
import '../models/library.dart';
import 'auth_controller.dart';

enum AddAlbumResult { added, duplicate, listMissing }

/// Result of moving or copying several entries to another list.
class TransferResult {
  const TransferResult({required this.transferred, required this.skipped});

  final int transferred;

  /// Entries already in the target list.
  final int skipped;
}

/// In-memory collections and wishlists of the signed-in user.
///
/// Each account has its own lists. Guests have none. This mirrors what the
/// drift `ListDao` will provide; the screens only use this class, so it can
/// later delegate to the database.
class LibraryStore extends ChangeNotifier {
  LibraryStore(this._auth) {
    _auth.addListener(_onAuthChanged);
  }

  final AuthController _auth;
  final Map<String, List<AlbumList>> _byUser = {};
  int _nextId = 1;

  String? get _userKey => _auth.user?.email;

  List<AlbumList> get _lists {
    final key = _userKey;
    if (key == null) {
      return const [];
    }
    return _byUser.putIfAbsent(key, () => _seedFor(key));
  }

  List<AlbumList> _seedFor(String email) {
    if (email != AuthController.demoEmail) {
      return [];
    }
    return MockLibrary.demoLists(nextId: _id);
  }

  String _id() => 'l${_nextId++}';

  void _onAuthChanged() => notifyListeners();

  /// All lists of the current user, collections first.
  List<AlbumList> get lists => List.unmodifiable(_lists);

  List<AlbumList> listsOf(ListKind kind) {
    return _lists.where((list) => list.kind == kind).toList();
  }

  AlbumList? listById(String id) {
    for (final list in _lists) {
      if (list.id == id) {
        return list;
      }
    }
    return null;
  }

  /// Albums owned across all collections (ghosts excluded).
  int get ownedCount => listsOf(
    ListKind.collection,
  ).fold(0, (sum, list) => sum + list.ownedCount);

  /// Albums across all wishlists.
  int get wishlistCount => listsOf(
    ListKind.wishlist,
  ).fold(0, (sum, list) => sum + list.entries.length);

  /// Lists that already contain [albumId].
  List<AlbumList> listsContaining(String albumId) {
    return _lists.where((list) => list.containsAlbum(albumId)).toList();
  }

  bool nameExists(String name, {String? exceptListId}) {
    final wanted = name.trim().toLowerCase();
    return _lists.any(
      (list) =>
          list.id != exceptListId && list.name.trim().toLowerCase() == wanted,
    );
  }

  /// Creates a list and returns its id.
  String createList(String name, ListKind kind) {
    final list = AlbumList(id: _id(), name: name.trim(), kind: kind);
    _lists.add(list);
    notifyListeners();
    return list.id;
  }

  void renameList(String listId, String name) {
    _replace(listId, (list) => list.copyWith(name: name.trim()));
  }

  void deleteList(String listId) {
    _lists.removeWhere((list) => list.id == listId);
    notifyListeners();
  }

  AddAlbumResult addAlbum({
    required String listId,
    required Album album,
    MediaFormat? format,
    bool ghost = false,
  }) {
    final list = listById(listId);
    if (list == null) {
      return AddAlbumResult.listMissing;
    }
    if (list.containsAlbum(album.id)) {
      return AddAlbumResult.duplicate;
    }
    final entry = ListEntry(
      id: _id(),
      album: album,
      addedAt: DateTime.now(),
      format: ghost ? null : format,
      isGhost: ghost,
    );
    _replace(listId, (list) => list.copyWith(entries: [entry, ...list.entries]));
    return AddAlbumResult.added;
  }

  void updateEntry(
    String listId,
    String entryId, {
    MediaFormat? format,
    String? condition,
    String? notes,
    String? lookingFor,
  }) {
    _updateEntry(
      listId,
      entryId,
      (entry) => entry.copyWith(
        format: format,
        condition: condition,
        notes: notes,
        lookingFor: lookingFor,
      ),
    );
  }

  /// Turns a ghost into an owned copy.
  void markOwned(String listId, String entryId, MediaFormat format) {
    _updateEntry(
      listId,
      entryId,
      (entry) => entry.copyWith(isGhost: false, format: format),
    );
  }

  void removeEntries(String listId, Set<String> entryIds) {
    _replace(
      listId,
      (list) => list.copyWith(
        entries: list.entries
            .where((entry) => !entryIds.contains(entry.id))
            .toList(),
      ),
    );
  }

  /// Copies entries into another list. Albums already there are skipped.
  TransferResult copyEntries(
    String fromListId,
    String toListId,
    Set<String> entryIds,
  ) {
    final from = listById(fromListId);
    final to = listById(toListId);
    if (from == null || to == null) {
      return const TransferResult(transferred: 0, skipped: 0);
    }

    final copies = <ListEntry>[];
    var skipped = 0;
    for (final entry in from.entries) {
      if (!entryIds.contains(entry.id)) {
        continue;
      }
      if (to.containsAlbum(entry.album.id)) {
        skipped++;
        continue;
      }
      // Wishlists hold albums the user wants; ghosts become plain entries.
      final copy = entry.copyWith(id: _id());
      copies.add(
        to.kind == ListKind.wishlist && copy.isGhost
            ? copy.copyWith(isGhost: false)
            : copy,
      );
    }
    _replace(toListId, (list) => list.copyWith(entries: [...copies, ...list.entries]));
    return TransferResult(transferred: copies.length, skipped: skipped);
  }

  /// Moves entries into another list. Albums already there stay where they
  /// are and are reported as skipped.
  TransferResult moveEntries(
    String fromListId,
    String toListId,
    Set<String> entryIds,
  ) {
    final to = listById(toListId);
    final from = listById(fromListId);
    if (from == null || to == null) {
      return const TransferResult(transferred: 0, skipped: 0);
    }
    final movable = from.entries
        .where(
          (entry) =>
              entryIds.contains(entry.id) && !to.containsAlbum(entry.album.id),
        )
        .map((entry) => entry.id)
        .toSet();
    final result = copyEntries(fromListId, toListId, movable);
    removeEntries(fromListId, movable);
    return TransferResult(
      transferred: result.transferred,
      skipped: entryIds.length - movable.length,
    );
  }

  /// Deletes every list of the account with [email].
  void deleteDataFor(String email) {
    _byUser.remove(email);
    notifyListeners();
  }

  void _updateEntry(
    String listId,
    String entryId,
    ListEntry Function(ListEntry entry) update,
  ) {
    _replace(
      listId,
      (list) => list.copyWith(
        entries: [
          for (final entry in list.entries)
            entry.id == entryId ? update(entry) : entry,
        ],
      ),
    );
  }

  void _replace(String listId, AlbumList Function(AlbumList list) update) {
    final lists = _lists;
    final index = lists.indexWhere((list) => list.id == listId);
    if (index < 0) {
      return;
    }
    lists[index] = update(lists[index]);
    notifyListeners();
  }

  @override
  void dispose() {
    _auth.removeListener(_onAuthChanged);
    super.dispose();
  }
}
