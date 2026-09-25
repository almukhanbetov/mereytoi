import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_theme.dart';

/// A bounded-integer editor that replaces a plain "+/− only" stepper
/// (MEREYTOI Этап 10Б-1): the number itself is a real text field — type
/// directly on the system numeric keyboard — plus a row of quick-pick
/// values spread across `[min, max]`, plus the familiar −/+ buttons for a
/// one-at-a-time nudge. Used anywhere a guest count needs editing
/// (restaurant menu, ordinary per-person service) so there's exactly one
/// implementation of this interaction, not one per screen.
class NumericStepperField extends StatefulWidget {
  const NumericStepperField({
    super.key,
    required this.value,
    required this.min,
    this.max,
    required this.onChanged,
    this.suffixLabel,
    this.quickValues,
    this.quickPickLabel,
  });

  final int value;
  final int min;

  /// `null` means genuinely no upper bound — see [GuestBounds]'s own doc
  /// comment; never invented here either.
  final int? max;
  final ValueChanged<int> onChanged;

  /// e.g. "чел." — shown after the number inside the field.
  final String? suffixLabel;

  /// Explicit override for the quick-pick row; otherwise derived from
  /// [min]/[max] (see [_quickValues]). Pass `const []` to hide the row
  /// entirely (e.g. when the range is too narrow to be useful).
  final List<int>? quickValues;

  /// e.g. "Быстрый выбор гостей" — a small caption shown above the
  /// quick-pick row so it reads as an intentional shortcut, not a random
  /// row of numbers (Этап 10Б-1А). This widget stays locale-agnostic
  /// itself (like [suffixLabel], the caller passes the already-localized
  /// string); omitted entirely when `null`, even if quick values exist.
  final String? quickPickLabel;

  @override
  State<NumericStepperField> createState() => _NumericStepperFieldState();
}

class _NumericStepperFieldState extends State<NumericStepperField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: '${widget.value}');
    _focusNode = FocusNode()..addListener(_onFocusChange);
  }

  @override
  void didUpdateWidget(covariant NumericStepperField oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Only overwrite the field's text when it isn't currently being typed
    // into — otherwise a parent rebuild would fight the user mid-keystroke
    // — and only when the value actually moved under it (a quick-pick chip
    // or the +/- buttons write through the same onChanged, so this also
    // covers "another part of the screen changed it").
    if (!_focusNode.hasFocus && widget.value != oldWidget.value) {
      _controller.text = '${widget.value}';
    }
  }

  @override
  void dispose() {
    _focusNode
      ..removeListener(_onFocusChange)
      ..dispose();
    _controller.dispose();
    super.dispose();
  }

  int _clamp(int v) {
    final max = widget.max;
    var out = v < widget.min ? widget.min : v;
    if (max != null && out > max) out = max;
    return out;
  }

  void _onFocusChange() {
    if (_focusNode.hasFocus) {
      // Этап 10Б-1А fix: this field can sit deep inside a long
      // CustomScrollView (the restaurant calculator's guest section), and
      // a plain focus-gain doesn't reliably scroll it clear of the
      // keyboard once one opens — schedule the scroll for the frame after
      // the keyboard's inset actually lands, not the frame the field was
      // tapped in.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        Scrollable.ensureVisible(
          context,
          alignment: 0.5,
          duration: const Duration(milliseconds: 220),
          curve: Curves.easeOut,
        );
      });
    } else {
      _commitTyped();
    }
  }

  /// Reads whatever the user actually typed, clamps it into range, and
  /// snaps the field's own text back in sync — covers an empty field, a
  /// value below min, or above max (never lets an out-of-range number
  /// silently reach [onChanged]).
  void _commitTyped() {
    final parsed = int.tryParse(_controller.text);
    final next = _clamp(parsed ?? widget.value);
    if ('$next' != _controller.text) _controller.text = '$next';
    if (next != widget.value) widget.onChanged(next);
  }

  void _apply(int next) {
    _focusNode.unfocus();
    final clamped = _clamp(next);
    _controller.text = '$clamped';
    if (clamped != widget.value) widget.onChanged(clamped);
  }

  /// Evenly spread candidates across the range plus both ends — e.g. for
  /// 50..120 this yields {50, 68, 85, 103, 120}. Empty when there's no
  /// real range to offer quick picks across (no max, or max == min).
  List<int> get _quickValues {
    if (widget.quickValues != null) return widget.quickValues!;
    final max = widget.max;
    if (max == null || max <= widget.min) return const [];
    final span = max - widget.min;
    final candidates = <int>{
      widget.min,
      widget.min + (span * 0.25).round(),
      widget.min + (span * 0.5).round(),
      widget.min + (span * 0.75).round(),
      max,
    };
    return candidates.toList()..sort();
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    final quick = _quickValues;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            _NudgeButton(
              icon: Icons.remove_rounded,
              onTap: widget.value > widget.min
                  ? () => _apply(widget.value - 1)
                  : null,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              // Этап 10Б-1А fix: the number + suffix used to be a plain
              // Row(IntrinsicWidth(TextField), Text(suffix)) — at a larger
              // system text scale (or once GuestSelector started wrapping
              // this in an AppCard, shaving more width off), that inner
              // Row's *own* unconstrained content could exceed the space
              // Expanded gave the container, overflowing *inside* it. A
              // single TextField with the suffix as its own
              // InputDecoration.suffixText can't do that — the
              // TextField/InputDecorator layout algorithm always fits
              // within whatever width it's given, shrinking the editable
              // area first rather than overflowing.
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                constraints: const BoxConstraints(minHeight: 52),
                decoration: BoxDecoration(
                  color: colors.inputBackground,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  border: Border.all(
                    color: _focusNode.hasFocus
                        ? colors.goldPrimary
                        : Colors.transparent,
                    width: 1.4,
                  ),
                ),
                child: TextField(
                  controller: _controller,
                  focusNode: _focusNode,
                  keyboardType: TextInputType.number,
                  textInputAction: TextInputAction.done,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.titleLarge,
                  decoration: InputDecoration(
                    border: InputBorder.none,
                    filled: false,
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.xs,
                      vertical: AppSpacing.xs,
                    ),
                    suffixText: widget.suffixLabel,
                    suffixStyle: Theme.of(context).textTheme.bodyMedium,
                  ),
                  onSubmitted: (_) => _focusNode.unfocus(),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            _NudgeButton(
              icon: Icons.add_rounded,
              onTap: (widget.max == null || widget.value < widget.max!)
                  ? () => _apply(widget.value + 1)
                  : null,
            ),
          ],
        ),
        if (quick.length > 1) ...[
          const SizedBox(height: AppSpacing.sm),
          if (widget.quickPickLabel != null) ...[
            Text(
              widget.quickPickLabel!,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.textMuted),
            ),
            const SizedBox(height: AppSpacing.xxs),
          ],
          SizedBox(
            height: 34,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              itemCount: quick.length,
              separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xxs),
              itemBuilder: (context, i) {
                final v = quick[i];
                return ChoiceChip(
                  label: Text('$v'),
                  visualDensity: VisualDensity.compact,
                  selected: v == widget.value,
                  onSelected: (_) => _apply(v),
                );
              },
            ),
          ),
        ],
      ],
    );
  }
}

class _NudgeButton extends StatelessWidget {
  const _NudgeButton({required this.icon, required this.onTap});

  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Material(
      color: enabled
          ? context.mereytoiColors.surfaceSoft
          : context.mereytoiColors.surface,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: SizedBox(
          width: 44,
          height: 44,
          child: Icon(
            icon,
            size: 17,
            color: enabled
                ? context.mereytoiColors.goldPrimary
                : context.mereytoiColors.textMuted,
          ),
        ),
      ),
    );
  }
}
