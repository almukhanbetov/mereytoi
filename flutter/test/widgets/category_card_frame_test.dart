import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/models/category.dart';
import 'package:mereytoi_app/state/locale_provider.dart';
import 'package:mereytoi_app/widgets/category_card.dart';

Category _category({String? imageUrl}) => Category(
  id: 4,
  slug: 'artists',
  nameRu: 'Артисты и исполнители',
  nameKz: 'Әртістер мен орындаушылар',
  position: 4,
  imageUrl: imageUrl,
);

void main() {
  Future<void> pumpGrid(
    WidgetTester tester,
    Category category, {
    double width = 393,
    ThemeData Function()? theme,
  }) async {
    tester.view.physicalSize = Size(width, 700);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        theme: (theme ?? () => AppTheme.light)(),
        home: Scaffold(
          // Home's own two-column grid rhythm.
          body: GridView.count(
            crossAxisCount: 2,
            padding: const EdgeInsets.all(20),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.92,
            children: [
              CategoryCard(
                category: category,
                locale: AppLocale.ru,
                onTap: () {},
              ),
              CategoryCard(
                category: _category(),
                locale: AppLocale.ru,
                onTap: () {},
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pump();
  }

  Container frame(WidgetTester tester) => tester.widget<Container>(
    find
        .descendant(
          of: find.byType(CategoryCard),
          matching: find.byWidgetPredicate(
            (w) => w is Container && w.foregroundDecoration != null,
          ),
        )
        .first,
  );

  for (final (label, url) in [
    ('with a photo', '/uploads/a.jpg'),
    ('without a photo (placeholder)', null),
  ]) {
    testWidgets('$label: 1px border at the card radius, soft shadow', (
      tester,
    ) async {
      await pumpGrid(tester, _category(imageUrl: url));

      final fg = frame(tester).foregroundDecoration! as BoxDecoration;
      expect((fg.border! as Border).top.width, 1);
      expect(fg.borderRadius, BorderRadius.circular(AppRadius.lg));

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

      // Photo + scrim still clipped to the same radius.
      final material = tester.widget<Material>(
        find
            .descendant(
              of: find.byType(CategoryCard),
              matching: find.byType(Material),
            )
            .first,
      );
      expect(material.clipBehavior, Clip.antiAlias);
      expect(material.borderRadius, BorderRadius.circular(AppRadius.lg));

      // Size unchanged: the card keeps its 0.92 aspect ratio.
      final size = tester.getSize(find.byType(CategoryCard).first);
      expect(size.width / size.height, closeTo(0.92, 0.01));
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
        await pumpGrid(
          tester,
          _category(imageUrl: '/uploads/a.jpg'),
          width: width,
          theme: theme.$2,
        );
        expect(tester.takeException(), isNull);
      });
    }
  }
}
