import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

/// The web calculator's guest range slider (`<input type="range">` in
/// ServiceDetail.jsx / RestaurantMenuCalculator.jsx), shown under the
/// [NumericStepperField] so both edit the same value: dragging calls
/// [onChanged] live, and the field/±1 buttons move the thumb back. Step is
/// 1 guest — the range input's default, which is what the web uses.
///
/// Purely an input: it never computes a price itself (the caller's
/// existing calculator does).
class GuestSlider extends StatelessWidget {
  const GuestSlider({
    super.key,
    required this.value,
    required this.min,
    required this.max,
    required this.onChanged,
    this.suffixLabel,
  });

  final int value;
  final int min;

  /// The slider's right end. Must be finite — see [sliderMaxFor].
  final int max;
  final ValueChanged<int> onChanged;

  /// e.g. "чел." — shown after the min/max labels.
  final String? suffixLabel;

  /// The slider's right end for a guest range whose real [max] may be
  /// absent: the real max when there is one, otherwise the web calculator's
  /// own slider-only fallback, `Math.max(minGuests * 4, 200)`
  /// (RestaurantMenuCalculator.jsx). The fallback only bounds the *slider*;
  /// the stepper beside it still allows any larger count.
  static int sliderMaxFor({required int min, int? max}) =>
      max ?? math.max(min * 4, 200);

  @override
  Widget build(BuildContext context) {
    if (max <= min) return const SizedBox.shrink();
    final colors = context.mereytoiColors;
    final suffix = suffixLabel == null ? '' : ' $suffixLabel';
    // The stepper can go past a fallback max; the thumb then just rests at
    // the right end instead of throwing.
    final shown = value.clamp(min, max).toDouble();
    final labelStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: colors.textMuted);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            activeTrackColor: colors.goldPrimary,
            inactiveTrackColor: colors.divider,
            thumbColor: colors.goldPrimary,
            overlayColor: colors.goldPrimary.withValues(alpha: 0.16),
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 11),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 24),
            // No discrete tick marks: up to ~1000 one-guest steps.
            activeTickMarkColor: Colors.transparent,
            inactiveTickMarkColor: Colors.transparent,
            showValueIndicator: ShowValueIndicator.never,
          ),
          child: Slider(
            key: const ValueKey('guest-slider'),
            value: shown,
            min: min.toDouble(),
            max: max.toDouble(),
            divisions: max - min,
            onChanged: (v) {
              final next = v.round();
              if (next != value) onChanged(next);
            },
          ),
        ),
        Padding(
          // Lines the labels up with the track's ends (overlay inset).
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
          child: Row(
            children: [
              Text('$min$suffix', style: labelStyle),
              const Spacer(),
              Text('$max$suffix', style: labelStyle),
            ],
          ),
        ),
      ],
    );
  }
}
