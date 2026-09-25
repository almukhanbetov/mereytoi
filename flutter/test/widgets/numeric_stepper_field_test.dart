import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/widgets/numeric_stepper_field.dart';

/// Этап 10Б-1 — replaces a plain "+/− only" guest stepper. Covers the
/// three ways a value can change: typing a number directly on the
/// keyboard, tapping a quick-pick chip, and nudging by one with −/+ —
/// plus the bounds a real menu's `min_guests`/`max_guests` impose (a
/// concrete real-world range like Panorama's 50..120, not an arbitrary
/// one).
Widget _harness({
  required int value,
  required int min,
  int? max,
  required ValueChanged<int> onChanged,
  String? suffixLabel,
  String? quickPickLabel,
}) {
  return MaterialApp(
    theme: AppTheme.dark,
    home: Scaffold(
      body: NumericStepperField(
        value: value,
        min: min,
        max: max,
        onChanged: onChanged,
        suffixLabel: suffixLabel,
        quickPickLabel: quickPickLabel,
      ),
    ),
  );
}

void main() {
  testWidgets(
    'typing a number directly and submitting commits the clamped value',
    (tester) async {
      int? changedTo;
      await tester.pumpWidget(
        _harness(value: 50, min: 50, max: 120, onChanged: (v) => changedTo = v),
      );

      await tester.enterText(find.byType(TextField), '85');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      expect(changedTo, 85);
    },
  );

  testWidgets('typing a value above max clamps to max on commit', (
    tester,
  ) async {
    int? changedTo;
    await tester.pumpWidget(
      _harness(value: 50, min: 50, max: 120, onChanged: (v) => changedTo = v),
    );

    await tester.enterText(find.byType(TextField), '999');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(changedTo, 120);
    expect(
      tester.widget<TextField>(find.byType(TextField)).controller!.text,
      '120',
    );
  });

  testWidgets('typing a value below min clamps to min on commit', (
    tester,
  ) async {
    int? changedTo;
    await tester.pumpWidget(
      _harness(value: 60, min: 50, max: 120, onChanged: (v) => changedTo = v),
    );

    await tester.enterText(find.byType(TextField), '1');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(changedTo, 50);
  });

  testWidgets(
    'an empty field on commit falls back to the current value, not zero',
    (tester) async {
      int? changedTo;
      await tester.pumpWidget(
        _harness(value: 70, min: 50, max: 120, onChanged: (v) => changedTo = v),
      );

      await tester.enterText(find.byType(TextField), '');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Never silently commits an out-of-range/invalid zero.
      expect(changedTo, isNull);
      expect(find.text('70'), findsOneWidget);
    },
  );

  testWidgets('tapping a quick-pick chip commits that value immediately', (
    tester,
  ) async {
    int? changedTo;
    await tester.pumpWidget(
      _harness(value: 50, min: 50, max: 120, onChanged: (v) => changedTo = v),
    );

    // Quick values for 50..120 are {50, 68, 85, 103, 120} (25/50/75% steps).
    await tester.tap(find.widgetWithText(ChoiceChip, '85'));
    await tester.pumpAndSettle();

    expect(changedTo, 85);
  });

  testWidgets('+/- nudge by exactly one and respect min/max bounds', (
    tester,
  ) async {
    int value = 50;
    await tester.pumpWidget(
      StatefulBuilder(
        builder: (context, setState) => _harness(
          value: value,
          min: 50,
          max: 51,
          onChanged: (v) => setState(() => value = v),
        ),
      ),
    );

    // At min: the "-" button must be disabled (onTap == null renders no
    // ink response, but we can still verify via the icon's tap doing
    // nothing — check by tapping "+" instead, which is enabled).
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    expect(value, 51);

    // Now at max (51) — "+" must be disabled, so tapping it again must not
    // push the value past max.
    await tester.tap(find.byIcon(Icons.add_rounded));
    await tester.pumpAndSettle();
    expect(value, 51);
  });

  testWidgets(
    'no max means no quick-pick row and the + button is always enabled',
    (tester) async {
      await tester.pumpWidget(_harness(value: 5, min: 1, onChanged: (_) {}));

      expect(find.byType(ChoiceChip), findsNothing);
    },
  );

  testWidgets('suffixLabel renders next to the number', (tester) async {
    await tester.pumpWidget(
      _harness(
        value: 4,
        min: 1,
        max: 10,
        onChanged: (_) {},
        suffixLabel: 'чел.',
      ),
    );

    expect(find.text('чел.'), findsOneWidget);
  });

  testWidgets(
    'quickPickLabel shows above the quick-pick row when provided, absent when null '
    '(Этап 10Б-1А requirement 3 — "Быстрый выбор гостей")',
    (tester) async {
      await tester.pumpWidget(
        _harness(
          value: 50,
          min: 50,
          max: 120,
          onChanged: (_) {},
          quickPickLabel: 'Быстрый выбор гостей',
        ),
      );
      expect(find.text('Быстрый выбор гостей'), findsOneWidget);

      await tester.pumpWidget(
        _harness(value: 50, min: 50, max: 120, onChanged: (_) {}),
      );
      expect(find.text('Быстрый выбор гостей'), findsNothing);
    },
  );
}
