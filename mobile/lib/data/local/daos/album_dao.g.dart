// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'album_dao.dart';

// ignore_for_file: type=lint
mixin _$AlbumDaoMixin on DatabaseAccessor<AppDatabase> {
  $AlbumsTable get albums => attachedDatabase.albums;
  $TracksTable get tracks => attachedDatabase.tracks;
  AlbumDaoManager get managers => AlbumDaoManager(this);
}

class AlbumDaoManager {
  final _$AlbumDaoMixin _db;
  AlbumDaoManager(this._db);
  $$AlbumsTableTableManager get albums =>
      $$AlbumsTableTableManager(_db.attachedDatabase, _db.albums);
  $$TracksTableTableManager get tracks =>
      $$TracksTableTableManager(_db.attachedDatabase, _db.tracks);
}
