import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../models/album.dart';
import '../../routing/app_navigation.dart';
import '../../state/preview_player.dart';
import '../../theme/app_theme.dart';
import '../../widgets/common.dart';
import '../../widgets/formatting.dart';

/// Dark card shown over the camera once an album is identified.
///
/// 10a: swipeable preview of the top tracks, auto-playing the first.
/// 10b: no previews available.
/// 10c: all top tracks, expanded from "All tracks".
class ResultCard extends StatefulWidget {
  const ResultCard({
    super.key,
    required this.album,
    required this.onAdd,
    required this.onWishlist,
  });

  final Album album;
  final VoidCallback onAdd;
  final VoidCallback onWishlist;

  @override
  State<ResultCard> createState() => _ResultCardState();
}

class _ResultCardState extends State<ResultCard> {
  final PageController _pages = PageController();
  bool _expanded = false;
  int _page = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  void _onPageChanged(PreviewPlayer player, List<Track> tracks, int index) {
    setState(() => _page = index);
    if (player.isPlaying) {
      player.play(widget.album, tracks[index]);
    }
  }

  void _retryPreviews() {
    showAppSnackBar(
      ScaffoldMessenger.of(context),
      'Previews are still unavailable for this album.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final player = AppScope.of(context).player;
    final album = widget.album;
    final tracks = album.topTracks;

    return Container(
      key: const Key('scan.resultCard'),
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.fromLTRB(20, 18, 16, 4),
      decoration: BoxDecoration(
        color: AppColors.inkDeep,
        borderRadius: BorderRadius.circular(24),
      ),
      child: ListenableBuilder(
        listenable: player,
        builder: (context, _) {
          final Widget previews;
          if (tracks.isEmpty) {
            previews = _NoPreviews(onRetry: _retryPreviews);
          } else if (_expanded) {
            previews = Flexible(
              child: _TrackList(
                album: album,
                tracks: tracks,
                player: player,
                onCollapse: () => setState(() => _expanded = false),
              ),
            );
          } else {
            previews = _PreviewPager(
              album: album,
              tracks: tracks,
              player: player,
              controller: _pages,
              page: _page,
              onPageChanged: (index) => _onPageChanged(player, tracks, index),
              onExpand: () => setState(() => _expanded = true),
            );
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          album.title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          album.artistYearFormat,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: AppColors.onDarkSecondary,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  ),
                  CircleIconButton(
                    icon: Icons.add,
                    tooltip: 'Add to collection',
                    onDark: true,
                    onPressed: widget.onAdd,
                  ),
                  const SizedBox(width: 8),
                  CircleIconButton(
                    icon: Icons.favorite_border,
                    tooltip: 'Add to wishlist',
                    onDark: true,
                    onPressed: widget.onWishlist,
                  ),
                ],
              ),
              const SizedBox(height: 14),
              previews,
              Row(
                children: [
                  TextButton(
                    onPressed: () => AppNav.openAlbum(context, album),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.white,
                      padding: EdgeInsets.zero,
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [Text('Learn more'), Icon(Icons.chevron_right)],
                    ),
                  ),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'Tap shutter to scan next',
                      maxLines: 1,
                      textAlign: TextAlign.end,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: AppColors.onDarkSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}

class _PreviewPager extends StatelessWidget {
  const _PreviewPager({
    required this.album,
    required this.tracks,
    required this.player,
    required this.controller,
    required this.page,
    required this.onPageChanged,
    required this.onExpand,
  });

  final Album album;
  final List<Track> tracks;
  final PreviewPlayer player;
  final PageController controller;
  final int page;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: 124,
          child: PageView.builder(
            controller: controller,
            itemCount: tracks.length,
            onPageChanged: onPageChanged,
            itemBuilder: (context, index) => Padding(
              padding: const EdgeInsets.only(right: 4),
              child: _PreviewTile(
                album: album,
                track: tracks[index],
                index: index,
                total: tracks.length,
                player: player,
                onExpand: onExpand,
              ),
            ),
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            for (var i = 0; i < tracks.length; i++)
              Container(
                width: 7,
                height: 7,
                margin: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: i == page ? Colors.white : AppColors.cameraControl,
                ),
              ),
          ],
        ),
        const SizedBox(height: 4),
      ],
    );
  }
}

class _PreviewTile extends StatelessWidget {
  const _PreviewTile({
    required this.album,
    required this.track,
    required this.index,
    required this.total,
    required this.player,
    required this.onExpand,
  });

  final Album album;
  final Track track;
  final int index;
  final int total;
  final PreviewPlayer player;
  final VoidCallback onExpand;

  @override
  Widget build(BuildContext context) {
    final current = player.isCurrent(album, track);
    final playing = player.isPlayingTrack(album, track);
    final position = current ? player.position : Duration.zero;
    final parts = ['Track ${index + 1} of $total'];
    if (index == 0) {
      parts.add('Popular');
    }
    if (playing) {
      parts.add('playing');
    }

    return Container(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      decoration: BoxDecoration(
        color: AppColors.darkTile,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              IconButton(
                tooltip: playing ? 'Pause preview' : 'Play preview',
                onPressed: () => player.toggle(album, track),
                icon: Icon(
                  playing ? Icons.pause : Icons.play_arrow,
                  color: AppColors.inkDeep,
                ),
                style: IconButton.styleFrom(
                  backgroundColor: Colors.white,
                  fixedSize: const Size(44, 44),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    Text(
                      parts.join(' · '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppColors.onDarkSecondary,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ActionChip(
                key: const Key('scan.allTracks'),
                onPressed: onExpand,
                label: const Text('All tracks'),
                avatar: const Icon(
                  Icons.keyboard_arrow_down,
                  size: 18,
                  color: Colors.white,
                ),
                backgroundColor: AppColors.cameraControl,
                side: BorderSide.none,
                labelStyle: const TextStyle(color: Colors.white, fontSize: 13),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const Spacer(),
          ClipRRect(
            borderRadius: BorderRadius.circular(2),
            child: LinearProgressIndicator(
              value: current ? player.progress : 0,
              minHeight: 3,
              color: Colors.white,
              backgroundColor: AppColors.cameraControl,
            ),
          ),
          const SizedBox(height: 6),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                Formatting.duration(position),
                style: const TextStyle(
                  color: AppColors.onDarkSecondary,
                  fontSize: 12,
                ),
              ),
              Text(
                Formatting.duration(player.clipLength),
                style: const TextStyle(
                  color: AppColors.onDarkSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _TrackList extends StatelessWidget {
  const _TrackList({
    required this.album,
    required this.tracks,
    required this.player,
    required this.onCollapse,
  });

  final Album album;
  final List<Track> tracks;
  final PreviewPlayer player;
  final VoidCallback onCollapse;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: AppColors.darkTile,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InkWell(
            key: const Key('scan.collapseTracks'),
            onTap: onCollapse,
            borderRadius: BorderRadius.circular(16),
            child: const Padding(
              padding: EdgeInsets.fromLTRB(16, 12, 12, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      'Top tracks · by popularity',
                      style: TextStyle(
                        color: AppColors.onDarkSecondary,
                        fontSize: 15,
                      ),
                    ),
                  ),
                  Icon(Icons.keyboard_arrow_up, color: Colors.white),
                ],
              ),
            ),
          ),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 8),
              itemCount: tracks.length,
              itemBuilder: (context, index) {
                final track = tracks[index];
                final current = player.isCurrent(album, track);
                final playing = player.isPlayingTrack(album, track);
                return Container(
                  margin: const EdgeInsets.symmetric(horizontal: 6),
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  decoration: BoxDecoration(
                    color: current ? const Color(0xFF444444) : null,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 26,
                        child: Text(
                          '${index + 1}',
                          style: const TextStyle(
                            color: AppColors.onDarkSecondary,
                          ),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          track.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 17,
                          ),
                        ),
                      ),
                      Text(
                        Formatting.duration(track.duration),
                        style: const TextStyle(
                          color: AppColors.onDarkSecondary,
                          fontSize: 14,
                        ),
                      ),
                      IconButton(
                        tooltip: playing
                            ? 'Pause ${track.title}'
                            : 'Play ${track.title}',
                        onPressed: () => player.toggle(album, track),
                        icon: Icon(
                          playing ? Icons.pause : Icons.play_arrow,
                          color: playing ? AppColors.inkDeep : Colors.white,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: playing ? Colors.white : null,
                          side: const BorderSide(color: Colors.white),
                        ),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _NoPreviews extends StatelessWidget {
  const _NoPreviews({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.fromLTRB(16, 14, 8, 4),
      decoration: BoxDecoration(
        color: AppColors.darkTile,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_rounded, color: Colors.white),
              SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No previews for this album',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Preview service unavailable',
                      style: TextStyle(
                        color: AppColors.onDarkSecondary,
                        fontSize: 14,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          Align(
            alignment: Alignment.centerRight,
            child: TextButton(
              onPressed: onRetry,
              style: TextButton.styleFrom(foregroundColor: Colors.white),
              child: const Text('RETRY'),
            ),
          ),
        ],
      ),
    );
  }
}
