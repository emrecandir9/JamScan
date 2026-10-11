import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'daos/album_dao.dart';
import 'daos/list_dao.dart';
import 'tables.dart';

part 'app_database.g.dart';

@DriftDatabase(
  tables: [Users, Lists, Albums, Tracks, ListEntries, HistoryEntries],
  daos: [AlbumDao, ListDao],
)
class AppDatabase extends _$AppDatabase {
  /// Opens the on-device SQLite file. Used by the application.
  AppDatabase() : super(driftDatabase(name: 'jamscan'));

  /// Opens an explicit executor. Used by tests with an in-memory database.
  AppDatabase.withExecutor(super.executor);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
    onCreate: (m) async {
      await m.createAll();
    },
    beforeOpen: (details) async {
      // SQLite does not enforce foreign keys unless this is enabled per
      // connection. Cascading deletes depend on it.
      await customStatement('PRAGMA foreign_keys = ON');
    },
  );
}
