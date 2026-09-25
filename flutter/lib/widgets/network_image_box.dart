import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import 'app_skeleton.dart';

/// One place for "how a photo from the API renders" — rounded corners,
/// BoxFit.cover, a calm skeleton while it loads (no spinner marooned in the
/// middle of a photo), a soft fade-in once it arrives, and a premium
/// dark/gold placeholder instead of a broken-image icon when a listing has
/// no photo or the URL fails to load.
class NetworkImageBox extends StatelessWidget {
  const NetworkImageBox({
    super.key,
    required this.url,
    this.borderRadius = AppRadius.md,
    this.fallbackIcon = Icons.auto_awesome,
    this.fit = BoxFit.cover,
  });

  final String? url;
  final double borderRadius;
  final IconData fallbackIcon;

  /// `cover` everywhere a photo fills a fixed-shape slot (cards, hero
  /// headers, thumbnails) — the one exception is the full-screen
  /// [PhotoViewerScreen], which passes `contain` so the *whole* photo is
  /// visible before the viewer's own pinch-to-zoom takes over.
  final BoxFit fit;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    if (url == null || url!.isEmpty) {
      return ClipRRect(
        borderRadius: radius,
        child: _Placeholder(icon: fallbackIcon),
      );
    }
    return ClipRRect(
      borderRadius: radius,
      child: CachedNetworkImage(
        imageUrl: url!,
        fit: fit,
        fadeInDuration: const Duration(milliseconds: 220),
        placeholder: (context, _) => const AppSkeleton(borderRadius: 0),
        errorWidget: (context, _, _) => _Placeholder(icon: fallbackIcon),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.icon});

  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    return Container(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors.surface, colors.backgroundSecondary],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(
        icon,
        color: colors.goldPrimary.withValues(alpha: 0.5),
        size: 28,
      ),
    );
  }
}
