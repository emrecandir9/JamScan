import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../models/library.dart';
import '../../routing/app_navigation.dart';
import '../../state/shell_controller.dart';
import '../../theme/app_theme.dart';
import '../../widgets/album_art.dart';
import '../../widgets/common.dart';
import '../../widgets/taskbars.dart';
import 'list_dialogs.dart';

/// Library tab: collections and wishlists (15a lists, 15b empty, 15c guest).
class LibraryScreen extends StatefulWidget {
  const LibraryScreen({super.key});

  @override
  State<LibraryScreen> createState() => _LibraryScreenState();
}

class _LibraryScreenState extends State<LibraryScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabs = TabController(length: 2, vsync: this);
  final TextEditingController _filter = TextEditingController();
  bool _searching = false;

  @override
  void dispose() {
    _tabs.dispose();
    _filter.dispose();
    super.dispose();
  }

  ListKind get _currentKind =>
      _tabs.index == 0 ? ListKind.collection : ListKind.wishlist;

  Future<void> _createList() async {
    final id = await showListNameDialog(context, kind: _currentKind);
    if (!mounted || id == null) return;
    final list = AppScope.of(context).library.listById(id);
    if (list != null) {
      _tabs.animateTo(list.kind == ListKind.collection ? 0 : 1);
    }
  }

  void _toggleSearch() {
    setState(() {
      _searching = !_searching;
      if (!_searching) {
        _filter.clear();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final deps = AppScope.of(context);
    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: ListenableBuilder(
          listenable: Listenable.merge([deps.auth, deps.library]),
          builder: (context, _) {
            if (!deps.auth.isSignedIn) {
              return const _GuestLibrary();
            }
            return Column(
              children: [
                _Header(
                  onSearch: _toggleSearch,
                  onCreate: _createList,
                  searching: _searching,
                ),
                if (_searching)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
                    child: TextField(
                      key: const Key('library.filter'),
                      controller: _filter,
                      autofocus: true,
                      onChanged: (_) => setState(() {}),
                      decoration: AppInputs.search('Search your lists'),
                    ),
                  ),
                TabBar(
                  controller: _tabs,
                  tabs: const [
                    Tab(text: 'Collections'),
                    Tab(text: 'Wishlists'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    controller: _tabs,
                    children: [
                      _ListGrid(
                        kind: ListKind.collection,
                        filter: _filter.text,
                        onCreate: _createList,
                      ),
                      _ListGrid(
                        kind: ListKind.wishlist,
                        filter: _filter.text,
                        onCreate: _createList,
                      ),
                    ],
                  ),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: const MainTaskbar(current: AppTab.library),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.onSearch,
    required this.onCreate,
    required this.searching,
  });

  final VoidCallback onSearch;
  final VoidCallback onCreate;
  final bool searching;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Library',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
          ),
          IconButton(
            tooltip: searching ? 'Close search' : 'Search library',
            icon: Icon(searching ? Icons.close : Icons.search),
            onPressed: onSearch,
          ),
          IconButton(
            tooltip: 'New list',
            icon: const Icon(Icons.add),
            onPressed: onCreate,
          ),
        ],
      ),
    );
  }
}

class _GuestLibrary extends StatelessWidget {
  const _GuestLibrary();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
          child: SizedBox(
            height: 48,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                'Library',
                style: Theme.of(context).textTheme.headlineMedium,
              ),
            ),
          ),
        ),
        Expanded(
          child: EmptyState(
            icon: Icons.person_outline,
            title: 'Sign in to build your library',
            message:
                'Save albums you own, keep wishlists and revisit your scan '
                'history.',
            actions: [
              FilledButton(
                onPressed: () => AppNav.signIn(context),
                child: const Text('Sign in'),
              ),
              OutlinedButton(
                onPressed: () => AppNav.signIn(context, register: true),
                child: const Text('Create account'),
              ),
              TextButton(
                onPressed: () => AppNav.switchTab(context, AppTab.scan),
                child: const Text('Keep scanning as guest'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ListGrid extends StatelessWidget {
  const _ListGrid({
    required this.kind,
    required this.filter,
    required this.onCreate,
  });

  final ListKind kind;
  final String filter;
  final VoidCallback onCreate;

  bool _matches(AlbumList list, String query) {
    if (query.isEmpty) {
      return true;
    }
    if (list.name.toLowerCase().contains(query)) {
      return true;
    }
    return list.entries.any(
      (entry) =>
          entry.album.title.toLowerCase().contains(query) ||
          entry.album.artist.toLowerCase().contains(query),
    );
  }

  Future<void> _showListOptions(BuildContext context, AlbumList list) async {
    final library = AppScope.of(context).library;
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('Rename list'),
              onTap: () => Navigator.of(context).pop('rename'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Delete list'),
              onTap: () => Navigator.of(context).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (action == 'rename') {
      await showListNameDialog(context, rename: list);
    } else if (action == 'delete') {
      if (await confirmDeleteList(context, list)) {
        library.deleteList(list.id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final library = AppScope.of(context).library;
    final all = library.listsOf(kind);
    final query = filter.trim().toLowerCase();
    final lists = all.where((list) => _matches(list, query)).toList();

    if (all.isEmpty) {
      if (kind == ListKind.collection) {
        return EmptyState(
          icon: Icons.view_week_outlined,
          title: 'Your library is empty',
          message: 'Scan an album cover and save it to start your collection.',
          actions: [
            FilledButton.icon(
              onPressed: () => AppNav.switchTab(context, AppTab.scan),
              icon: const Icon(Icons.photo_camera_outlined),
              label: const Text('Scan an album'),
            ),
          ],
        );
      }
      return EmptyState(
        icon: Icons.favorite_border,
        title: 'No wishlists yet',
        message: 'Keep track of albums you want to find next.',
        actions: [
          FilledButton.icon(
            onPressed: onCreate,
            icon: const Icon(Icons.add),
            label: const Text('New wishlist'),
          ),
        ],
      );
    }

    if (lists.isEmpty) {
      return const EmptyState(
        icon: Icons.search,
        title: 'No lists match',
        message: 'Try a list name, an album title or an artist.',
      );
    }

    return GridView.builder(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: 20,
        crossAxisSpacing: 16,
        childAspectRatio: 0.7,
      ),
      itemCount: lists.length,
      itemBuilder: (context, index) {
        final list = lists[index];
        return _ListCard(
          list: list,
          onTap: () => AppNav.openList(context, list.id),
          onLongPress: () => _showListOptions(context, list),
        );
      },
    );
  }
}

class _ListCard extends StatelessWidget {
  const _ListCard({
    required this.list,
    required this.onTap,
    required this.onLongPress,
  });

  final AlbumList list;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final covers = list.entries.take(4).toList();

    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 1,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final tile = (constraints.maxWidth - 2) / 2;
                return Wrap(
                  spacing: 2,
                  runSpacing: 2,
                  children: [
                    for (var i = 0; i < 4; i++)
                      if (i < covers.length)
                        AlbumArt(
                          album: covers[i].album,
                          ghost: covers[i].isGhost,
                          size: tile,
                          radius: 0,
                        )
                      else
                        Container(
                          width: tile,
                          height: tile,
                          color: AppColors.surfaceMuted,
                        ),
                  ],
                );
              },
            ),
          ),
          const SizedBox(height: 10),
          Text(
            list.name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.titleMedium,
          ),
          Text(
            list.countLabel,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
