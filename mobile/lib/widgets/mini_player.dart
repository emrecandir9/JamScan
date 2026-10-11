import 'package:flutter/material.dart';

import '../app_scope.dart';
import '../theme/app_theme.dart';
import 'album_art.dart';
import 'formatting.dart';

/// Preview mini-player docked above the taskbar (wireframe 11).
/// Hidden while nothing has been played.
class MiniPlayer extends StatelessWidget {
  const MiniPlayer({super.key});

  @override
  Widget build(BuildContext context) {
    final player = AppScope.of(context).player;
    return ListenableBuilder(
      listenable: player,
      builder: (context, _) {
        final album = player.album;
        final track = player.track;
        if (album == null || track == null) {
          return const SizedBox.shrink();
        }
        return Container(
          key: const Key('miniPlayer'),
          margin: const EdgeInsets.fromLTRB(12, 0, 12, 8),
          decoration: BoxDecoration(
            color: AppColors.surfaceMuted,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: AppColors.divider),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(10, 8, 8, 6),
                child: Row(
                  children: [
                    AlbumArt(album: album, size: 44, radius: 2),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            track.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          Text(
                            album.artist,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    Text(
                      '${Formatting.duration(player.position)} / '
                      '${Formatting.duration(player.clipLength)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    const SizedBox(width: 8),
                    IconButton.filled(
                      tooltip: player.isPlaying
                          ? 'Pause preview'
                          : 'Play preview',
                      onPressed: () => player.toggle(album, track),
                      icon: Icon(
                        player.isPlaying ? Icons.pause : Icons.play_arrow,
                      ),
                    ),
                  ],
                ),
              ),
              LinearProgressIndicator(value: player.progress, minHeight: 2),
            ],
          ),
        );
      },
    );
  }
}
