import 'package:flutter/material.dart';

import '../../app_scope.dart';
import '../../models/album.dart';
import '../../models/library.dart';
import '../../routing/app_navigation.dart';
import '../../routing/app_routes.dart';
import '../../theme/app_theme.dart';
import '../../widgets/album_art.dart';
import '../../widgets/common.dart';
import '../../widgets/formatting.dart';
import '../../widgets/mini_player.dart';
import '../../widgets/taskbars.dart';
import 'save_album_sheet.dart';

/// Full album details: "Learn more" (wireframe 11).
class AlbumDetailsScreen extends StatelessWidget {
  const AlbumDetailsScreen({super.key, required this.args});

  final AlbumDetailsArgs args;

  @override
  Widget build(BuildContext context) {
    final album = args.album;
    final theme = Theme.of(context);
    final player = AppScope.of(context).player;

    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.white,
        scrolledUnderElevation: 0,
        actions: [
          PopupMenuButton<String>(
            tooltip: 'More options',
            onSelected: (_) async {
              final picked = await AppNav.search(
                context,
                initialQuery: album.title,
              );
              if (picked != null && context.mounted) {
                AppNav.showResult(context, picked);
              }
            },
            itemBuilder: (context) => const [
              PopupMenuItem(
                value: 'releases',
                child: Text('Find other releases'),
              ),
            ],
          ),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.page,
          0,
          AppSpacing.page,
          24,
        ),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              AlbumArt(album: album, size: 96, radius: 2),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(album.title, style: theme.textTheme.titleLarge),
                    const SizedBox(height: 2),
                    Text(
                      album.artistYear,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: AppColors.textSecondary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${album.formatDescription} · ${album.label}',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: AppColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              CircleIconButton(
                icon: Icons.add,
                tooltip: 'Add to collection',
                onPressed: () =>
                    startSaveAlbum(context, album, ListKind.collection),
              ),
              const SizedBox(width: 6),
              CircleIconButton(
                icon: Icons.favorite_border,
                tooltip: 'Add to wishlist',
                onPressed: () =>
                    startSaveAlbum(context, album, ListKind.wishlist),
              ),
            ],
          ),
          if (album.isPartial) ...[
            const SizedBox(height: 16),
            const InfoBanner(
              message: 'Showing saved info – some details may be missing',
            ),
          ],
          const _SectionTitle('Tracklist'),
          ListenableBuilder(
            listenable: player,
            builder: (context, _) => Column(
              children: [
                for (final track in album.tracks)
                  _TrackRow(
                    track: track,
                    playing: player.isPlayingTrack(album, track),
                    onTap: track.hasPreview && album.previewsAvailable
                        ? () => player.toggle(album, track)
                        : null,
                  ),
              ],
            ),
          ),
          const Divider(height: 32),
          const _SectionTitle('Pressing details', top: 0),
          _DetailRow(label: 'Label', value: album.label),
          _DetailRow(label: 'Catalog #', value: album.catalogNumber),
          _DetailRow(label: 'Country', value: album.country),
          _DetailRow(label: 'Format', value: album.pressingFormat),
          const Divider(height: 32),
          const _SectionTitle('Genres & styles', top: 0),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final genre in album.genres)
                Chip(label: Text(genre), backgroundColor: Colors.white),
            ],
          ),
          const Divider(height: 32),
          const _SectionTitle('Community rating', top: 0),
          _Rating(rating: album.rating, count: album.ratingCount),
        ],
      ),
      bottomNavigationBar: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const MiniPlayer(),
          MainTaskbar(current: args.tab),
        ],
      ),
    );
  }
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, {this.top = 24});

  final String text;
  final double top;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(top: top, bottom: 8),
      child: Text(text, style: Theme.of(context).textTheme.titleLarge),
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({required this.track, required this.playing, this.onTap});

  final Track track;
  final bool playing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontSize: 17,
      color: AppColors.inkDeep,
      fontWeight: playing ? FontWeight.w600 : FontWeight.w400,
    );
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(
          children: [
            SizedBox(
              width: 44,
              child: Text(
                track.position,
                style: const TextStyle(
                  fontSize: 16,
                  color: AppColors.textMuted,
                ),
              ),
            ),
            Expanded(child: Text(track.title, style: style)),
            if (playing)
              const Padding(
                padding: EdgeInsets.only(right: 8),
                child: Icon(Icons.graphic_eq, size: 18),
              ),
            Text(Formatting.duration(track.duration), style: style),
          ],
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  const _DetailRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 130,
            child: Text(
              label,
              style: const TextStyle(fontSize: 16, color: AppColors.inkDeep),
            ),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontSize: 16, color: AppColors.inkDeep),
            ),
          ),
        ],
      ),
    );
  }
}

class _Rating extends StatelessWidget {
  const _Rating({required this.rating, required this.count});

  final double? rating;
  final int count;

  @override
  Widget build(BuildContext context) {
    final rating = this.rating;
    if (rating == null) {
      return Text(
        'No ratings yet',
        style: Theme.of(context).textTheme.bodyLarge,
      );
    }
    return Row(
      children: [
        for (var i = 1; i <= 5; i++)
          Icon(
            rating >= i
                ? Icons.star
                : rating >= i - 0.5
                ? Icons.star_half
                : Icons.star_border,
            color: AppColors.ink,
            size: 26,
          ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            '${rating.toStringAsFixed(1)} / 5 · '
            '${Formatting.count(count)} ratings on Discogs',
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: AppColors.textSecondary,
            ),
          ),
        ),
      ],
    );
  }
}
