import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/screens/service_detail/service_detail_screen.dart';
import 'package:mereytoi_app/state/listings_provider.dart';

/// Этап 10Б-1 — the ordinary per-person service's sticky CTA used to
/// hand-roll its own "+/− only" guest stepper (`_GuestStepper`, now
/// removed); it's now a compact "N чел. ▾" chip that opens a bottom sheet
/// containing the same [NumericStepperField] the restaurant calculator
/// uses. Covers that the chip shows the current count, opens the sheet,
/// and that committing a new value in the sheet actually updates the
/// price shown on the sticky bar.
Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(theme: AppTheme.dark, home: child),
  );
}

final _perPersonListing = Listing(
  id: 61,
  categoryId: 3,
  nameRu: 'Тамада с ведущим',
  nameKz: 'Тамада',
  descriptionRu: '',
  descriptionKz: '',
  city: 'Алматы',
  phone: '',
  price: 5000,
  minGuests: 10,
  maxGuests: 200,
  rating: 0,
  emoji: '',
  colorFrom: '',
  colorTo: '',
  imageUrls: const [],
  isActive: true,
);

void main() {
  testWidgets(
    'the sticky bar shows a tappable guest-count chip that opens a numeric editor sheet',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          ProviderScope(
            overrides: [
              listingDetailProvider(
                61,
              ).overrideWith((ref) => Future.value(_perPersonListing)),
            ],
            child: const ServiceDetailScreen(listingId: 61),
          ),
        ),
      );
      await tester.pumpAndSettle();

      // Starts at the default 1 guest, clamped up to min_guests=10 by the
      // sheet's own bounds once opened — but the chip itself reflects
      // whatever _guests currently is (1, unclamped, since the screen's
      // own state starts there and nothing has changed it yet). Exact
      // match, not textContaining — the price-per-guest label above it
      // ("5 000 ₸ / чел.") also contains "чел.".
      expect(find.text('1 чел.'), findsOneWidget);

      await tester.tap(find.text('1 чел.'));
      await tester.pumpAndSettle();

      expect(find.text('Количество гостей'), findsOneWidget);
      expect(find.byType(TextField), findsOneWidget);
    },
  );

  testWidgets(
    'committing a new guest count in the sheet updates the sticky total',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          ProviderScope(
            overrides: [
              listingDetailProvider(
                61,
              ).overrideWith((ref) => Future.value(_perPersonListing)),
            ],
            child: const ServiceDetailScreen(listingId: 61),
          ),
        ),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('1 чел.'));
      await tester.pumpAndSettle();

      await tester.enterText(find.byType(TextField), '20');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Готово'));
      await tester.pumpAndSettle();

      // price = 5000/guest * 20 guests = 100 000 — the sticky bar's own
      // total, not re-derived here, just confirmed it reflects the new
      // count.
      expect(find.text('20 чел.'), findsOneWidget);
      expect(find.textContaining('100'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
