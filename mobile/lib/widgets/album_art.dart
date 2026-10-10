import 'dart:io';

import 'package:flutter/material.dart';

import '../models/album.dart';
import '../theme/app_theme.dart';
import 'dashed_border.dart';

/// Cover placeholder until cover images are fetched from Discogs.
///
/// Each album gets a stable shade so rows are easy to tell apart. A ghost
/// is drawn as a dashed outline with a faded record, as in the wireframes.
class AlbumArt extends StatelessWidget {
  const AlbumArt({
    super.key,
    this.album,
    this.size = 56,
    this.ghost = false,
    this.radius = 4,
  });

  final Album? album;
  final double size;
  final bool ghost;
  final double radius;

  static const _shades = [
    Color(0xFFE4E4E4),
    Color(0xFFD8D8D8),
    Color(0xFFCDCDCD),
    Color(0xFFE9E9E9),
    Color(0xFFDDDDDD),
  ];

  @override
  Widget build(BuildContext context) {
    if (ghost) {
      return SizedBox.square(
        dimension: size,
        child: CustomPaint(
          painter: DashedBorderPainter(
            color: AppColors.textMuted,
            radius: radius,
          ),
          child: Center(
            child: Icon(
              Icons.album_outlined,
              size: size * 0.5,
              color: AppColors.divider,
            ),
          ),
        ),
      );
    }

    final id = album?.id ?? '';
    final shade = _shades[id.hashCode.abs() % _shades.length];
    return Semantics(
      label: album == null ? 'Album cover' : 'Cover of ${album!.title}',
      image: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: shade,
          borderRadius: BorderRadius.circular(radius),
        ),
        child: Icon(
          Icons.album,
          size: size * 0.45,
          color: AppColors.textMuted.withValues(alpha: 0.6),
        ),
      ),
    );
  }
}

/// A photo taken or imported by the user, with a placeholder fallback.
class CoverPhoto extends StatelessWidget {
  const CoverPhoto({super.key, this.path, this.album, required this.size});

  final String? path;
  final Album? album;
  final double size;

  @override
  Widget build(BuildContext context) {
    final placeholder = AlbumArt(album: album, size: size, radius: 2);
    final path = this.path;
    if (path == null || !File(path).existsSync()) {
      return placeholder;
    }
    return SizedBox.square(
      dimension: size,
      child: Image.file(
        File(path),
        fit: BoxFit.cover,
        semanticLabel: 'Cover photo',
        errorBuilder: (context, error, stackTrace) => placeholder,
      ),
    );
  }
}
