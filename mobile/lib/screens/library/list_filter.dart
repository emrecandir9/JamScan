import '../../models/album.dart';
import '../../models/library.dart';

enum ListSort { dateAdded, artist, year }

extension ListSortLabel on ListSort {
  /// Shown next to the count on the list page.
  String get shortLabel => switch (this) {
    ListSort.dateAdded => 'Date added',
    ListSort.artist => 'Artist A–Z',
    ListSort.year => 'Release year',
  };

  /// Shown in the sort & filter sheet.
  String get longLabel => switch (this) {
    ListSort.dateAdded => 'Date added (newest first)',
    ListSort.artist => 'Artist A–Z',
    ListSort.year => 'Release year',
  };
}

/// Search, sort and filter state of a list page (16a, 16b, 17).
class ListFilter {
  const ListFilter({
    this.sort = ListSort.dateAdded,
    this.showOwned = true,
    this.showGhosts = true,
    this.formats = const {},
    this.genres = const {},
    this.artists = const {},
    this.fromYear,
    this.toYear,
  });

  final ListSort sort;
  final bool showOwned;
  final bool showGhosts;
  final Set<MediaFormat> formats;
  final Set<String> genres;
  final Set<String> artists;
  final int? fromYear;
  final int? toYear;

  bool get hasYearRange => fromYear != null || toYear != null;

  /// True when any filter (not the sort order) narrows the list.
  bool get isFiltering =>
      !showOwned ||
      !showGhosts ||
      formats.isNotEmpty ||
      genres.isNotEmpty ||
      artists.isNotEmpty ||
      hasYearRange;

  ListFilter copyWith({
    ListSort? sort,
    bool? showOwned,
    bool? showGhosts,
    Set<MediaFormat>? formats,
    Set<String>? genres,
    Set<String>? artists,
    int? fromYear,
    int? toYear,
    bool clearYears = false,
  }) {
    return ListFilter(
      sort: sort ?? this.sort,
      showOwned: showOwned ?? this.showOwned,
      showGhosts: showGhosts ?? this.showGhosts,
      formats: formats ?? this.formats,
      genres: genres ?? this.genres,
      artists: artists ?? this.artists,
      fromYear: clearYears ? null : fromYear ?? this.fromYear,
      toYear: clearYears ? null : toYear ?? this.toYear,
    );
  }

  /// Entries matching [query] and the filters, in sort order.
  List<ListEntry> apply(List<ListEntry> entries, String query) {
    final text = query.trim().toLowerCase();
    final from = fromYear;
    final to = toYear;

    final result = entries.where((entry) {
      final album = entry.album;
      if (entry.isGhost ? !showGhosts : !showOwned) {
        return false;
      }
      if (formats.isNotEmpty &&
          !formats.contains(entry.format ?? album.format)) {
        return false;
      }
      if (genres.isNotEmpty && !album.genres.any(genres.contains)) {
        return false;
      }
      if (artists.isNotEmpty && !artists.contains(album.artist)) {
        return false;
      }
      if (from != null && album.year < from) {
        return false;
      }
      if (to != null && album.year > to) {
        return false;
      }
      if (text.isNotEmpty &&
          !'${album.title} ${album.artist}'.toLowerCase().contains(text)) {
        return false;
      }
      return true;
    }).toList();

    switch (sort) {
      case ListSort.dateAdded:
        result.sort((a, b) => b.addedAt.compareTo(a.addedAt));
      case ListSort.artist:
        result.sort(
          (a, b) => a.album.artist.toLowerCase().compareTo(
            b.album.artist.toLowerCase(),
          ),
        );
      case ListSort.year:
        result.sort((a, b) => a.album.year.compareTo(b.album.year));
    }
    return result;
  }
}

/// Returns a copy of [values] with [value] added or removed.
Set<T> toggled<T>(Set<T> values, T value, bool include) {
  final copy = {...values};
  if (include) {
    copy.add(value);
  } else {
    copy.remove(value);
  }
  return copy;
}
