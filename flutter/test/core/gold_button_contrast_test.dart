import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';

/// WCAG contrast of [fg] over [bg], both composited on the opaque [page].
double _contrast(Color fg, Color bg, Color page) {
  final fill = Color.alphaBlend(bg, page);
  final ink = Color.alphaBlend(fg, fill);
  final a = ink.computeLuminance();
  final b = fill.computeLuminance();
  return (a > b ? a + .05 : b + .05) / (a > b ? b + .05 : a + .05);
}

const _aa = 4.5;

void main() {
  final themes = <String, (ThemeData Function(), MereytoiColors)>{
    'light': (() => AppTheme.light, MereytoiColors.light),
    'dark': (() => AppTheme.dark, MereytoiColors.dark),
  };

  for (final MapEntry(key: name, value: (makeTheme, colors))
      in themes.entries) {
    final pages = [
      colors.backgroundPrimary,
      colors.surface,
      colors.surfaceElevated,
    ];

    Future<BuildContext> pump(WidgetTester tester, Widget button) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: makeTheme(),
          home: Scaffold(body: Center(child: button)),
        ),
      );
      return tester.element(find.byIcon(Icons.check));
    }

    Color fillOf(WidgetTester tester, Type type) => tester
        .widget<Material>(
          find
              .descendant(
                of: find.byType(type),
                matching: find.byType(Material),
              )
              .first,
        )
        .color!;

    /// The color the button hands to whatever it draws: label, icon, spinner.
    Color inkOf(BuildContext iconContext) => IconTheme.of(iconContext).color!;

    group('$name: gold buttons', () {
      testWidgets('ElevatedButton: normal, pressed, disabled', (tester) async {
        final style = makeTheme().elevatedButtonTheme.style!;
        var ctx = await pump(
          tester,
          ElevatedButton.icon(
            onPressed: () {},
            icon: const Icon(Icons.check),
            label: const Text('x'),
          ),
        );
        final fill = fillOf(tester, ElevatedButton);
        final ink = inkOf(ctx);
        expect(fill, colors.goldPrimary);
        expect(ink, colors.onGold);
        expect(_contrast(ink, fill, pages.first), greaterThanOrEqualTo(_aa));

        final overlay = style.overlayColor!.resolve({WidgetState.pressed})!;
        expect(
          _contrast(ink, Color.alphaBlend(overlay, fill), pages.first),
          greaterThanOrEqualTo(_aa),
          reason: 'pressed',
        );

        ctx = await pump(
          tester,
          const ElevatedButton(onPressed: null, child: Icon(Icons.check)),
        );
        await tester.pumpAndSettle();
        final off = fillOf(tester, ElevatedButton);
        expect(inkOf(ctx), colors.onGoldDisabled);
        for (final page in pages) {
          expect(
            _contrast(colors.onGoldDisabled, off, page),
            greaterThanOrEqualTo(_aa),
            reason: 'disabled on $page',
          );
        }
      });

      testWidgets('a local size override keeps the shared ink', (tester) async {
        final ctx = await pump(
          tester,
          // The Home «Смотреть услуги» button only overrides size and padding.
          ElevatedButton.icon(
            onPressed: () {},
            style: ElevatedButton.styleFrom(minimumSize: const Size(0, 44)),
            icon: const Icon(Icons.check),
            label: const Text('x'),
          ),
        );
        expect(fillOf(tester, ElevatedButton), colors.goldPrimary);
        expect(inkOf(ctx), colors.onGold);
      });

      testWidgets('FilledIconButton: normal, pressed, disabled', (
        tester,
      ) async {
        var ctx = await pump(
          tester,
          IconButton.filled(
            style: colors.goldIconButtonStyle,
            onPressed: () {},
            icon: const Icon(Icons.check),
          ),
        );
        final fill = fillOf(tester, IconButton);
        final ink = inkOf(ctx);
        expect(fill, colors.goldPrimary);
        expect(
          _contrast(ink, fill, pages.first),
          greaterThanOrEqualTo(_aa),
          reason: 'normal: $ink on $fill',
        );
        final overlay = colors.goldIconButtonStyle.overlayColor!.resolve({
          WidgetState.pressed,
        })!;
        expect(
          _contrast(ink, Color.alphaBlend(overlay, fill), pages.first),
          greaterThanOrEqualTo(_aa),
          reason: 'pressed',
        );

        ctx = await pump(
          tester,
          IconButton.filled(
            style: colors.goldIconButtonStyle,
            onPressed: null,
            icon: const Icon(Icons.check),
          ),
        );
        await tester.pumpAndSettle();
        final off = fillOf(tester, IconButton);
        for (final page in pages) {
          expect(
            _contrast(inkOf(ctx), off, page),
            greaterThanOrEqualTo(_aa),
            reason: 'disabled: ${inkOf(ctx)} on $off over $page',
          );
          expect(
            _contrast(colors.onGoldDisabled, off, page),
            greaterThanOrEqualTo(3),
            reason: 'spinner on $off over $page',
          );
        }
      });
    });
  }
}
