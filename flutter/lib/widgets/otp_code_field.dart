import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/theme/app_theme.dart';

/// A one-time-code input drawn as [length] cells.
///
/// Under the cells is a single, invisible text field — so typing moves from
/// cell to cell, Backspace walks back, and pasting a whole code (even
/// "Код: 123 456" — non-digits are dropped) or the system's one-time-code
/// autofill fills every cell at once. Digits only, numeric keyboard.
class OtpCodeField extends StatefulWidget {
  const OtpCodeField({
    super.key,
    required this.controller,
    this.length = 6,
    this.onCompleted,
    this.hasError = false,
    this.autofocus = true,
    this.semanticsLabel,
  });

  final TextEditingController controller;
  final int length;

  /// Called with the code each time it reaches [length] digits.
  final ValueChanged<String>? onCompleted;

  /// Draws the cells in the error colour.
  final bool hasError;
  final bool autofocus;
  final String? semanticsLabel;

  @override
  State<OtpCodeField> createState() => _OtpCodeFieldState();
}

class _OtpCodeFieldState extends State<OtpCodeField> {
  final _focus = FocusNode();

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_changed);
    _focus.addListener(_changed);
  }

  @override
  void didUpdateWidget(covariant OtpCodeField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_changed);
      widget.controller.addListener(_changed);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_changed);
    _focus.dispose();
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    final code = widget.controller.text;
    return Semantics(
      label: widget.semanticsLabel,
      textField: true,
      child: SizedBox(
        height: 58,
        child: Stack(
          children: [
            Row(
              children: [
                for (var i = 0; i < widget.length; i++) ...[
                  if (i > 0) const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: _Cell(
                      digit: i < code.length ? code[i] : '',
                      active:
                          _focus.hasFocus &&
                          (i == code.length ||
                              (i == widget.length - 1 &&
                                  code.length == widget.length)),
                      hasError: widget.hasError,
                      colors: colors,
                    ),
                  ),
                ],
              ],
            ),
            Positioned.fill(
              child: TextField(
                key: const ValueKey('otp-input'),
                controller: widget.controller,
                focusNode: _focus,
                autofocus: widget.autofocus,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.done,
                autofillHints: const [AutofillHints.oneTimeCode],
                inputFormatters: [
                  FilteringTextInputFormatter.digitsOnly,
                  LengthLimitingTextInputFormatter(widget.length),
                ],
                autocorrect: false,
                enableSuggestions: false,
                showCursor: false,
                cursorColor: Colors.transparent,
                style: const TextStyle(color: Colors.transparent, fontSize: 1),
                // Every border and the fill off explicitly: the app's input
                // theme would otherwise draw its focus border over the cells.
                decoration: const InputDecoration(
                  isCollapsed: true,
                  filled: false,
                  contentPadding: EdgeInsets.zero,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  counterText: '',
                ),
                onChanged: (value) {
                  if (value.length == widget.length) {
                    widget.onCompleted?.call(value);
                  }
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Cell extends StatelessWidget {
  const _Cell({
    required this.digit,
    required this.active,
    required this.hasError,
    required this.colors,
  });

  final String digit;
  final bool active;
  final bool hasError;
  final MereytoiColors colors;

  @override
  Widget build(BuildContext context) {
    final borderColor = hasError
        ? colors.error
        : active
        ? colors.goldPrimary
        : digit.isNotEmpty
        ? colors.goldMuted
        : colors.border;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 120),
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: colors.inputBackground,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(color: borderColor, width: active ? 2 : 1.2),
      ),
      child: Text(
        digit,
        style: Theme.of(context).textTheme.titleLarge?.copyWith(
          fontSize: 22,
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}
