import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../models/album.dart';
import '../../models/library.dart';
import '../../state/library_store.dart';
import '../../theme/app_theme.dart';
import '../../widgets/album_art.dart';
import 'list_dialogs.dart';

/// What the list page should do after an entry sheet closes.
class EntrySheetResult {
  const EntrySheetResult({this.message, this.openAlbum});

  /// Shown in a snack bar.
  final String? message;

  /// Open the album page ("Play previews" on a ghost).
  final Album? openAlbum;
}

String _transferMessage(TransferResult result, String target, bool move) {
  if (result.transferred == 0) {
    return 'Already in $target';
  }
  return move ? 'Moved to $target' : 'Copied to $target';
}

/// Edit entry / move / remove (wireframe 18).
class EditEntrySheet extends StatefulWidget {
  const EditEntrySheet({super.key, required this.list, required this.entry});

  final AlbumList list;
  final ListEntry entry;

  @override
  State<EditEntrySheet> createState() => _EditEntrySheetState();
}

class _EditEntrySheetState extends State<EditEntrySheet> {
  late MediaFormat _format = widget.entry.format ?? widget.entry.album.format;
  late String? _condition = widget.entry.condition;
  late final TextEditingController _notes = TextEditingController(
    text: widget.entry.notes,
  );

  @override
  void dispose() {
    _notes.dispose();
    super.dispose();
  }

  void _applyEdits(LibraryStore library) {
    library.updateEntry(
      widget.list.id,
      widget.entry.id,
      format: _format,
      condition: _condition,
      notes: _notes.text.trim(),
    );
  }

  void _save() {
    _applyEdits(AppScope.of(context).library);
    Navigator.of(context).pop(const EntrySheetResult(message: 'Changes saved'));
  }

  Future<void> _transfer({required bool move}) async {
    final library = AppScope.of(context).library;
    final target = await pickTargetList(
      context,
      title: move ? 'Move to' : 'Copy to',
      excludeListId: widget.list.id,
    );
    if (!mounted || target == null) return;
    _applyEdits(library);
    final ids = {widget.entry.id};
    final result = move
        ? library.moveEntries(widget.list.id, target.id, ids)
        : library.copyEntries(widget.list.id, target.id, ids);
    Navigator.of(
      context,
    ).pop(EntrySheetResult(message: _transferMessage(result, target.name, move)));
  }

  void _remove() {
    AppScope.of(context).library.removeEntries(widget.list.id, {
      widget.entry.id,
    });
    Navigator.of(
      context,
    ).pop(EntrySheetResult(message: 'Removed from ${widget.list.name}'));
  }

  @override
  Widget build(BuildContext context) {
    final album = widget.entry.album;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _EntryHeader(album: album),
            const SizedBox(height: 24),
            Row(
              children: [
                Expanded(
                  child: PickerField(
                    label: 'Format',
                    value: _format.label,
                    options: [for (final f in MediaFormat.values) f.label],
                    onSelected: (index) =>
                        setState(() => _format = MediaFormat.values[index]),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: PickerField(
                    label: 'Condition',
                    value: _condition ?? 'Not set',
                    options: mediaConditions,
                    onSelected: (index) =>
                        setState(() => _condition = mediaConditions[index]),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            TextField(
              controller: _notes,
              minLines: 2,
              maxLines: 4,
              textCapitalization: TextCapitalization.sentences,
              decoration: AppInputs.outlined('Notes'),
            ),
            const SizedBox(height: 8),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.swap_horiz),
              title: const Text('Move to another list'),
              onTap: () => _transfer(move: true),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.content_copy),
              title: const Text('Copy to another list'),
              onTap: () => _transfer(move: false),
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.delete_outline),
              title: Text('Remove from ${widget.list.name}'),
              onTap: _remove,
            ),
            const SizedBox(height: 16),
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
                    onPressed: _save,
                    child: const Text('Save'),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Ghost record actions (wireframe 18b).
class GhostEntrySheet extends StatefulWidget {
  const GhostEntrySheet({super.key, required this.list, required this.entry});

  final AlbumList list;
  final ListEntry entry;

  @override
  State<GhostEntrySheet> createState() => _GhostEntrySheetState();
}

class _GhostEntrySheetState extends State<GhostEntrySheet> {
  late final TextEditingController _lookingFor = TextEditingController(
    text: widget.entry.lookingFor,
  );

  @override
  void dispose() {
    _lookingFor.dispose();
    super.dispose();
  }

  void _saveNote(LibraryStore library) {
    final text = _lookingFor.text.trim();
    if (text != widget.entry.lookingFor) {
      library.updateEntry(widget.list.id, widget.entry.id, lookingFor: text);
    }
  }

  void _markOwned() {
    final deps = AppScope.of(context);
    _saveNote(deps.library);
    deps.library.markOwned(
      widget.list.id,
      widget.entry.id,
      deps.settings.defaultFormat,
    );
    Navigator.of(context).pop(
      EntrySheetResult(message: 'Marked as owned in ${widget.list.name}'),
    );
  }

  Future<void> _moveToWishlist() async {
    final library = AppScope.of(context).library;
    _saveNote(library);
    final target = await pickTargetList(
      context,
      title: 'Move to a wishlist',
      kind: ListKind.wishlist,
    );
    if (!mounted || target == null) return;
    final result = library.moveEntries(widget.list.id, target.id, {
      widget.entry.id,
    });
    Navigator.of(context).pop(
      EntrySheetResult(message: _transferMessage(result, target.name, true)),
    );
  }

  void _playPreviews() {
    _saveNote(AppScope.of(context).library);
    Navigator.of(context).pop(EntrySheetResult(openAlbum: widget.entry.album));
  }

  void _remove() {
    AppScope.of(context).library.removeEntries(widget.list.id, {
      widget.entry.id,
    });
    Navigator.of(context).pop(const EntrySheetResult(message: 'Ghost removed'));
  }

  @override
  Widget build(BuildContext context) {
    final album = widget.entry.album;
    return PopScope(
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          _saveNote(AppScope.of(context).library);
        }
      },
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _EntryHeader(album: album, ghostIn: widget.list.name),
              const SizedBox(height: 24),
              TextField(
                controller: _lookingFor,
                textCapitalization: TextCapitalization.sentences,
                decoration: AppInputs.outlined('Looking for'),
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: _markOwned,
                icon: const Icon(Icons.check),
                label: const Text('I bought it – mark as owned'),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: _moveToWishlist,
                child: const Text('Move to a wishlist'),
              ),
              const SizedBox(height: 8),
              TextButton.icon(
                onPressed: _playPreviews,
                icon: const Icon(Icons.play_arrow),
                label: const Text('Play previews'),
              ),
              TextButton.icon(
                onPressed: _remove,
                icon: const Icon(Icons.delete_outline),
                label: const Text('Remove ghost'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EntryHeader extends StatelessWidget {
  const _EntryHeader({required this.album, this.ghostIn});

  final Album album;

  /// List name for the "Ghost in …" tag.
  final String? ghostIn;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final ghostIn = this.ghostIn;
    return Row(
      children: [
        AlbumArt(album: album, ghost: ghostIn != null, size: 72),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(album.title, style: theme.textTheme.titleLarge),
              Text(album.artistYear, style: theme.textTheme.bodyMedium),
              if (ghostIn != null) ...[
                const SizedBox(height: 4),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.inkDeep),
                  ),
                  child: Text(
                    'Ghost in $ghostIn',
                    style: const TextStyle(fontSize: 13),
                  ),
                ),
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Outlined field that opens a list of options, like a dropdown.
class PickerField extends StatelessWidget {
  const PickerField({
    super.key,
    required this.label,
    required this.value,
    required this.options,
    required this.onSelected,
  });

  final String label;
  final String value;
  final List<String> options;
  final ValueChanged<int> onSelected;

  Future<void> _pick(BuildContext context) async {
    final index = await showModalBottomSheet<int>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (context) => SingleChildScrollView(
        padding: const EdgeInsets.only(bottom: 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
              child: Text(
                label,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            for (var i = 0; i < options.length; i++)
              ListTile(
                title: Text(options[i]),
                trailing: options[i] == value ? const Icon(Icons.check) : null,
                onTap: () => Navigator.of(context).pop(i),
              ),
          ],
        ),
      ),
    );
    if (index != null) {
      onSelected(index);
    }
  }

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: () => _pick(context),
      borderRadius: BorderRadius.circular(8),
      child: InputDecorator(
        decoration: AppInputs.outlined(
          label,
        ).copyWith(suffixIcon: const Icon(Icons.keyboard_arrow_down)),
        child: Text(value, style: const TextStyle(fontSize: 16)),
      ),
    );
  }
}
