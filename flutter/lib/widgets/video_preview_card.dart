import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../services/video_thumbnail_service.dart';
import '../state/locale_provider.dart';

/// A 16:9 preview tile for one service video: a real frame from the video
/// as the background, a soft dark gradient at the bottom, and a large
/// round play button — tapping it calls [onOpen] (the caller's existing
/// "open this URL" flow). Nothing here plays the video or turns on sound.
///
/// The frame is requested only once the card scrolls near the viewport
/// (not when the page is built), through [videoThumbnailCacheProvider]'s
/// session cache. While it loads the tile is a dark placeholder; if no
/// frame can be produced (offline, timeout, unsupported file) it stays a
/// dark tile labelled «Видео».
class VideoPreviewCard extends ConsumerStatefulWidget {
  const VideoPreviewCard({
    super.key,
    required this.videoUrl,
    required this.locale,
    required this.onOpen,
  });

  /// Absolute URL of the video (already resolved by the caller).
  final String videoUrl;
  final AppLocale locale;
  final VoidCallback onOpen;

  /// How far outside the viewport a card may be and still start loading —
  /// enough to have the frame ready as it scrolls in.
  static const preloadMargin = 300.0;

  @override
  ConsumerState<VideoPreviewCard> createState() => _VideoPreviewCardState();
}

enum _FrameState { idle, loading, ready, failed }

class _VideoPreviewCardState extends ConsumerState<VideoPreviewCard> {
  _FrameState _state = _FrameState.idle;
  Uint8List? _frame;
  ScrollPosition? _position;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final position = Scrollable.maybeOf(context)?.position;
    if (position != _position) {
      _position?.removeListener(_maybeLoad);
      _position = position;
      if (_state == _FrameState.idle) _position?.addListener(_maybeLoad);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoad());
  }

  @override
  void didUpdateWidget(covariant VideoPreviewCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.videoUrl != widget.videoUrl) {
      _state = _FrameState.idle;
      _frame = null;
      _position?.removeListener(_maybeLoad);
      _position?.addListener(_maybeLoad);
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeLoad());
    }
  }

  @override
  void dispose() {
    _position?.removeListener(_maybeLoad);
    super.dispose();
  }

  bool _isNearViewport() {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return false;
    final scrollable = Scrollable.maybeOf(context);
    if (scrollable == null) return true; // not scrollable: always on screen
    final viewport = scrollable.context.findRenderObject();
    if (viewport is! RenderBox || !viewport.hasSize) return false;
    final top = box.localToGlobal(Offset.zero, ancestor: viewport).dy;
    const margin = VideoPreviewCard.preloadMargin;
    return top < viewport.size.height + margin &&
        top + box.size.height > -margin;
  }

  void _maybeLoad() {
    if (!mounted || _state != _FrameState.idle || !_isNearViewport()) return;
    _position?.removeListener(_maybeLoad);
    setState(() => _state = _FrameState.loading);
    final url = widget.videoUrl;
    ref.read(videoThumbnailCacheProvider).load(url).then((bytes) {
      if (!mounted || url != widget.videoUrl) return;
      setState(() {
        _frame = bytes;
        _state = bytes == null ? _FrameState.failed : _FrameState.ready;
      });
    });
  }

  @override
  Widget build(BuildContext context) {
    final label = t(widget.locale, ru: 'Видео', kz: 'Видео', en: 'Video');
    final frame = _frame;

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
              onTap: widget.onOpen,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  if (frame != null)
                    Image.memory(
                      frame,
                      key: const ValueKey('video-preview-frame'),
                      fit: BoxFit.cover,
                      gaplessPlayback: true,
                      errorBuilder: (_, _, _) => const _DarkBackdrop(),
                    )
                  else
                    const _DarkBackdrop(),
                  // Soft legibility gradient over the bottom of the frame.
                  const DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Colors.transparent, Color(0x99000000)],
                        stops: [0.5, 1.0],
                      ),
                    ),
                  ),
                  const Center(child: _PlayButton()),
                  if (_state == _FrameState.failed)
                    Positioned(
                      left: AppSpacing.md,
                      bottom: AppSpacing.sm,
                      child: Text(
                        label,
                        key: const ValueKey('video-preview-fallback'),
                        style: Theme.of(
                          context,
                        ).textTheme.titleSmall?.copyWith(color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),
          ),
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
