import 'package:drift/drift.dart';

import 'local/app_database.dart';

/// Album metadata as returned by the backend's `GET /releases/{release_id}`
/// (S2-04), parsed from JSON and converted to rows for the local database.
class ReleaseMetadata {
  const ReleaseMetadata({
    required this.releaseId,
    required this.artist,
    required this.title,
    this.year,
    this.coverUrl,
    this.label,
    this.catalogNumber,
    this.genres = const [],
    this.styles = const [],
    this.rating,
    this.previewStatus,
    this.tracks = const [],
  });

  /// Parses the backend response. Throws [FormatException] when the fields
  /// every album needs (id, artist, title) are missing or have the wrong type.
  factory ReleaseMetadata.fromJson(Map<String, Object?> json) {
    final id = json['discogs_id'];
    final artist = json['artist'];
    final title = json['title'];
    if (id is! int || artist is! String || title is! String) {
      throw const FormatException(
        'Release metadata needs discogs_id, artist and title.',
      );
    }
    final rawTracks = json['tracks'];
    return ReleaseMetadata(
      releaseId: '$id',
      artist: artist,
      title: title,
      year: _int(json['year']),
      coverUrl: _text(json['cover_url']),
      label: _text(json['label']),
      catalogNumber: _text(json['catalog_number']),
      genres: _strings(json['genres']),
      styles: _strings(json['styles']),
      rating: _double(json['rating']),
      previewStatus: _text(json['preview_status']),
      tracks: rawTracks is List
          ? rawTracks
                .whereType<Map<String, Object?>>()
                .where((track) => track['title'] is String)
                .map(ReleaseTrack.fromJson)
                .toList()
          : const [],
    );
  }

  /// Discogs release ID, stored in `albums.release_id`.
  final String releaseId;
  final String artist;
  final String title;
  final int? year;
  final String? coverUrl;
  final String? label;
  final String? catalogNumber;
  final List<String> genres;
  final List<String> styles;
  final double? rating;
  final String? previewStatus;
  final List<ReleaseTrack> tracks;

  /// Row for the `albums` table. `cover_path` is left untouched so a cover
  /// that was already downloaded is kept when the metadata is refreshed.
  AlbumsCompanion toAlbumCompanion({required DateTime fetchedAt}) {
    return AlbumsCompanion(
      releaseId: Value(releaseId),
      artist: Value(artist),
      title: Value(title),
      year: Value(year),
      coverUrl: Value(coverUrl),
      label: Value(label),
      catalogNumber: Value(catalogNumber),
      genres: Value(genres),
      styles: Value(styles),
      rating: Value(rating),
      previewStatus: Value(previewStatus),
      metadataSource: const Value('discogs'),
      fetchedAt: Value(fetchedAt),
    );
  }

  /// Rows for the `tracks` table, numbered 1, 2, 3 in tracklist order.
  List<TracksCompanion> toTrackCompanions() {
    return [
      for (final (index, track) in tracks.indexed)
        track.toCompanion(position: index + 1),
    ];
  }
}

/// One track of a [ReleaseMetadata] tracklist.
class ReleaseTrack {
  const ReleaseTrack({
    required this.title,
    this.positionLabel,
    this.durationSeconds,
    this.previewUrl,
  });

  factory ReleaseTrack.fromJson(Map<String, Object?> json) {
    return ReleaseTrack(
      title: json['title']! as String,
      positionLabel: _text(json['position']),
      durationSeconds: parseTrackDuration(json['duration']),
      previewUrl: _text(json['preview_url']),
    );
  }

  final String title;

  /// Position printed on the release, for example `A1`.
  final String? positionLabel;
  final int? durationSeconds;

  /// 30-second iTunes preview, when the backend found one.
  final String? previewUrl;

  TracksCompanion toCompanion({required int position}) {
    return TracksCompanion(
      position: Value(position),
      title: Value(title),
      positionLabel: Value(positionLabel),
      durationSeconds: Value(durationSeconds),
      previewUrl: Value(previewUrl),
      previewSource: Value(previewUrl == null ? null : 'itunes'),
    );
  }
}

/// Converts a Discogs duration such as `4:13` or `1:02:03` to seconds.
///
/// Returns null for an empty or unreadable value; Discogs leaves the
/// duration blank for many releases.
int? parseTrackDuration(Object? value) {
  if (value is! String) {
    return null;
  }
  final parts = value.trim().split(':');
  if (parts.length < 2 || parts.length > 3) {
    return null;
  }
  var seconds = 0;
  for (final (index, part) in parts.indexed) {
    final number = int.tryParse(part);
    if (number == null || number < 0 || (index > 0 && number >= 60)) {
      return null;
    }
    seconds = seconds * 60 + number;
  }
  return seconds;
}

String? _text(Object? value) {
  if (value is! String) {
    return null;
  }
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int? _int(Object? value) => value is int ? value : null;

double? _double(Object? value) => value is num ? value.toDouble() : null;

List<String> _strings(Object? value) {
  if (value is! List) {
    return const [];
  }
  return value.whereType<String>().toList();
}
