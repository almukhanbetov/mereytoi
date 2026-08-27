import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/models/category.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/screens/cart/cart_screen.dart';
import 'package:mereytoi_app/state/locale_provider.dart';
import 'package:mereytoi_app/widgets/category_card.dart';
import 'package:mereytoi_app/widgets/category_filter_bar.dart';
import 'package:mereytoi_app/widgets/service_card.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// These specifically target the overflow risk called out in the redesign
/// brief: a fixed-size grid tile (via `mainAxisExtent`/`childAspectRatio`)
/// paired with real (long, admin-entered) text. Every text field is
/// deliberately made unrealistically long so a regression that removes a
/// `maxLines`/`overflow`/`FittedBox` safety net fails loudly here instead
/// of silently shipping a RenderFlex overflow banner on a real device.
Widget _wrap(Widget child, {required Size size}) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: ProviderScope(
      child: MaterialApp(
        theme: AppTheme.dark,
        home: Scaffold(body: child),
      ),
    ),
  );
}

final _longListing = Listing(
  id: 1,
  categoryId: 1,
  category: const Category(id: 1, slug: 'hosts', nameRu: 'Ведущие и очень длинное название категории', nameKz: 'Жүргізушілер', position: 0),
  nameRu: 'Очень длинное название услуги, которое обязательно должно перенестись на несколько строк если не ограничено',
  nameKz: 'Ұзақ атау',
  descriptionRu: 'Описание',
  descriptionKz: 'Сипаттама',
  city: 'Алматы (очень длинное название города для проверки)',
  phone: '+7 700 123 45 67',
  price: 123456789,
  minGuests: 0,
  maxGuests: 0,
  rating: 4.9,
  emoji: '',
  colorFrom: '',
  colorTo: '',
  imageUrls: const [],
  isActive: true,
);

final _longCategory = const Category(
  id: 2,
  slug: 'venues',
  nameRu: 'Очень длинное название категории, которое может перенестись на несколько строк',
  nameKz: 'Ұзақ санат атауы',
  position: 0,
);

final _manyLongCategories = List.generate(
  8,
  (i) => Category(
    id: i + 10,
    slug: 'cat-$i',
    nameRu: 'Очень длинное название категории номер $i для проверки переполнения',
    nameKz: 'Ұзақ санат атауы $i',
    position: i,
  ),
);

void main() {
  // 320px is narrower than any target device (390/430) — a deliberately
  // tighter squeeze than we expect in practice.
  const narrowMobile = Size(320, 720);

  testWidgets('ServiceCard with long name/city/huge price does not overflow at 2-column grid width', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 150, // ~ one column of a 2-up grid on a 320px screen
          height: 262, // matches _kCardExtent in services_screen.dart
          child: ServiceCard(
            listing: _longListing,
            locale: AppLocale.ru,
            categoryLabel: _longListing.category!.nameRu,
            onTap: () {},
          ),
        ),
        size: narrowMobile,
      ),
    );
    await tester.pump(const Duration(milliseconds: 250)); // let the image fade-in/skeleton settle

    expect(tester.takeException(), isNull);
  });

  testWidgets('ServiceListTile (the primary services-list card) with long name/city does not overflow', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 320 - 40, // full-width list row minus the screen's horizontal padding
          child: ServiceListTile(
            listing: _longListing,
            locale: AppLocale.ru,
            categoryLabel: _longListing.category!.nameRu,
            onTap: () {},
          ),
        ),
        size: narrowMobile,
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));

    expect(tester.takeException(), isNull);
  });

  testWidgets('CategoryCard with a long two-line name does not overflow', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 150,
          height: 163, // childAspectRatio 0.92 at width 150
          child: CategoryCard(category: _longCategory, locale: AppLocale.ru, onTap: () {}),
        ),
        size: narrowMobile,
      ),
    );
    await tester.pump(const Duration(milliseconds: 250));

    expect(tester.takeException(), isNull);
  });

  testWidgets('Cart screen empty state renders without overflow at 320px width', (tester) async {
    await tester.pumpWidget(_wrap(const CartScreen(), size: narrowMobile));
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(CartScreen), findsOneWidget);
  });

  // This must be the *first* CategoryFilterBar test in the file: the
  // one-time nudge is gated by a module-level flag in the widget's own
  // file, so it only ever plays for whichever scrollable lane mounts first
  // across this whole test run — exactly the "once per session" behaviour
  // being verified here.
  testWidgets('CategoryFilterBar: one-time nudge plays and settles back to the start, lane holds every category with no overflow', (tester) async {
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 320 - 40, // matches the screen's own lg-padding gutter
          child: CategoryFilterBar(categories: _manyLongCategories, activeSlug: null, locale: AppLocale.ru, onSelect: (_) {}),
        ),
        size: narrowMobile,
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    // Let the nudge-right-and-settle-back sequence play out in full: first
    // advance past its initial `Future.delayed` (a bare Timer, not an
    // animation frame — `pumpAndSettle` alone won't fire it), then settle
    // the two `animateTo` calls it schedules once it starts.
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final controller = tester.widget<ListView>(find.byType(ListView)).controller!;
    expect(controller.offset, 0); // it always settles back to the very start

    // Every category is in the lane (nothing held back behind a "quick
    // filters" cutoff) — jump to the far end (deterministic, unlike a
    // drag-driven fling) and find the last one, plus the ever-present
    // "Все категории" chip.
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text(_manyLongCategories.last.nameRu), findsOneWidget);
    expect(find.text('Все категории'), findsOneWidget);
  });

  testWidgets('CategoryFilterBar "Все категории" chip opens the picker sheet and reports a pick', (tester) async {
    var selectCalled = false;
    String? selected;
    await tester.pumpWidget(
      _wrap(
        SizedBox(
          width: 320 - 40,
          child: CategoryFilterBar(
            categories: _manyLongCategories,
            activeSlug: _manyLongCategories[6].slug,
            locale: AppLocale.ru,
            onSelect: (slug) {
              selectCalled = true;
              selected = slug;
            },
          ),
        ),
        size: narrowMobile,
      ),
    );
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // "Все категории" is the lane's last item — jump there so it's actually
    // built (a lazy ListView never builds far-offscreen children).
    final controller = tester.widget<ListView>(find.byType(ListView)).controller!;
    controller.jumpTo(controller.position.maxScrollExtent);
    await tester.pump();

    await tester.tap(find.text('Все категории'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);

    // "Все услуги" is always the first (visible-without-scrolling) grid tile.
    await tester.tap(find.text('Все услуги'));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(selectCalled, isTrue);
    expect(selected, isNull);
  });

  for (final size in const [Size(360, 800), Size(390, 844), Size(412, 915), Size(430, 932)]) {
    testWidgets('CategoryFilterBar lane + picker sheet grid render without overflow at ${size.width.toInt()}x${size.height.toInt()}', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: CategoryFilterBar(categories: _manyLongCategories, activeSlug: null, locale: AppLocale.ru, onSelect: (_) {}),
          ),
          size: size,
        ),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);

      // Scroll the lane fully across — the real-world gesture most likely to
      // surface an overflow in a long-name, many-category lane.
      final controller = tester.widget<ListView>(find.byType(ListView)).controller!;
      controller.jumpTo(controller.position.maxScrollExtent);
      await tester.pump();
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('Все категории'));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      // 65–85% of the screen height, per spec — a 2-column grid of every
      // category should be present and rendered with no exception.
      expect(find.byType(GridView), findsOneWidget);

      await tester.tap(find.byIcon(Icons.close_rounded));
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    });
  }
}
