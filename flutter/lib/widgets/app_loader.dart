import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// A simple centered spinner — used for single-item loads (service detail,
/// a full-screen fetch). Grid/list loads use [AppGridSkeleton] instead so
/// the layout is already legible while data is in flight.
class AppLoader extends StatelessWidget {
  const AppLoader({super.key, this.compact = false});

  final bool compact;

  @override
  Widget build(BuildContext context) {
    final indicator = SizedBox(
      width: 26,
      height: 26,
      child: CircularProgressIndicator(
        strokeWidth: 2.4,
        color: context.mereytoiColors.goldPrimary,
      ),
    );
    if (compact) return Center(child: indicator);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: indicator,
      ),
    );
  }
}
