import 'package:flutter/material.dart';

import '../../models/album.dart';
import '../../models/library.dart';
import '../../widgets/common.dart';
import 'list_filter.dart';

/// Sort & filter sheet of a list (wireframe 17). Pops with the new filter.
class FilterSortSheet extends StatefulWidget {
  const FilterSortSheet({
    super.key,
    required this.list,
    required this.initial,
    required this.query,
  });

  final AlbumList list;
  final ListFilter initial;

  /// Current search text, so the button can show the resulting count.
  final String query;

  @override
  State<FilterSortSheet> createState() => _FilterSortSheetState();
}

class _FilterSortSheetState extends State<FilterSortSheet> {
  late ListFilter _draft = widget.initial;

  void _update(ListFilter filter) => setState(() => _draft = filter);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries = widget.list.entries;
    final isCollection = widget.list.kind == ListKind.collection;
    final genres = {for (final entry in entries) ...entry.album.genres}.toList()
      ..sort();
    final artists = {for (final entry in entries) entry.album.artist}.toList()
      ..sort();
    final years = [for (final entry in entries) entry.album.year];
    final minYear = years.isEmpty ? 0 : years.reduce((a, b) => a < b ? a : b);
    final maxYear = years.isEmpty ? 0 : years.reduce((a, b) => a > b ? a : b);
    final fromYear = (_draft.fromYear ?? minYear).clamp(minYear, maxYear);
    final toYear = (_draft.toYear ?? maxYear).clamp(minYear, maxYear);
    final count = _draft.apply(entries, widget.query).length;

    return SingleChildScrollView(
      padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Sort & filter', style: theme.textTheme.headlineSmall),
          const SizedBox(height: 16),
          const SectionLabel('Sort by'),
          for (final sort in ListSort.values)
            InkWell(
              onTap: () => _update(_draft.copyWith(sort: sort)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  children: [
                    ChoiceMark(selected: _draft.sort == sort),
                    const SizedBox(width: 14),
                    Text(sort.longLabel, style: theme.textTheme.bodyLarge),
                  ],
                ),
              ),
            ),
          if (isCollection) ...[
            const SizedBox(height: 16),
            const SectionLabel('Show'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                FilterChip(
                  label: const Text('Owned'),
                  selected: _draft.showOwned,
                  onSelected: (value) =>
                      _update(_draft.copyWith(showOwned: value)),
                ),
                FilterChip(
                  label: const Text('Ghosts'),
                  selected: _draft.showGhosts,
                  onSelected: (value) =>
                      _update(_draft.copyWith(showGhosts: value)),
                ),
              ],
            ),
          ],
          const SizedBox(height: 16),
          const SectionLabel('Format'),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final format in MediaFormat.values)
                FilterChip(
                  label: Text(format.label),
                  selected: _draft.formats.contains(format),
                  onSelected: (value) => _update(
                    _draft.copyWith(
                      formats: toggled(_draft.formats, format, value),
                    ),
                  ),
                ),
            ],
          ),
          if (genres.isNotEmpty) ...[
            const SizedBox(height: 16),
            const SectionLabel('Genre'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final genre in genres)
                  FilterChip(
                    label: Text(genre),
                    selected: _draft.genres.contains(genre),
                    onSelected: (value) => _update(
                      _draft.copyWith(
                        genres: toggled(_draft.genres, genre, value),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (artists.length > 1) ...[
            const SizedBox(height: 16),
            const SectionLabel('Artist'),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final artist in artists)
                  FilterChip(
                    label: Text(artist),
                    selected: _draft.artists.contains(artist),
                    onSelected: (value) => _update(
                      _draft.copyWith(
                        artists: toggled(_draft.artists, artist, value),
                      ),
                    ),
                  ),
              ],
            ),
          ],
          if (minYear < maxYear) ...[
            const SizedBox(height: 16),
            const SectionLabel('Release year'),
            RangeSlider(
              values: RangeValues(fromYear.toDouble(), toYear.toDouble()),
              min: minYear.toDouble(),
              max: maxYear.toDouble(),
              divisions: maxYear - minYear,
              labels: RangeLabels('$fromYear', '$toYear'),
              onChanged: (values) {
                final from = values.start.round();
                final to = values.end.round();
                _update(
                  from == minYear && to == maxYear
                      ? _draft.copyWith(clearYears: true)
                      : _draft.copyWith(fromYear: from, toYear: to),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [Text('$fromYear'), Text('$toYear')],
              ),
            ),
          ],
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: TextButton(
                  onPressed: () => _update(const ListFilter()),
                  child: const Text('Clear all'),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: FilledButton(
                  key: const Key('filter.apply'),
                  onPressed: () => Navigator.of(context).pop(_draft),
                  child: Text(
                    count == 1 ? 'Show 1 album' : 'Show $count albums',
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
