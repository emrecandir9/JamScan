import 'dart:async';

import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../models/album.dart';
import '../../routing/app_routes.dart';
import '../../services/catalog_service.dart';
import '../../state/shell_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/album_art.dart';
import '../../widgets/common.dart';
import '../../widgets/taskbars.dart';

/// Manual search by title or artist (08a results, 08b no results / error).
///
/// Pops with the selected release, which the camera page then shows.
class ManualSearchScreen extends StatefulWidget {
  const ManualSearchScreen({super.key, required this.args});

  final ManualSearchArgs args;

  @override
  State<ManualSearchScreen> createState() => _ManualSearchScreenState();
}

class _ManualSearchScreenState extends State<ManualSearchScreen> {
  late final TextEditingController _query = TextEditingController(
    text: widget.args.initialQuery,
  );
  MediaFormat? _format;
  List<Album>? _results;
  bool _loading = false;
  int _request = 0;

  @override
  void initState() {
    super.initState();
    final initial = widget.args.initialQuery;
    if (initial.trim().isNotEmpty) {
      _loading = true;
      // Runs after the first frame, so the search may call setState.
      scheduleMicrotask(() => _search(initial));
    }
  }

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  Future<void> _search(String text) async {
    final request = ++_request;
    final query = text.trim();
    if (query.isEmpty) {
      setState(() {
        _results = null;
        _loading = false;
      });
      return;
    }

    setState(() => _loading = true);
    final catalog = AppScope.of(context).catalog;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final results = await catalog.search(query);
      if (!mounted || request != _request) return;
      setState(() {
        _results = results;
        _loading = false;
      });
    } on CatalogUnavailableException {
      if (!mounted || request != _request) return;
      setState(() => _loading = false);
      showAppSnackBar(
        messenger,
        "Discogs isn't responding.",
        actionLabel: 'RETRY',
        onAction: () => _search(_query.text),
      );
    }
  }

  void _clear() {
    _query.clear();
    _search('');
  }

  void _select(Album album) {
    final query = _query.text.trim();
    AppScope.of(context).history.recordSearch(
      query,
      album,
      afterFailedScan: widget.args.afterFailedScan,
    );
    Navigator.of(context).pop(album);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final query = _query.text.trim();
    final results = _results;
    final filtered = results
        ?.where((album) => _format == null || album.format == _format)
        .toList();

    final Widget body;
    if (query.isEmpty) {
      body = const EmptyState(
        icon: Icons.search,
        title: 'Search for an album',
        message: 'Type the album title, the artist, or both.',
      );
    } else if (filtered == null) {
      body = const SizedBox.shrink();
    } else if (filtered.isEmpty) {
      body = EmptyState(
        icon: Icons.search,
        title: 'No results for "$query"',
        message:
            'Check the spelling, or try just the artist or just the album '
            'title.',
        actions: [
          OutlinedButton(onPressed: _clear, child: const Text('Clear search')),
        ],
      );
    } else {
      body = ListView(
        padding: const EdgeInsets.only(bottom: 24),
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
            child: Text(
              filtered.length == 1
                  ? '1 result from Discogs'
                  : '${filtered.length} results from Discogs',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: AppColors.textSecondary,
              ),
            ),
          ),
          for (final album in filtered)
            _ResultRow(album: album, onTap: _select),
        ],
      );
    }

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 16, 8),
              child: Row(
                children: [
                  const BackButton(),
                  Expanded(
                    child: TextField(
                      key: const Key('search.field'),
                      controller: _query,
                      autofocus: widget.args.initialQuery.isEmpty,
                      textInputAction: TextInputAction.search,
                      onChanged: _search,
                      onSubmitted: _search,
                      decoration: AppInputs.search(
                        'Album title or artist',
                        suffixIcon: query.isEmpty
                            ? null
                            : IconButton(
                                tooltip: 'Clear search',
                                icon: const Icon(Icons.close),
                                onPressed: _clear,
                              ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  _FormatChip(
                    label: 'All',
                    selected: _format == null,
                    onSelected: () => setState(() => _format = null),
                  ),
                  _FormatChip(
                    label: 'Vinyl',
                    selected: _format == MediaFormat.vinyl,
                    onSelected: () =>
                        setState(() => _format = MediaFormat.vinyl),
                  ),
                  _FormatChip(
                    label: 'CD',
                    selected: _format == MediaFormat.cd,
                    onSelected: () => setState(() => _format = MediaFormat.cd),
                  ),
                ],
              ),
            ),
            SizedBox(
              height: 4,
              child: _loading
                  ? const LinearProgressIndicator(minHeight: 2)
                  : null,
            ),
            Expanded(child: body),
          ],
        ),
      ),
      bottomNavigationBar: const MainTaskbar(current: AppTab.scan),
    );
  }
}

class _FormatChip extends StatelessWidget {
  const _FormatChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
      ),
    );
  }
}

class _ResultRow extends StatelessWidget {
  const _ResultRow({required this.album, required this.onTap});

  final Album album;
  final ValueChanged<Album> onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: () => onTap(album),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 8, 12, 8),
        child: Row(
          children: [
            AlbumArt(album: album, size: 60),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    album.artistYearFormat,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right),
          ],
        ),
      ),
    );
  }
}
