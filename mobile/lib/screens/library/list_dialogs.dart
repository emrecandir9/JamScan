import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../models/library.dart';
import '../../theme/app_theme.dart';

/// New list or rename list dialog (19a). Completes with the list id.
Future<String?> showListNameDialog(
  BuildContext context, {
  ListKind kind = ListKind.collection,
  AlbumList? rename,
  bool lockKind = false,
}) {
  return showDialog<String>(
    context: context,
    builder: (context) =>
        _ListNameDialog(initialKind: kind, rename: rename, lockKind: lockKind),
  );
}

class _ListNameDialog extends StatefulWidget {
  const _ListNameDialog({
    required this.initialKind,
    required this.rename,
    required this.lockKind,
  });

  final ListKind initialKind;
  final AlbumList? rename;
  final bool lockKind;

  @override
  State<_ListNameDialog> createState() => _ListNameDialogState();
}

class _ListNameDialogState extends State<_ListNameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.rename?.name ?? '',
  );
  late ListKind _kind = widget.initialKind;
  bool _attempted = false;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _submit() {
    final library = AppScope.of(context).library;
    final name = _name.text.trim();
    final rename = widget.rename;
    if (name.isEmpty) {
      setState(() => _attempted = true);
      return;
    }
    if (library.nameExists(name, exceptListId: rename?.id)) {
      return;
    }
    if (rename == null) {
      Navigator.of(context).pop(library.createList(name, _kind));
    } else {
      library.renameList(rename.id, name);
      Navigator.of(context).pop(rename.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = AppScope.of(context).library;
    final rename = widget.rename;
    final name = _name.text.trim();
    final exists =
        name.isNotEmpty && library.nameExists(name, exceptListId: rename?.id);
    String? error;
    if (exists) {
      error = 'A list with this name already exists';
    } else if (_attempted && name.isEmpty) {
      error = 'Enter a name for the list';
    }

    return AlertDialog(
      title: Text(rename == null ? 'New list' : 'Rename list'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (rename == null && !widget.lockKind) ...[
            Wrap(
              spacing: 8,
              children: [
                for (final kind in ListKind.values)
                  ChoiceChip(
                    label: Text(kind.label),
                    selected: _kind == kind,
                    onSelected: (_) => setState(() => _kind = kind),
                  ),
              ],
            ),
            const SizedBox(height: 20),
          ],
          TextField(
            key: const Key('listName.field'),
            controller: _name,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: AppInputs.outlined('List name'),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) => _submit(),
          ),
          if (error != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.warning_amber_rounded, size: 18),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(error, style: const TextStyle(fontSize: 14)),
                ),
              ],
            ),
          ],
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(
          key: const Key('listName.confirm'),
          onPressed: exists ? null : _submit,
          child: Text(rename == null ? 'Create' : 'Save'),
        ),
      ],
    );
  }
}

/// Delete list confirmation (19b). Completes with `true` to delete.
Future<bool> confirmDeleteList(BuildContext context, AlbumList list) async {
  final count = list.entries.length;
  final contents = count == 0
      ? 'This list is empty.'
      : 'This list contains ${count == 1 ? '1 album' : '$count albums'}. '
            'They will be removed from this list.';
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text("Delete '${list.name}'?"),
      content: Text('$contents This cannot be undone.'),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Delete'),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Generic confirmation dialog.
Future<bool> confirmAction(
  BuildContext context, {
  required String title,
  required String message,
  required String confirmLabel,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(message),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// Picks the list to move or copy albums to.
Future<AlbumList?> pickTargetList(
  BuildContext context, {
  required String title,
  String? excludeListId,
  ListKind? kind,
}) {
  return showModalBottomSheet<AlbumList>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (context) => _ListPickerSheet(
      title: title,
      excludeListId: excludeListId,
      kind: kind,
    ),
  );
}

class _ListPickerSheet extends StatelessWidget {
  const _ListPickerSheet({
    required this.title,
    required this.excludeListId,
    required this.kind,
  });

  final String title;
  final String? excludeListId;
  final ListKind? kind;

  @override
  Widget build(BuildContext context) {
    final library = AppScope.of(context).library;
    return ListenableBuilder(
      listenable: library,
      builder: (context, _) {
        final lists = library.lists
            .where(
              (list) =>
                  list.id != excludeListId &&
                  (kind == null || list.kind == kind),
            )
            .toList();
        return SingleChildScrollView(
          padding: const EdgeInsets.only(bottom: 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.headlineSmall,
                ),
              ),
              for (final list in lists)
                ListTile(
                  leading: Icon(
                    list.kind == ListKind.collection
                        ? Icons.view_week_outlined
                        : Icons.favorite_border,
                  ),
                  title: Text(list.name),
                  subtitle: Text(list.countLabel),
                  onTap: () => Navigator.of(context).pop(list),
                ),
              ListTile(
                leading: const Icon(Icons.add),
                title: Text(
                  kind == ListKind.wishlist ? 'New wishlist' : 'New list',
                ),
                onTap: () async {
                  final id = await showListNameDialog(
                    context,
                    kind: kind ?? ListKind.collection,
                    lockKind: kind != null,
                  );
                  if (id == null || !context.mounted) return;
                  Navigator.of(context).pop(library.listById(id));
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
