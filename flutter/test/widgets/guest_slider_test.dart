import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/core/utils/format.dart';
import 'package:mereytoi_app/domain/restaurant/restaurant_guest_bounds.dart';
import 'package:mereytoi_app/domain/restaurant/restaurant_price_calculator.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/screens/service_detail/service_detail_screen.dart';
import 'package:mereytoi_app/state/cart_provider.dart';
import 'package:mereytoi_app/state/listings_provider.dart';
import 'package:mereytoi_app/state/locale_provider.dart';
import 'package:mereytoi_app/widgets/guest_slider.dart';
import 'package:mereytoi_app/widgets/numeric_stepper_field.dart';
import 'package:mereytoi_app/widgets/restaurant/guest_selector.dart';
import 'package:mereytoi_app/widgets/restaurant/price_summary_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

final _slider = find.byKey(const ValueKey('guest-slider'));

/// Whitespace-agnostic match for a formatted price ("1 250 000 ₸" with
/// the ru locale's non-breaking group separators).
Finder _price(String digitsWithSpaces) => find.byWidgetPredicate(
  (w) =>
      w is Text &&
      (w.data ?? '').replaceAll(RegExp(r'\s'), ' ') == '$digitsWithSpaces ₸',
);

Listing _listing({required int price, int minGuests = 0, int maxGuests = 0}) =>
    Listing(
      id: 61,
      categoryId: 3,
      nameRu: 'Тамада',
      nameKz: 'Тамада',
      descriptionRu: '',
      descriptionKz: '',
      city: 'Алматы',
      phone: '',
      price: price,
      minGuests: minGuests,
      maxGuests: maxGuests,
      rating: 0,
      emoji: '',
      colorFrom: '',
      colorTo: '',
      imageUrls: const [],
      isActive: true,
    );

void _setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Restaurant guest card + the existing price summary, driven the same way
/// RestaurantDetailScreen's _MenuDetail drives them (calculator untouched).
class _RestaurantHost extends StatefulWidget {
  const _RestaurantHost({required this.bounds, required this.pricePerGuest});

  final GuestBounds bounds;
  final int pricePerGuest;

  @override
  State<_RestaurantHost> createState() => _RestaurantHostState();
}

class _RestaurantHostState extends State<_RestaurantHost> {
  int? _guests;

  @override
  Widget build(BuildContext context) {
    final guests = _guests ?? widget.bounds.min;
    final breakdown = RestaurantPriceCalculator.calculate(
      pricePerGuest: widget.pricePerGuest,
      guests: guests,
      selectedExtras: const [],
    );
    return Scaffold(
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          GuestSelector(
            guests: guests,
            bounds: widget.bounds,
            locale: AppLocale.ru,
            onChanged: (g) => setState(() => _guests = g),
          ),
          PriceSummaryCard(
            pricePerGuest: widget.pricePerGuest,
            guests: guests,
            breakdown: breakdown,
            locale: AppLocale.ru,
          ),
        ],
      ),
    );
  }
}

Future<void> _pumpRestaurant(
  WidgetTester tester, {
  GuestBounds bounds = (min: 50, max: 120),
  ThemeData? theme,
  Size size = const Size(390, 844),
}) async {
  _setSize(tester, size);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? AppTheme.dark,
      home: _RestaurantHost(bounds: bounds, pricePerGuest: 25000),
    ),
  );
  await tester.pumpAndSettle();
}

int _sliderValue(WidgetTester tester) =>
    tester.widget<Slider>(_slider).value.round();

void main() {
  group('GuestSlider', () {
    test(
      'slider max: real max when set, else the web fallback max(min*4, 200)',
      () {
        expect(GuestSlider.sliderMaxFor(min: 50, max: 120), 120);
        expect(GuestSlider.sliderMaxFor(min: 30, max: null), 200);
        expect(GuestSlider.sliderMaxFor(min: 80, max: null), 320);
      },
    );

    test('KZT format matches the site: grouped thousands + ₸', () {
      expect(
        formatPrice(1250000).replaceAll(RegExp(r'\s'), ' '),
        '1 250 000 ₸',
      );
    });
  });

  group('Restaurant menu calculator (Panorama-like: 50–120 × 25 000 ₸)', () {
    testWidgets('starts at min with min/max labels and the web total', (
      tester,
    ) async {
      await _pumpRestaurant(tester);
      expect(_sliderValue(tester), 50);
      expect(find.text('50 чел.'), findsOneWidget);
      expect(find.text('120 чел.'), findsOneWidget);
      expect(
        _price('1 250 000'),
        findsNWidgets(2),
      ); // 50 × 25 000 — base line + Итого
    });

    testWidgets(
      'dragging the slider to the ends hits max/min and recalculates live',
      (tester) async {
        await _pumpRestaurant(tester);
        await tester.drag(_slider, const Offset(800, 0));
        await tester.pumpAndSettle();
        expect(_sliderValue(tester), 120);
        expect(
          _price('3 000 000'),
          findsNWidgets(2),
        ); // 120 × 25 000 — base line + Итого
        expect(
          tester
              .widget<NumericStepperField>(find.byType(NumericStepperField))
              .value,
          120,
        );

        await tester.drag(_slider, const Offset(-800, 0));
        await tester.pumpAndSettle();
        expect(_sliderValue(tester), 50);
        expect(_price('1 250 000'), findsNWidgets(2)); // base line + Итого
      },
    );

    testWidgets('±1 on the stepper moves the slider (synced)', (tester) async {
      await _pumpRestaurant(tester);
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      await tester.tap(find.byIcon(Icons.add_rounded));
      await tester.pumpAndSettle();
      expect(_sliderValue(tester), 52);
      expect(
        _price('1 300 000'),
        findsNWidgets(2),
      ); // 52 × 25 000 — base line + Итого

      await tester.tap(find.byIcon(Icons.remove_rounded));
      await tester.pumpAndSettle();
      expect(_sliderValue(tester), 51);
    });

    testWidgets(
      'no menu max: slider uses the web fallback range, stepper still unbounded',
      (tester) async {
        await _pumpRestaurant(tester, bounds: (min: 30, max: null));
        expect(find.text('200 чел.'), findsOneWidget);
        expect(
          tester
              .widget<NumericStepperField>(find.byType(NumericStepperField))
              .max,
          isNull,
        );
      },
    );

    for (final name in ['dark', 'light']) {
      testWidgets('320dp, $name theme: no overflow', (tester) async {
        await _pumpRestaurant(
          tester,
          theme: name == 'dark' ? AppTheme.dark : AppTheme.light,
          size: const Size(320, 640),
        );
        expect(tester.takeException(), isNull);
        expect(_slider, findsOneWidget);
      });
    }
  });

  group('Per-person service (ServiceDetailScreen)', () {
    Future<ProviderContainer> pumpService(
      WidgetTester tester,
      Listing listing,
    ) async {
      SharedPreferences.setMockInitialValues({});
      _setSize(tester, const Size(390, 844));
      final container = ProviderContainer(
        overrides: [
          listingDetailProvider(
            61,
          ).overrideWith((ref) => Future.value(listing)),
        ],
      );
      addTearDown(container.dispose);
      await tester.pumpWidget(
        UncontrolledProviderScope(
          container: container,
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const ServiceDetailScreen(listingId: 61),
          ),
        ),
      );
      await tester.pumpAndSettle();
      return container;
    }

    testWidgets('starts at min_guests like the web, with min × price total', (
      tester,
    ) async {
      await pumpService(
        tester,
        _listing(price: 5000, minGuests: 10, maxGuests: 200),
      );
      expect(find.text('10 чел.'), findsOneWidget);
      expect(_price('50 000'), findsOneWidget); // 10 × 5 000
    });

    testWidgets(
      'sheet: slider + stepper stay synced and the sticky total follows',
      (tester) async {
        await pumpService(
          tester,
          _listing(price: 5000, minGuests: 10, maxGuests: 200),
        );
        await tester.tap(find.text('10 чел.'));
        await tester.pumpAndSettle();
        expect(_slider, findsOneWidget);

        // ±1 used to read the sheet's opening value forever; now it moves on.
        await tester.tap(find.byIcon(Icons.add_rounded));
        await tester.pumpAndSettle();
        await tester.tap(find.byIcon(Icons.add_rounded));
        await tester.pumpAndSettle();
        expect(_sliderValue(tester), 12);

        await tester.drag(_slider, const Offset(800, 0));
        await tester.pumpAndSettle();
        expect(_sliderValue(tester), 200);
        expect(
          tester
              .widget<NumericStepperField>(find.byType(NumericStepperField))
              .value,
          200,
        );
        expect(_price('1 000 000'), findsOneWidget); // sticky bar: 200 × 5 000
      },
    );

    testWidgets(
      'add to cart stores the calculated guests / unitPrice / total',
      (tester) async {
        final container = await pumpService(
          tester,
          _listing(price: 5000, minGuests: 10, maxGuests: 200),
        );
        await tester.tap(find.text('10 чел.'));
        await tester.pumpAndSettle();
        await tester.drag(_slider, const Offset(800, 0));
        await tester.pumpAndSettle();
        await tester.tap(find.text('Готово'));
        await tester.pumpAndSettle();

        await tester.tap(find.text('В корзину'));
        await tester.pumpAndSettle();

        final items = container.read(cartProvider);
        expect(items, hasLength(1));
        expect(items.single.guests, 200);
        expect(items.single.unitPrice, 5000);
        expect(items.single.totalPrice, 1000000);
      },
    );

    testWidgets(
      'fixed-price service: no guest chip, no slider, total = price',
      (tester) async {
        await pumpService(tester, _listing(price: 250000));
        expect(find.textContaining('чел.'), findsNothing);
        expect(_slider, findsNothing);
        expect(_price('250 000'), findsWidgets);
      },
    );
  });
}
