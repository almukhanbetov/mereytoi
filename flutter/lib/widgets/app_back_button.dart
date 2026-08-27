import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// A single, consistent back control for every pushed (non-tab) screen —
/// used instead of relying on each `AppBar`'s own default `BackButton` so
/// hero-image screens (where a plain icon can get lost against a bright
/// photo) and flat-surface screens (Categories, a pushed Services) share
/// the same visual language.
///
/// [onHero] switches between the two contexts this app actually has:
/// - `true` — sits directly over a photo (Service Detail's hero): a soft
///   dark, semi-transparent circular backdrop keeps the icon legible
///   against any photo, with a warm, soft-gold icon on top.
/// - `false` — sits on a normal themed surface (a flat `AppBar`, no
///   image behind it): no backdrop needed, just the icon in the app's
///   usual light "primary text" tone.
///
/// Always calls `Navigator.maybePop` — a real back navigation (preserving
/// whatever screen, filter, and scroll position was already there), never a
/// hard redirect to a bottom-nav tab.
class AppBackButton extends StatelessWidget {
  const AppBackButton({super.key, this.onHero = false});

  final bool onHero;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: onHero ? Colors.black.withValues(alpha: 0.38) : Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: () => Navigator.maybePop(context),
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            Icons.arrow_back_rounded,
            size: 20,
            color: onHero ? AppColors.goldSoft : AppColors.textPrimary,
          ),
        ),
      ),
    );
  }
}
