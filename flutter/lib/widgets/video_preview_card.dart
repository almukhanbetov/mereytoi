import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../state/locale_provider.dart';

/// A 16:9 preview tile for one service video: the backend-made poster image
/// as the background, a soft dark gradient at the bottom, and a large round
/// play button — tapping it calls [onOpen] (the caller's existing "open
/// this URL" flow). Nothing here plays or downloads the video.
///
/// The poster is a small JPEG loaded like any other image (Flutter's own
/// image cache). While it loads the tile is a dark backdrop; with no poster
/// (not generated yet) or when it fails to load, the tile stays dark and is
/// labelled «Видео».
class VideoPreviewCard extends StatelessWidget {
  const VideoPreviewCard({
    super.key,
    required this.videoUrl,
    required this.posterUrl,
    required this.locale,
    required this.onOpen,
  });

  /// Absolute URL of the video [onOpen] opens (already resolved by the caller).
  final String videoUrl;

  /// Absolute URL of the poster image, or null when the video has none.
  final String? posterUrl;
  final AppLocale locale;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final label = t(locale, ru: 'Видео', kz: 'Видео', en: 'Video');
    final poster = posterUrl;
    final fallback = _Fallback(label: label);

    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.lg),
        child: AspectRatio(
          aspectRatio: 16 / 9,
          child: Material(
            // Always dark, in both themes: it stands in for video content.
            color: const Color(0xFF16171F),
            child: InkWell(
              key: const ValueKey('video-preview-card'),
              onTap: onOpen,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (poster == null || poster.isEmpty)
                    fallback
                  else
                    Image.network(
                      poster,
                      key: const ValueKey('video-preview-frame'),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      frameBuilder: (context, child, frame, _) => frame == null
                          ? const _DarkBackdrop()
                          : Stack(
                              fit: StackFit.expand,
                              children: [child, const _BottomGradient()],
                            ),
                      errorBuilder: (_, _, _) => fallback,
                    ),
                  const Center(child: _PlayButton()),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// No poster (or it failed): the dark tile with its «Видео» label.
class _Fallback extends StatelessWidget {
  const _Fallback({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Stack(
      key: const ValueKey('video-preview-fallback'),
      fit: StackFit.expand,
      children: [
        const _DarkBackdrop(),
        const _BottomGradient(),
        Positioned(
          left: AppSpacing.md,
          bottom: AppSpacing.sm,
          child: Text(
            label,
            style: Theme.of(
              context,
            ).textTheme.titleSmall?.copyWith(color: Colors.white),
          ),
        ),
      ],
    );
  }
}

/// Soft legibility gradient over the bottom of the tile.
class _BottomGradient extends StatelessWidget {
  const _BottomGradient();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.transparent, Color(0x99000000)],
          stops: [0.5, 1.0],
        ),
      ),
    );
  }
}

class _DarkBackdrop extends StatelessWidget {
  const _DarkBackdrop();

  @override
  Widget build(BuildContext context) {
    return const DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF20222C), Color(0xFF3A3F52)],
        ),
      ),
    );
  }
}

class _PlayButton extends StatelessWidget {
  const _PlayButton();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: Colors.black.withValues(alpha: 0.45),
        border: Border.all(
          color: Colors.white.withValues(alpha: 0.85),
          width: 1.5,
        ),
      ),
      child: const Icon(
        Icons.play_arrow_rounded,
        size: 38,
        color: Colors.white,
      ),
    );
  }
}
