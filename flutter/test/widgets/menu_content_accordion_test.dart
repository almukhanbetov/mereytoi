import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/models/listing_menu_item.dart';
import 'package:mereytoi_app/models/listing_menu_section.dart';
import 'package:mereytoi_app/state/locale_provider.dart';
import 'package:mereytoi_app/widgets/restaurant/menu_content_accordion.dart';

/// Этап 10Б-1А, requirement 1 — the exact regression this stage fixes:
/// "Состав меню" + "Развернуть всё"/"Свернуть всё" used to share one Row
/// with no Expanded/Wrap, overflowing horizontally
/// ("OVERFLOWED BY 41 PIXELS") at narrow widths and/or a larger system
/// text scale. Isolated widget test, not just the full-screen one, so a
/// future regression here fails fast and close to the actual bug.
final _section = ListingMenuSection(
  id: 1,
  menuId: 1,
  titleRu: 'Холодные закуски',
  titleKz: 'Салқын тағамдар',
  sortOrder: 0,
  items: [
    ListingMenuItem(
      id: 1,
      sectionId: 1,
      nameRu: 'Мясное ассорти',
      nameKz: 'Ет ассортиси',
      quantityText: '250 г',
      sortOrder: 0,
    ),
  ],
);

Widget _harness(Size size, {TextScaler textScaler = TextScaler.noScaling}) {
  return MediaQuery(
    data: MediaQueryData(size: size, textScaler: textScaler),
    child: MaterialApp(
      theme: AppTheme.dark,
      home: Scaffold(
        body: MenuContentAccordion(sections: [_section], locale: AppLocale.ru),
      ),
    ),
  );
}

void main() {
  for (final width in [320.0, 360.0, 393.0]) {
    testWidgets('no overflow at ${width.toInt()}px (normal text scale)', (
      tester,
    ) async {
      await tester.pumpWidget(_harness(Size(width, 600)));
      await tester.pumpAndSettle();

      expect(tester.takeException(), isNull);
      expect(find.text('Состав меню'), findsOneWidget);
      expect(find.text('Развернуть всё'), findsOneWidget);
      expect(find.text('Свернуть всё'), findsOneWidget);
    });
  }

  testWidgets('no overflow at 320px with a 1.3x system text scale', (
    tester,
  ) async {
    await tester.pumpWidget(
      _harness(const Size(320, 600), textScaler: const TextScaler.linear(1.3)),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('Состав меню'), findsOneWidget);
  });

  testWidgets(
    'expand-all / collapse-all still tap without error after the header restructure',
    (tester) async {
      await tester.pumpWidget(_harness(const Size(360, 600)));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Свернуть всё'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Развернуть всё'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.text('Мясное ассорти'), findsOneWidget);
    },
  );
}
