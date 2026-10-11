import 'package:drift/drift.dart';

/// Kind of list a user keeps. Stored as text, as in the ER diagram.
enum ListType { collection, wishlist }

/// How a history entry was created. Stored as text, as in the ER diagram.
enum HistoryKind { scan, manualSearch }

/// Application user. Local-only for now; authentication is a later story.
class Users extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get displayName => text().withLength(min: 1, max: 100)();
  TextColumn get email => text().unique()();
  TextColumn get passwordHash => text()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// A collection or wishlist belonging to a user.
@DataClassName('AlbumList')
class Lists extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get userId =>
      integer().references(Users, #id, onDelete: KeyAction.cascade)();
  TextColumn get name => text().withLength(min: 1, max: 100)();
  TextColumn get type => textEnum<ListType>()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}

/// A recognised release. [releaseId] is the external Discogs identifier;
/// the primary key is a synthetic integer (decision 1 in DATA_MODEL.md).
class Albums extends Table {
  IntColumn get id => integer().autoIncrement()();
  TextColumn get releaseId => text().nullable().unique()();
  TextColumn get artist => text()();
  TextColumn get title => text()();
  IntColumn get year => integer().nullable()();
  TextColumn get coverPath => text().nullable()();
  TextColumn get discogsFormat => text().nullable()();
  TextColumn get metadataSource =>
      text().withDefault(const Constant('manual'))();
  DateTimeColumn get fetchedAt => dateTime().withDefault(currentDateAndTime)();
}

/// One track of an album's tracklist.
class Tracks extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get albumId =>
      integer().references(Albums, #id, onDelete: KeyAction.cascade)();
  IntColumn get position => integer()();
  TextColumn get title => text()();
  IntColumn get popularityRank => integer().nullable()();
  TextColumn get previewUrl => text().nullable()();
  TextColumn get previewSource => text().nullable()();

  /// A tracklist cannot contain the same position twice.
  @override
  List<Set<Column>> get uniqueKeys => [
    {albumId, position},
  ];
}

/// An album saved into a list, with the user's own ownership details.
class ListEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get listId =>
      integer().references(Lists, #id, onDelete: KeyAction.cascade)();
  IntColumn get albumId =>
      integer().references(Albums, #id, onDelete: KeyAction.cascade)();
  TextColumn get ownedFormat => text().nullable()();
  TextColumn get condition => text().nullable()();
  TextColumn get notes => text().nullable()();
  IntColumn get priority => integer().nullable()();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();

  /// Duplicate rule (decision 2 in DATA_MODEL.md): the same album cannot be
  /// added to the same list twice.
  @override
  List<Set<Column>> get uniqueKeys => [
    {listId, albumId},
  ];
}

/// A scan or manual search performed by a user.
class HistoryEntries extends Table {
  IntColumn get id => integer().autoIncrement()();
  IntColumn get userId =>
      integer().references(Users, #id, onDelete: KeyAction.cascade)();
  IntColumn get albumId => integer().nullable().references(
    Albums,
    #id,
    onDelete: KeyAction.setNull,
  )();
  TextColumn get kind => textEnum<HistoryKind>()();
  TextColumn get queryText => text().nullable()();
  TextColumn get imagePath => text().nullable()();
  RealColumn get confidence => real().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
