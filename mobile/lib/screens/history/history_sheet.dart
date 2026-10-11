import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../models/album.dart';
import '../../models/history.dart';
import '../../widgets/album_art.dart';
import '../../widgets/common.dart';
import '../../widgets/formatting.dart';
import '../library/list_dialogs.dart';

/// Scan and search history overlay (14, UC-14).
///
/// Completes with the album the user opened, if any.
Future<Album?> showHistorySheet(BuildContext context) {
  return showModalBottomSheet<Album>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) =>
        const FractionallySizedBox(heightFactor: 0.9, child: HistorySheet()),
  );
}

class HistorySheet extends StatefulWidget {
  const HistorySheet({super.key});

  @override
  State<HistorySheet> createState() => _HistorySheetState();
}

class _HistorySheetState extends State<HistorySheet> {
  /// `null` shows everything.
  HistoryKind? _filter;

  Future<void> _clearAll() async {
    final history = AppScope.of(context).history;
    final confirmed = await confirmAction(
      context,
      title: 'Clear your history?',
      message: 'All scans and searches will be removed from this device.',
      confirmLabel: 'Clear',
    );
    if (confirmed) {
      history.clear();
    }
  }

  Widget _chip(String label, HistoryKind? kind) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: _filter == kind,
        onSelected: (_) => setState(() => _filter = kind),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final history = AppScope.of(context).history;
    final theme = Theme.of(context);

    return ListenableBuilder(
      listenable: history,
      builder: (context, _) {
        final items = history.items
            .where((item) => _filter == null || item.kind == _filter)
            .toList();
        final now = DateTime.now();
        final rows = <Widget>[];
        String? day;
        for (final item in items) {
          final itemDay = Formatting.day(item.createdAt, now);
          if (itemDay != day) {
            day = itemDay;
            rows.add(
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 16, 24, 4),
                child: Text(itemDay, style: theme.textTheme.titleSmall),
              ),
            );
          }
          final album = item.album;
          rows.add(
            _HistoryRow(
              item: item,
              onOpen: album == null
                  ? null
                  : () => Navigator.of(context).pop(album),
              onRemove: () => history.remove(item.id),
            ),
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'History',
                      style: theme.textTheme.headlineSmall,
                    ),
                  ),
                  TextButton(
                    onPressed: history.items.isEmpty ? null : _clearAll,
                    child: const Text('Clear all'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Wrap(
                children: [
                  _chip('All', null),
                  _chip('Scans', HistoryKind.scan),
                  _chip('Searches', HistoryKind.search),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: items.isEmpty
                  ? const EmptyState(
                      icon: Icons.history,
                      title: 'Nothing here yet',
                      message:
                          'Albums you scan or search for will show up here.',
                    )
                  : ListView(
                      padding: const EdgeInsets.only(bottom: 24),
                      children: rows,
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _HistoryRow extends StatelessWidget {
  const _HistoryRow({
    required this.item,
    required this.onOpen,
    required this.onRemove,
  });

  final HistoryItem item;
  final VoidCallback? onOpen;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      onTap: onOpen,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 8, 12, 8),
        child: Row(
          children: [
            AlbumArt(album: item.album, size: 56),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium,
                  ),
                  Text(
                    '${item.description} · ${Formatting.time(item.createdAt)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium,
                  ),
                ],
              ),
            ),
            IconButton(
              tooltip: 'Remove from history',
              icon: const Icon(Icons.close),
              onPressed: onRemove,
            ),
          ],
        ),
      ),
    );
  }
}
