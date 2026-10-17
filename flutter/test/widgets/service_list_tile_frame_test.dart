import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/state/locale_provider.dart';
import 'package:mereytoi_app/widgets/service_card.dart';

Listing _listing({required List<String> images}) => Listing(
  id: 1,
  categoryId: 1,
  nameRu: 'Очень длинное название услуги, которое занимает две строки',
  nameKz: 'Ұзақ атау',
  descriptionRu: '',
  descriptionKz: '',
  city: 'Алматы',
  phone: '',
  price: 500000,
  minGuests: 0,
  maxGuests: 0,
  rating: 4.9,
  emoji: '',
  colorFrom: '',
  colorTo: '',
  imageUrls: images,
  isActive: true,
);

void main() {
  Future<void> pumpTile(
    WidgetTester tester,
    Listing listing, {
    double width = 393,
    ThemeData Function()? theme,
  }) async {
    tester.view.physicalSize = Size(width, 400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: (theme ?? () => AppTheme.light)(),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: ServiceListTile(
              listing: listing,
              locale: AppLocale.ru,
              categoryLabel: 'Ведущие',
              onTap: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  /// The photo frame: the Container whose foreground draws the 1px border.
  Container frame(WidgetTester tester) => tester.widget<Container>(
    find.descendant(
      of: find.byType(ServiceListTile),
      matching: find.byWidgetPredicate(
        (w) => w is Container && w.foregroundDecoration != null,
      ),
    ),
  );

  for (final (label, images) in [
    ('with a photo', ['https://example.com/a.jpg']),
    ('without a photo (placeholder)', <String>[]),
  ]) {
    testWidgets('$label: same frame — 1px border, radius 16, soft shadow', (
      tester,
    ) async {
      await pumpTile(tester, _listing(images: images));

      final fg = frame(tester).foregroundDecoration! as BoxDecoration;
      final border = fg.border! as Border;
      expect(border.top.width, 1);
      expect(fg.borderRadius, BorderRadius.circular(AppRadius.md));

      final shadowBox = tester.widget<DecoratedBox>(
        find
            .ancestor(
              of: find.byWidget(frame(tester)),
              matching: find.byType(DecoratedBox),
            )
            .first,
      );
      final shadow = (shadowBox.decoration as BoxDecoration).boxShadow!.single;
      expect(shadow.blurRadius, inInclusiveRange(10, 14));
      expect(shadow.color.a, lessThan(0.15));

      // Photo size unchanged: 104 tall, ~32% of the content width.
      final size = tester.getSize(find.byWidget(frame(tester)));
      expect(size.height, 104);
      expect(tester.takeException(), isNull);
    });
  }

  final themes = <(String, ThemeData Function())>[
    ('light', () => AppTheme.light),
    ('dark', () => AppTheme.dark),
  ];
  for (final theme in themes) {
    for (final width in [320.0, 393.0]) {
      testWidgets('${theme.$1} · ${width.toInt()}px: no overflow', (
        tester,
      ) async {
        await pumpTile(
          tester,
          _listing(images: ['https://example.com/a.jpg']),
          width: width,
          theme: theme.$2,
        );
        expect(tester.takeException(), isNull);
        await pumpTile(
          tester,
          _listing(images: const []),
          width: width,
          theme: theme.$2,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
