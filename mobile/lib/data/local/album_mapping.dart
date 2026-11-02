import '../../models/album.dart' as model;
import 'daos/album_dao.dart';

/// Converts stored rows into the view model the screens use
/// (`lib/models/album.dart`), so Album Details can show cached metadata.
extension AlbumWithTracksMapping on AlbumWithTracks {
  /// [isPartial] marks metadata that could not be refreshed (offline).
  model.Album toViewModel({bool isPartial = false}) {
    final format = album.discogsFormat;
    final viewTracks = [
      for (final track in tracks)
        model.Track(
          position: track.positionLabel ?? '${track.position}',
          title: track.title,
          duration: Duration(seconds: track.durationSeconds ?? 0),
          popularityRank: track.popularityRank,
          hasPreview: track.previewUrl != null,
        ),
    ];
    return model.Album(
      id: album.releaseId ?? 'local-${album.id}',
      title: album.title,
      artist: album.artist,
      year: album.year ?? 0,
      format: mediaFormatOf(format),
      formatDescription: shortFormatOf(format),
      pressingFormat: format ?? '',
      label: album.label ?? '',
      catalogNumber: album.catalogNumber ?? '',
      // Discogs returns no country in the S2-04 response yet.
      country: '',
      genres: [...album.genres, ...album.styles],
      tracks: viewTracks,
      rating: album.rating,
      isPartial: isPartial,
      previewsAvailable: viewTracks.any((track) => track.hasPreview),
    );
  }
}

/// Physical format from a Discogs format string such as `Vinyl, LP, Album`.
/// Defaults to vinyl, the format the MVP targets.
model.MediaFormat mediaFormatOf(String? discogsFormat) {
  final value = (discogsFormat ?? '').toLowerCase();
  if (value.startsWith('cd')) {
    return model.MediaFormat.cd;
  }
  if (value.startsWith('cassette')) {
    return model.MediaFormat.tape;
  }
  return model.MediaFormat.vinyl;
}

/// Short format for lists: `Vinyl, LP, Album` becomes `Vinyl LP`.
String shortFormatOf(String? discogsFormat) {
  final parts = (discogsFormat ?? '')
      .split(',')
      .map((part) => part.trim())
      .where((part) => part.isNotEmpty)
      .take(2)
      .toList();
  return parts.isEmpty ? mediaFormatOf(discogsFormat).label : parts.join(' ');
}
