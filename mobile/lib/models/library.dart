import 'album.dart';

/// Kind of list a user keeps. Mirrors `ListType` in the drift tables.
enum ListKind { collection, wishlist }

extension ListKindLabel on ListKind {
  String get label => switch (this) {
    ListKind.collection => 'Collection',
    ListKind.wishlist => 'Wishlist',
  };
}

/// Condition grades used on Discogs, best first.
const List<String> mediaConditions = [
  'M',
  'NM',
  'VG+',
  'VG',
  'G+',
  'G',
  'F',
  'P',
];

/// An album saved in a list.
class ListEntry {
  const ListEntry({
    required this.id,
    required this.album,
    required this.addedAt,
    this.format,
    this.condition,
    this.notes = '',
    this.isGhost = false,
    this.lookingFor = '',
  });

  final String id;
  final Album album;
  final DateTime addedAt;

  /// Format of the copy the user owns. `null` for ghosts.
  final MediaFormat? format;
  final String? condition;
  final String notes;

  /// A ghost is an album the user wants in a collection but does not own yet.
  final bool isGhost;

  /// What the user is looking for, for ghosts.
  final String lookingFor;

  ListEntry copyWith({
    String? id,
    MediaFormat? format,
    String? condition,
    String? notes,
    bool? isGhost,
    String? lookingFor,
  }) {
    return ListEntry(
      id: id ?? this.id,
      album: album,
      addedAt: addedAt,
      format: format ?? this.format,
      condition: condition ?? this.condition,
      notes: notes ?? this.notes,
      isGhost: isGhost ?? this.isGhost,
      lookingFor: lookingFor ?? this.lookingFor,
    );
  }
}

/// A collection or wishlist.
class AlbumList {
  const AlbumList({
    required this.id,
    required this.name,
    required this.kind,
    this.entries = const [],
  });

  final String id;
  final String name;
  final ListKind kind;

  /// Newest first.
  final List<ListEntry> entries;

  int get ownedCount => entries.where((entry) => !entry.isGhost).length;
  int get ghostCount => entries.where((entry) => entry.isGhost).length;

  /// `42 owned · 3 ghosts` for collections, `9 albums` for wishlists.
  String get countLabel {
    if (kind == ListKind.wishlist) {
      return entries.length == 1 ? '1 album' : '${entries.length} albums';
    }
    final owned = '$ownedCount owned';
    if (ghostCount == 0) {
      return owned;
    }
    return ghostCount == 1
        ? '$owned · 1 ghost'
        : '$owned · $ghostCount ghosts';
  }

  bool containsAlbum(String albumId) {
    return entries.any((entry) => entry.album.id == albumId);
  }

  AlbumList copyWith({String? name, List<ListEntry>? entries}) {
    return AlbumList(
      id: id,
      name: name ?? this.name,
      kind: kind,
      entries: entries ?? this.entries,
    );
  }
}
