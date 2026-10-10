import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../models/album.dart';
import '../../models/library.dart';
import '../../routing/app_navigation.dart';
import '../../state/library_store.dart';
import '../../state/shell_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/album_art.dart';
import '../../widgets/common.dart';
import '../../widgets/formatting.dart';
import '../../widgets/taskbars.dart';
import 'entry_sheets.dart';
import 'filter_sort_sheet.dart';
import 'list_dialogs.dart';
import 'list_filter.dart';

enum _ListAction { select, rename, delete }

/// One collection or wishlist (16a, 16b no results, 20 bulk select).
class ListDetailScreen extends StatefulWidget {
  const ListDetailScreen({super.key, required this.listId});

  final String listId;

  @override
  State<ListDetailScreen> createState() => _ListDetailScreenState();
}

class _ListDetailScreenState extends State<ListDetailScreen> {
  final TextEditingController _query = TextEditingController();
  ListFilter _filter = const ListFilter();

  /// Selected entry ids while in bulk-select mode, otherwise `null`.
  Set<String>? _selection;

  @override
  void dispose() {
    _query.dispose();
    super.dispose();
  }

  void _clearFilters() {
    _query.clear();
    setState(() => _filter = ListFilter(sort: _filter.sort));
  }

  void _toggle(String entryId) {
    final selection = _selection;
    if (selection == null) return;
    setState(
      () => _selection = toggled(
        selection,
        entryId,
        !selection.contains(entryId),
      ),
    );
  }

  Future<void> _openFilters(AlbumList list) async {
    final updated = await showModalBottomSheet<ListFilter>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) =>
          FilterSortSheet(list: list, initial: _filter, query: _query.text),
    );
    if (!mounted || updated == null) return;
    setState(() => _filter = updated);
  }

  Future<void> _openEntry(AlbumList list, ListEntry entry) async {
    final messenger = ScaffoldMessenger.of(context);
    final result = await showModalBottomSheet<EntrySheetResult>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => entry.isGhost
          ? GhostEntrySheet(list: list, entry: entry)
          : EditEntrySheet(list: list, entry: entry),
    );
    if (!mounted || result == null) return;
    final message = result.message;
    if (message != null) {
      showAppSnackBar(messenger, message);
    }
    final album = result.openAlbum;
    if (album != null) {
      await AppNav.openAlbum(context, album, tab: AppTab.library);
    }
  }

  Future<void> _onListAction(_ListAction action, AlbumList list) async {
    switch (action) {
      case _ListAction.select:
        setState(() => _selection = <String>{});
      case _ListAction.rename:
        await showListNameDialog(context, rename: list);
      case _ListAction.delete:
        {
          final library = AppScope.of(context).library;
          final navigator = Navigator.of(context);
          if (await confirmDeleteList(context, list)) {
            navigator.pop();
            library.deleteList(list.id);
          }
        }
    }
  }

  Future<void> _transferSelected(
    AlbumList list,
    Set<String> ids, {
    required bool move,
  }) async {
    final library = AppScope.of(context).library;
    final messenger = ScaffoldMessenger.of(context);
    final target = await pickTargetList(
      context,
      title: move ? 'Move to' : 'Copy to',
      excludeListId: list.id,
    );
    if (!mounted || target == null) return;

    final result = move
        ? library.moveEntries(list.id, target.id, ids)
        : library.copyEntries(list.id, target.id, ids);
    setState(() => _selection = null);
    showAppSnackBar(messenger, _bulkMessage(result, target.name, move));
  }

  String _bulkMessage(TransferResult result, String target, bool move) {
    final verb = move ? 'Moved' : 'Copied';
    final message = '$verb ${Formatting.albums(result.transferred)} to $target';
    if (result.skipped == 0) {
      return message;
    }
    return '$message · ${result.skipped} already there';
  }

  Future<void> _deleteSelected(AlbumList list, Set<String> ids) async {
    final library = AppScope.of(context).library;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await confirmAction(
      context,
      title: 'Remove ${Formatting.albums(ids.length)}?',
      message: 'They will be removed from ${list.name}.',
      confirmLabel: 'Remove',
    );
    if (!mounted || !confirmed) return;
    library.removeEntries(list.id, ids);
    setState(() => _selection = null);
    showAppSnackBar(messenger, 'Removed ${Formatting.albums(ids.length)}');
  }

  @override
  Widget build(BuildContext context) {
    final library = AppScope.of(context).library;
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final list = library.listById(widget.listId);
        if (list == null) {
          return Scaffold(
            appBar: AppBar(),
            body: const EmptyState(
              icon: Icons.view_week_outlined,
              title: 'List not found',
              message: 'This list was deleted.',
            ),
            bottomNavigationBar: const MainTaskbar(current: AppTab.library),
          );
        }

        final selection = _selection;
        final entries = _filter.apply(list.entries, _query.text);

        return PopScope(
          canPop: selection == null,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) {
              setState(() => _selection = null);
            }
          },
          child: Scaffold(
            appBar: selection == null
                ? _buildAppBar(list)
                : _buildSelectionBar(list, selection),
            body: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: TextField(
                    key: const Key('list.search'),
                    controller: _query,
                    onChanged: (_) => setState(() {}),
                    decoration: AppInputs.search(
                      'Search in ${list.name}',
                      suffixIcon: _query.text.isEmpty
                          ? null
                          : IconButton(
                              tooltip: 'Clear search',
                              icon: const Icon(Icons.close),
                              onPressed: () => setState(_query.clear),
                            ),
                    ),
                  ),
                ),
                _FilterChips(filter: _filter, onTap: () => _openFilters(list)),
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 8, 0),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          list.countLabel,
                          style: Theme.of(context).textTheme.bodyLarge
                              ?.copyWith(color: AppColors.textSecondary),
                        ),
                      ),
                      TextButton(
                        onPressed: () => _openFilters(list),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(_filter.sort.shortLabel),
                            const Icon(Icons.keyboard_arrow_down),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(child: _buildEntries(list, entries, selection)),
              ],
            ),
            bottomNavigationBar: selection == null
                ? const MainTaskbar(current: AppTab.library)
                : _BulkBar(
                    enabled: selection.isNotEmpty,
                    onMove: () =>
                        _transferSelected(list, selection, move: true),
                    onCopy: () =>
                        _transferSelected(list, selection, move: false),
                    onDelete: () => _deleteSelected(list, selection),
                  ),
          ),
        );
      },
    );
  }

  PreferredSizeWidget _buildAppBar(AlbumList list) {
    return AppBar(
      backgroundColor: Colors.white,
      scrolledUnderElevation: 0,
      title: Text(list.name),
      actions: [
        PopupMenuButton<_ListAction>(
          tooltip: 'List options',
          onSelected: (action) => _onListAction(action, list),
          itemBuilder: (context) => const [
            PopupMenuItem(
              value: _ListAction.select,
              child: Text('Select albums'),
            ),
            PopupMenuItem(
              value: _ListAction.rename,
              child: Text('Rename list'),
            ),
            PopupMenuItem(
              value: _ListAction.delete,
              child: Text('Delete list'),
            ),
          ],
        ),
      ],
    );
  }

  PreferredSizeWidget _buildSelectionBar(
    AlbumList list,
    Set<String> selection,
  ) {
    return AppBar(
      backgroundColor: Colors.white,
      scrolledUnderElevation: 0,
      leading: IconButton(
        tooltip: 'Cancel selection',
        icon: const Icon(Icons.close),
        onPressed: () => setState(() => _selection = null),
      ),
      title: Text('${selection.length} selected'),
      actions: [
        IconButton(
          tooltip: 'Delete selected',
          icon: const Icon(Icons.delete_outline),
          onPressed: selection.isEmpty
              ? null
              : () => _deleteSelected(list, selection),
        ),
      ],
    );
  }

  Widget _buildEntries(
    AlbumList list,
    List<ListEntry> entries,
    Set<String>? selection,
  ) {
    if (list.entries.isEmpty) {
      return EmptyState(
        icon: Icons.album_outlined,
        title: 'Nothing in this list yet',
        message: 'Scan an album and tap + to save it here.',
        actions: [
          FilledButton.icon(
            onPressed: () => AppNav.switchTab(context, AppTab.scan),
            icon: const Icon(Icons.photo_camera_outlined),
            label: const Text('Scan an album'),
          ),
        ],
      );
    }
    if (entries.isEmpty) {
      return EmptyState(
        icon: Icons.search,
        title: 'No albums match',
        message: 'Try a different search or remove some filters.',
        actions: [
          OutlinedButton(
            onPressed: _clearFilters,
            child: const Text('Clear filters'),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.only(bottom: 24),
      itemCount: entries.length,
      separatorBuilder: (context, index) =>
          const Divider(indent: 96, height: 1),
      itemBuilder: (context, index) {
        final entry = entries[index];
        return _EntryRow(
          entry: entry,
          selecting: selection != null,
          selected: selection?.contains(entry.id) ?? false,
          onTap: selection != null
              ? () => _toggle(entry.id)
              : () =>
                    AppNav.openAlbum(context, entry.album, tab: AppTab.library),
          onLongPress: selection != null
              ? null
              : () => setState(() => _selection = {entry.id}),
          onMore: () => _openEntry(list, entry),
        );
      },
    );
  }
}

class _FilterChips extends StatelessWidget {
  const _FilterChips({required this.filter, required this.onTap});

  final ListFilter filter;
  final VoidCallback onTap;

  static String _label(String name, Set<String> values) {
    if (values.isEmpty) {
      return name;
    }
    if (values.length == 1) {
      return '$name: ${values.first}';
    }
    return '$name: ${values.length}';
  }

  @override
  Widget build(BuildContext context) {
    final chips = <(String, bool)>[
      (_label('Artist', filter.artists), filter.artists.isNotEmpty),
      (_label('Genre', filter.genres), filter.genres.isNotEmpty),
      (
        filter.hasYearRange
            ? '${filter.fromYear ?? '…'}–${filter.toYear ?? '…'}'
            : 'Year',
        filter.hasYearRange,
      ),
      (
        _label('Format', {for (final f in filter.formats) f.label}),
        filter.formats.isNotEmpty,
      ),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          for (final (label, active) in chips)
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                selected: active,
                onSelected: (_) => onTap(),
                label: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label),
                    const SizedBox(width: 2),
                    const Icon(Icons.keyboard_arrow_down, size: 18),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({
    required this.entry,
    required this.selecting,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onMore,
  });

  final ListEntry entry;
  final bool selecting;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final album = entry.album;
    final ghost = entry.isGhost;
    final muted = ghost ? AppColors.textMuted : null;

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      child: Padding(
        padding: EdgeInsets.fromLTRB(selecting ? 8 : 20, 8, 4, 8),
        child: Row(
          children: [
            if (selecting) Checkbox(value: selected, onChanged: (_) => onTap()),
            AlbumArt(album: album, ghost: ghost, size: 60),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    album.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleMedium?.copyWith(color: muted),
                  ),
                  Text(
                    album.artistYear,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.bodyMedium?.copyWith(color: muted),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FormatBadge(
              label: ghost ? 'Ghost' : (entry.format ?? album.format).label,
              outlined: ghost,
            ),
            if (selecting)
              const SizedBox(width: 12)
            else
              IconButton(
                tooltip: 'Options for ${album.title}',
                icon: const Icon(Icons.more_vert),
                onPressed: onMore,
              ),
          ],
        ),
      ),
    );
  }
}

class _BulkBar extends StatelessWidget {
  const _BulkBar({
    required this.enabled,
    required this.onMove,
    required this.onCopy,
    required this.onDelete,
  });

  final bool enabled;
  final VoidCallback onMove;
  final VoidCallback onCopy;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surfaceMuted,
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              _BulkButton(
                icon: Icons.swap_horiz,
                label: 'Move',
                onTap: enabled ? onMove : null,
              ),
              _BulkButton(
                icon: Icons.content_copy,
                label: 'Copy',
                onTap: enabled ? onCopy : null,
              ),
              _BulkButton(
                icon: Icons.delete_outline,
                label: 'Delete',
                onTap: enabled ? onDelete : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BulkButton extends StatelessWidget {
  const _BulkButton({required this.icon, required this.label, this.onTap});

  final IconData icon;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = onTap == null ? AppColors.textMuted : AppColors.inkDeep;
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: color),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: color,
                  fontSize: 14,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
