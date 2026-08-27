import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// A gently pulsing placeholder block — used in list/grid loading states
/// instead of a spinner marooned in the middle of an empty screen, so the
/// layout that's about to load is already legible while data is in flight.
class AppSkeleton extends StatefulWidget {
  const AppSkeleton({super.key, this.borderRadius = AppRadius.md, this.width, this.height});

  final double borderRadius;
  final double? width;
  final double? height;

  @override
  State<AppSkeleton> createState() => _AppSkeletonState();
}

class _AppSkeletonState extends State<AppSkeleton> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1100))..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = Curves.easeInOut.transform(_controller.value);
        return Container(
          width: widget.width,
          height: widget.height,
          decoration: BoxDecoration(
            color: Color.lerp(AppColors.surface, AppColors.surfaceElevated, t),
            borderRadius: BorderRadius.circular(widget.borderRadius),
          ),
        );
      },
    );
  }
}

/// A skeleton the same shape as [ServiceCard] / [CategoryCard] — used while
/// GET /api/listings or GET /api/categories is loading, so the grid never
/// flashes a blank frame.
class AppCardSkeleton extends StatelessWidget {
  const AppCardSkeleton({super.key, this.aspectRatio = 4 / 3});

  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: AppColors.surface, borderRadius: BorderRadius.circular(AppRadius.lg)),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(aspectRatio: aspectRatio, child: const AppSkeleton(borderRadius: 0)),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const AppSkeleton(height: 12, width: 70),
                const SizedBox(height: AppSpacing.sm),
                const AppSkeleton(height: 14, width: 120),
                const SizedBox(height: AppSpacing.sm),
                AppSkeleton(height: 12, width: MediaQuery.sizeOf(context).width * 0.2),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A row of [AppCardSkeleton] tiles filling a 2-column grid — drop-in
/// replacement for `AppLoader()` on the Services/Categories grids.
class AppGridSkeleton extends StatelessWidget {
  const AppGridSkeleton({super.key, this.itemCount = 6, this.aspectRatio = 0.72});

  final int itemCount;
  final double aspectRatio;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      padding: const EdgeInsets.all(AppSpacing.lg),
      physics: const NeverScrollableScrollPhysics(),
      shrinkWrap: true,
      itemCount: itemCount,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisSpacing: AppSpacing.md,
        crossAxisSpacing: AppSpacing.md,
        childAspectRatio: aspectRatio,
      ),
      itemBuilder: (context, i) => const AppCardSkeleton(),
    );
  }
}
