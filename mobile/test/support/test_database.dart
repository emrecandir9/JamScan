import 'package:drift/native.dart';
import 'package:jamscan/data/local/app_database.dart';

/// A fresh in-memory database for a single test.
///
/// package:sqlite3 3.x bundles its own SQLite build, so no platform-specific
/// library loading is needed here.
AppDatabase createTestDatabase() {
  return AppDatabase.withExecutor(NativeDatabase.memory());
}
