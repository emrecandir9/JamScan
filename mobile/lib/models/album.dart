/// Physical format of a release, or of the copy a user owns.
enum MediaFormat { vinyl, cd, tape }

extension MediaFormatLabel on MediaFormat {
  String get label => switch (this) {
    MediaFormat.vinyl => 'Vinyl',
    MediaFormat.cd => 'CD',
    MediaFormat.tape => 'Tape',
  };
}

/// One track of a release.
class Track {
  const Track({
    required this.position,
    required this.title,
    required this.duration,
    this.popularityRank,
    this.hasPreview = true,
  });

  /// Position as printed on the release, for example `A1` or `3`.
  final String position;
  final String title;
  final Duration duration;

  /// 1 is the most popular track. `null` when unknown.
  final int? popularityRank;

  /// Whether a 30-second preview exists for this track.
  final bool hasPreview;
}

/// A release as the UI shows it.
///
/// This is a view model for the screens. It carries more than the drift
/// `Albums` table does today (label, genres, rating, durations); see
/// docs/UI_SHELL.md for the fields the data model still needs.
class Album {
  const Album({
    required this.id,
    required this.title,
    required this.artist,
    required this.year,
    required this.format,
    required this.formatDescription,
    required this.pressingFormat,
    required this.label,
    required this.catalogNumber,
    required this.country,
    required this.genres,
    required this.tracks,
    this.rating,
    this.ratingCount = 0,
    this.isPartial = false,
    this.previewsAvailable = true,
  });

  /// External release identifier (a Discogs release id once wired up).
  final String id;
  final String title;
  final String artist;
  final int year;
  final MediaFormat format;

  /// Short format shown in lists, for example `Vinyl LP`.
  final String formatDescription;

  /// Full format shown in pressing details, for example `Vinyl, LP, Mono`.
  final String pressingFormat;
  final String label;
  final String catalogNumber;
  final String country;

  /// Genres first, then styles, as Discogs lists them.
  final List<String> genres;
  final List<Track> tracks;

  /// Community rating out of 5, or `null` when there are no ratings.
  final double? rating;
  final int ratingCount;

  /// True when only locally saved metadata is available.
  final bool isPartial;

  /// False when the preview service has nothing for this release.
  final bool previewsAvailable;

  /// `Artist · 1959`
  String get artistYear => '$artist · $year';

  /// `Artist · 1959 · Vinyl LP`
  String get artistYearFormat => '$artist · $year · $formatDescription';

  /// Up to five tracks with previews, most popular first.
  List<Track> get topTracks {
    if (!previewsAvailable) {
      return const [];
    }
    final ranked =
        tracks
            .where((track) => track.hasPreview && track.popularityRank != null)
            .toList()
          ..sort((a, b) => a.popularityRank!.compareTo(b.popularityRank!));
    return ranked.take(5).toList();
  }
}
