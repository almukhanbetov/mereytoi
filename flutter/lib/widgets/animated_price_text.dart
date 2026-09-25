import 'package:flutter/material.dart';

/// The one deliberate animation this redesign adds around price (Этап
/// 10Б-1, requirement 6 — "не добавляй лишние анимации"): a short
/// fade+rise crossfade whenever the *formatted* price string changes, so a
/// guest-count or extras edit doesn't just snap to a new number. Respects
/// the system's reduce-motion setting (`MediaQuery.disableAnimations`) by
/// collapsing to an instant swap. Deliberately takes the already-formatted
/// string, not a raw number — this never recomputes or reformats a price,
/// only animates between two strings the caller already produced with the
/// existing `formatPrice`.
class AnimatedPriceText extends StatelessWidget {
  const AnimatedPriceText({super.key, required this.text, this.style});

  final String text;
  final TextStyle? style;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.of(context).disableAnimations;
    return AnimatedSwitcher(
      duration: reduceMotion
          ? Duration.zero
          : const Duration(milliseconds: 180),
      switchInCurve: Curves.easeOut,
      switchOutCurve: Curves.easeIn,
      transitionBuilder: (child, animation) => FadeTransition(
        opacity: animation,
        child: SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0, 0.2),
            end: Offset.zero,
          ).animate(animation),
          child: child,
        ),
      ),
      child: Text(text, key: ValueKey(text), style: style),
    );
  }
}
