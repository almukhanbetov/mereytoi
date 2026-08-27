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
  });

  final String? url;
  final double borderRadius;
  final IconData fallbackIcon;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(borderRadius);
    if (url == null || url!.isEmpty) {
      return ClipRRect(borderRadius: radius, child: _Placeholder(icon: fallbackIcon));
    }
    return ClipRRect(
      borderRadius: radius,
      child: CachedNetworkImage(
        imageUrl: url!,
        fit: BoxFit.cover,
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
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.surface, AppColors.backgroundSecondary],
        ),
      ),
      alignment: Alignment.center,
      child: Icon(icon, color: AppColors.goldPrimary.withValues(alpha: 0.5), size: 28),
    );
  }
}
