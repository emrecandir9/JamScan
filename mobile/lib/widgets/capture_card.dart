import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Floating card on the camera page: Gallery, shutter, Library.
class CaptureCard extends StatelessWidget {
  const CaptureCard({
    super.key,
    required this.onGallery,
    required this.onShutter,
    required this.onLibrary,
    this.busy = false,
    this.light = false,
  });

  final VoidCallback onGallery;
  final VoidCallback onShutter;
  final VoidCallback onLibrary;

  /// Disables the buttons while a capture or import is running.
  final bool busy;

  /// Light variant shown when camera access is off.
  final bool light;

  @override
  Widget build(BuildContext context) {
    final background = light ? AppColors.surfaceMuted : AppColors.cameraChrome;
    final border = light ? AppColors.divider : const Color(0xFF3A3A3A);
    final label = light ? AppColors.inkDeep : Colors.white;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 12),
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AppSpacing.cardRadius + 8),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _SideButton(
            key: const Key('capture.gallery'),
            label: 'Gallery',
            icon: Icons.image_outlined,
            labelColor: label,
            light: light,
            highlighted: true,
            onTap: busy ? null : onGallery,
          ),
          _Shutter(light: light, busy: busy, onTap: busy ? null : onShutter),
          _SideButton(
            key: const Key('capture.library'),
            label: 'Library',
            icon: Icons.view_week_outlined,
            labelColor: label,
            light: light,
            highlighted: false,
            onTap: onLibrary,
          ),
        ],
      ),
    );
  }
}

class _SideButton extends StatelessWidget {
  const _SideButton({
    super.key,
    required this.label,
    required this.icon,
    required this.labelColor,
    required this.light,
    required this.highlighted,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final Color labelColor;
  final bool light;
  final bool highlighted;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final Color fill;
    if (light) {
      fill = highlighted ? Colors.white : AppColors.surfaceStrong;
    } else {
      fill = highlighted ? const Color(0xFF969696) : AppColors.cameraControl;
    }
    final iconColor = light ? AppColors.inkDeep : Colors.white;

    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: SizedBox(
          width: 72,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: fill,
                  borderRadius: BorderRadius.circular(14),
                  border: highlighted
                      ? Border.all(
                          color: light ? AppColors.ink : Colors.white,
                          width: 1.4,
                        )
                      : null,
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                style: TextStyle(
                  color: labelColor,
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

class _Shutter extends StatelessWidget {
  const _Shutter({
    required this.light,
    required this.busy,
    required this.onTap,
  });

  final bool light;
  final bool busy;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final ring = light ? AppColors.textMuted : Colors.white;
    final Color fill;
    if (busy) {
      fill = AppColors.cameraControl;
    } else if (light) {
      fill = AppColors.surfaceStrong;
    } else {
      fill = Colors.white;
    }

    return Semantics(
      button: true,
      label: 'Take photo',
      excludeSemantics: true,
      child: GestureDetector(
        key: const Key('capture.shutter'),
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: 76,
          height: 76,
          padding: const EdgeInsets.all(5),
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: ring, width: 4),
          ),
          child: DecoratedBox(
            decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
          ),
        ),
      ),
    );
  }
}
