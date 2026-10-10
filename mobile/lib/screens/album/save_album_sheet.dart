import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../models/album.dart';
import '../../models/library.dart';
import '../../routing/app_navigation.dart';
import '../../state/library_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/sign_in_prompt.dart';
import '../library/list_dialogs.dart';

class SaveAlbumResult {
  const SaveAlbumResult({
    required this.listId,
    required this.listName,
    this.saved = true,
  });

  final String listId;
  final String listName;

  /// False when the user chose "View entry" for an existing entry instead.
  final bool saved;
}

/// Saves [album] to a collection or wishlist (UC-10, UC-11).
///
/// Guests get the sign-in prompt first (13).
Future<void> startSaveAlbum(
  BuildContext context,
  Album album,
  ListKind kind,
) async {
  final deps = AppScope.of(context);
  if (!deps.auth.isSignedIn) {
    final signedIn = await showSignInPrompt(context);
    if (!signedIn || !context.mounted) return;
  }

  final messenger = ScaffoldMessenger.of(context);
  final result = await showModalBottomSheet<SaveAlbumResult>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => SaveAlbumSheet(album: album, initialKind: kind),
  );
  if (result == null || !context.mounted) return;

  if (!result.saved) {
    await AppNav.openList(context, result.listId);
    return;
  }
  showAppSnackBar(
    messenger,
    'Saved to ${result.listName}',
    actionLabel: 'VIEW',
    onAction: () {
      if (context.mounted) {
        AppNav.openList(context, result.listId);
      }
    },
  );
}

/// "Save album" bottom sheet (wireframe 12).
class SaveAlbumSheet extends StatefulWidget {
  const SaveAlbumSheet({
    super.key,
    required this.album,
    required this.initialKind,
  });

  final Album album;
  final ListKind initialKind;

  @override
  State<SaveAlbumSheet> createState() => _SaveAlbumSheetState();
}

class _SaveAlbumSheetState extends State<SaveAlbumSheet> {
  late ListKind _kind = widget.initialKind;
  late MediaFormat _format = AppScope.of(context).settings.defaultFormat;
  String? _listId;
  bool _ghost = false;

  String? _selectedId(List<AlbumList> lists) {
    final wanted = _listId;
    if (wanted != null && lists.any((list) => list.id == wanted)) {
      return wanted;
    }
    return lists.isEmpty ? null : lists.first.id;
  }

  Future<void> _createList() async {
    final id = await showListNameDialog(context, kind: _kind, lockKind: true);
    if (!mounted || id == null) return;
    setState(() => _listId = id);
  }

  void _save(LibraryStore library, AlbumList list) {
    final isCollection = _kind == ListKind.collection;
    final result = library.addAlbum(
      listId: list.id,
      album: widget.album,
      format: isCollection ? _format : null,
      ghost: isCollection && _ghost,
    );
    if (result == AddAlbumResult.added) {
      Navigator.of(
        context,
      ).pop(SaveAlbumResult(listId: list.id, listName: list.name));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final library = AppScope.of(context).library;

    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final isCollection = _kind == ListKind.collection;
        final lists = library.listsOf(_kind);
        final selectedId = _selectedId(lists);
        final selected = selectedId == null
            ? null
            : library.listById(selectedId);
        final duplicateIn =
            selected != null && selected.containsAlbum(widget.album.id)
            ? selected
            : null;

        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(context).bottom,
          ),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Save album', style: theme.textTheme.headlineSmall),
                const SizedBox(height: 16),
                SegmentedButton<ListKind>(
                  segments: const [
                    ButtonSegment(
                      value: ListKind.collection,
                      label: Text('Collection'),
                    ),
                    ButtonSegment(
                      value: ListKind.wishlist,
                      label: Text('Wishlist'),
                    ),
                  ],
                  selected: {_kind},
                  onSelectionChanged: (selection) => setState(() {
                    _kind = selection.first;
                    _listId = null;
                  }),
                  style: SegmentedButton.styleFrom(
                    foregroundColor: AppColors.inkDeep,
                    selectedForegroundColor: AppColors.inkDeep,
                    selectedBackgroundColor: AppColors.surfaceStrong,
                    side: const BorderSide(color: AppColors.ink),
                  ),
                ),
                if (duplicateIn != null) ...[
                  const SizedBox(height: 12),
                  InfoBanner(
                    message: "Already in '${duplicateIn.name}'",
                    action: TextButton(
                      onPressed: () => Navigator.of(context).pop(
                        SaveAlbumResult(
                          listId: duplicateIn.id,
                          listName: duplicateIn.name,
                          saved: false,
                        ),
                      ),
                      child: const Text('View entry'),
                    ),
                  ),
                ],
                const SizedBox(height: 20),
                SectionLabel(
                  isCollection ? 'Choose a collection' : 'Choose a wishlist',
                ),
                const SizedBox(height: 4),
                for (final list in lists)
                  _ListChoice(
                    list: list,
                    selected: list.id == selectedId,
                    onTap: () => setState(() => _listId = list.id),
                  ),
                InkWell(
                  onTap: _createList,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    child: Row(
                      children: [
                        const SizedBox(width: 2),
                        const Icon(Icons.add),
                        const SizedBox(width: 16),
                        Text(
                          isCollection ? 'New collection' : 'New wishlist',
                          style: theme.textTheme.titleMedium,
                        ),
                      ],
                    ),
                  ),
                ),
                if (isCollection) ...[
                  const SizedBox(height: 8),
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.surfaceMuted,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: CheckboxListTile(
                      value: _ghost,
                      onChanged: (value) =>
                          setState(() => _ghost = value ?? false),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 8,
                      ),
                      title: const Text("Add as ghost – I don't own it yet"),
                      subtitle: const Text(
                        'Shows as a faded placeholder in this collection',
                      ),
                    ),
                  ),
                ],
                if (isCollection && !_ghost) ...[
                  const SizedBox(height: 20),
                  const SectionLabel('Format'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      for (final format in MediaFormat.values)
                        ChoiceChip(
                          label: Text(format.label),
                          selected: _format == format,
                          onSelected: (_) => setState(() => _format = format),
                        ),
                    ],
                  ),
                ],
                const SizedBox(height: 28),
                Row(
                  children: [
                    Expanded(
                      child: TextButton(
                        onPressed: () => Navigator.of(context).pop(),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: FilledButton(
                        key: const Key('saveAlbum.save'),
                        onPressed: selected == null || duplicateIn != null
                            ? null
                            : () => _save(library, selected),
                        child: const Text('Save'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _ListChoice extends StatelessWidget {
  const _ListChoice({
    required this.list,
    required this.selected,
    required this.onTap,
  });

  final AlbumList list;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      selected: selected,
      button: true,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              ChoiceMark(selected: selected),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(list.name, style: theme.textTheme.titleMedium),
                    Text(
                      list.countLabel,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
