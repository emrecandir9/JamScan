// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'list_dao.dart';

// ignore_for_file: type=lint
mixin _$ListDaoMixin on DatabaseAccessor<AppDatabase> {
  $UsersTable get users => attachedDatabase.users;
  $ListsTable get lists => attachedDatabase.lists;
  $AlbumsTable get albums => attachedDatabase.albums;
  $ListEntriesTable get listEntries => attachedDatabase.listEntries;
  ListDaoManager get managers => ListDaoManager(this);
}

class ListDaoManager {
  final _$ListDaoMixin _db;
  ListDaoManager(this._db);
  $$UsersTableTableManager get users =>
      $$UsersTableTableManager(_db.attachedDatabase, _db.users);
  $$ListsTableTableManager get lists =>
      $$ListsTableTableManager(_db.attachedDatabase, _db.lists);
  $$AlbumsTableTableManager get albums =>
      $$AlbumsTableTableManager(_db.attachedDatabase, _db.albums);
  $$ListEntriesTableTableManager get listEntries =>
      $$ListEntriesTableTableManager(_db.attachedDatabase, _db.listEntries);
}
