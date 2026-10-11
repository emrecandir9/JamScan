import 'package:flutter/material.dart';

import '../routing/app_navigation.dart';
import '../state/shell_controller.dart';
import '../theme/app_theme.dart';

/// One destination in a taskbar.
class TaskbarItem {
  const TaskbarItem({
    required this.key,
    required this.label,
    required this.icon,
    required this.onTap,
    this.selected = false,
  });

  final Key key;
  final String label;
  final Widget icon;
  final VoidCallback onTap;
  final bool selected;
}

/// Rounded bottom bar used on every page of the wireframes.
class Taskbar extends StatelessWidget {
  const Taskbar({super.key, required this.items});

  final List<TaskbarItem> items;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.surfaceMuted,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        border: Border(top: BorderSide(color: AppColors.divider)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Row(
            children: [
              for (final item in items) Expanded(child: _TaskbarButton(item)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TaskbarButton extends StatelessWidget {
  const _TaskbarButton(this.item);

  final TaskbarItem item;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: item.selected,
      child: InkWell(
        key: item.key,
        onTap: item.onTap,
        borderRadius: BorderRadius.circular(20),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 60,
                height: 34,
                decoration: BoxDecoration(
                  color: item.selected
                      ? AppColors.surfaceStrong
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(17),
                ),
                child: Center(
                  child: IconTheme(
                    data: const IconThemeData(
                      color: AppColors.inkDeep,
                      size: 26,
                    ),
                    child: item.icon,
                  ),
                ),
              ),
              const SizedBox(height: 4),
              Text(
                item.label,
                style: TextStyle(
                  fontSize: 14,
                  color: AppColors.inkDeep,
                  fontWeight: item.selected ? FontWeight.w600 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The record icon used for Scan.
class ScanGlyph extends StatelessWidget {
  const ScanGlyph({super.key});

  @override
  Widget build(BuildContext context) {
    return const Icon(Icons.album, size: 30);
  }
}

/// Taskbar on scan pages: History, Scan, Search.
class ScanTaskbar extends StatelessWidget {
  const ScanTaskbar({
    super.key,
    required this.onHistory,
    required this.onScan,
    required this.onSearch,
  });

  final VoidCallback onHistory;
  final VoidCallback onScan;
  final VoidCallback onSearch;

  @override
  Widget build(BuildContext context) {
    return Taskbar(
      items: [
        TaskbarItem(
          key: const Key('taskbar.history'),
          label: 'History',
          icon: const Icon(Icons.history),
          onTap: onHistory,
        ),
        TaskbarItem(
          key: const Key('taskbar.scan'),
          label: 'Scan',
          icon: const ScanGlyph(),
          onTap: onScan,
          selected: true,
        ),
        TaskbarItem(
          key: const Key('taskbar.search'),
          label: 'Search',
          icon: const Icon(Icons.search),
          onTap: onSearch,
        ),
      ],
    );
  }
}

/// Taskbar on all other pages: Profile, Scan, Library.
class MainTaskbar extends StatelessWidget {
  const MainTaskbar({super.key, required this.current});

  /// The highlighted destination.
  final AppTab current;

  @override
  Widget build(BuildContext context) {
    return Taskbar(
      items: [
        TaskbarItem(
          key: const Key('taskbar.profile'),
          label: 'Profile',
          icon: const Icon(Icons.person_outline),
          selected: current == AppTab.profile,
          onTap: () => AppNav.switchTab(context, AppTab.profile),
        ),
        TaskbarItem(
          key: const Key('taskbar.scan'),
          label: 'Scan',
          icon: const ScanGlyph(),
          selected: current == AppTab.scan,
          onTap: () => AppNav.switchTab(context, AppTab.scan),
        ),
        TaskbarItem(
          key: const Key('taskbar.library'),
          label: 'Library',
          icon: const Icon(Icons.view_week_outlined),
          selected: current == AppTab.library,
          onTap: () => AppNav.switchTab(context, AppTab.library),
        ),
      ],
    );
  }
}
