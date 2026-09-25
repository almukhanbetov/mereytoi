import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/widgets/animated_price_text.dart';

/// Этап 10Б-1, requirement 6 — the one deliberate animation this stage
/// adds: confirms it actually renders the given text (both before and
/// after a value change settles), and that it collapses to an instant
/// swap under reduce-motion — never a data/formula concern, purely that
/// the widget shows the right string.
void main() {
  testWidgets('renders the given text', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: AnimatedPriceText(text: '25 000 ₸')),
    );

    expect(find.text('25 000 ₸'), findsOneWidget);
  });

  testWidgets(
    'swapping the text mid-animation still settles on the new value',
    (tester) async {
      await tester.pumpWidget(
        const MaterialApp(home: AnimatedPriceText(text: '25 000 ₸')),
      );
      await tester.pumpWidget(
        const MaterialApp(home: AnimatedPriceText(text: '30 000 ₸')),
      );
      await tester.pumpAndSettle();

      expect(find.text('30 000 ₸'), findsOneWidget);
      expect(find.text('25 000 ₸'), findsNothing);
    },
  );

  testWidgets(
    'under reduce-motion the swap is instant (no lingering old text)',
    (tester) async {
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MaterialApp(home: AnimatedPriceText(text: '25 000 ₸')),
        ),
      );
      await tester.pumpWidget(
        const MediaQuery(
          data: MediaQueryData(disableAnimations: true),
          child: MaterialApp(home: AnimatedPriceText(text: '30 000 ₸')),
        ),
      );
      // A single pump (no pumpAndSettle needed) — Duration.zero should
      // already have completed the transition.
      await tester.pump();

      expect(find.text('30 000 ₸'), findsOneWidget);
      expect(find.text('25 000 ₸'), findsNothing);
    },
  );
}
