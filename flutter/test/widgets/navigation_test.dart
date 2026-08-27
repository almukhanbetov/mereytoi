import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/models/category.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/screens/service_detail/service_detail_screen.dart';
import 'package:mereytoi_app/screens/services/services_screen.dart';
import 'package:mereytoi_app/state/categories_provider.dart';
import 'package:mereytoi_app/state/listings_provider.dart';
import 'package:mereytoi_app/widgets/app_back_button.dart';

/// `ServicesScreen` always watches these — every test that pumps it (even
/// only to check for a back button) needs them stubbed so it never makes a
/// real network call.
final _noNetworkOverrides = [
  categoriesProvider.overrideWith((ref) => Future.value(const <Category>[])),
  listingsProvider(null).overrideWith((ref) => Future.value(const <Listing>[])),
];

/// Covers the back-navigation gap this change closes: Service Detail's
/// loading/error states used to render with *no* app bar at all (the back
/// button only existed inside the hero `SliverAppBar`, which is only built
/// once data actually arrives) — so a slow or failing request left the user
/// with no on-screen way back. These pump the screen in each state and
/// assert a back control is always present, then exercise a real push +
/// tap-to-pop to confirm `Navigator.pop` (not a hard redirect) is what
/// actually runs.
Widget _wrap(Widget home, {List<Override> overrides = const []}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(theme: AppTheme.dark, home: home),
  );
}

/// Pushes [target] on top of a plain root screen — every real usage in this
/// app reaches these screens via `Navigator.push`, never as the very first
/// route, so `Navigator.canPop` (which the back-button logic depends on)
/// needs a real predecessor to be meaningful.
Future<void> _pumpPushed(WidgetTester tester, Widget target, {List<Override> overrides = const []}) async {
  await tester.pumpWidget(
    _wrap(
      Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => target)),
              child: const Text('open'),
            ),
          ),
        ),
      ),
      overrides: overrides,
    ),
  );
  await tester.tap(find.text('open'));
  await tester.pump();
}

final _listing = const Listing(
  id: 42,
  categoryId: 1,
  nameRu: 'AURORA QUINTET',
  nameKz: 'AURORA QUINTET',
  descriptionRu: 'Живая музыка на торжество',
  descriptionKz: 'Той үшін тірі музыка',
  city: 'Алматы',
  phone: '+7 700 123 45 67',
  price: 250000,
  minGuests: 0,
  maxGuests: 0,
  rating: 4.8,
  emoji: '',
  colorFrom: '',
  colorTo: '',
  imageUrls: [],
  isActive: true,
);

void main() {
  testWidgets('Service Detail shows a visible back button while still loading (regression: used to have none)', (tester) async {
    // Never resolves — pins the screen in its "loading" state so the fix (a
    // plain AppBar for non-data states) is what's under test.
    await _pumpPushed(
      tester,
      const ServiceDetailScreen(listingId: 42),
      overrides: [listingDetailProvider(42).overrideWith((ref) => Completer<Listing>().future)],
    );
    await tester.pump(const Duration(milliseconds: 400)); // let the push transition finish

    expect(find.byType(BackButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Service Detail shows a visible back button on error', (tester) async {
    await _pumpPushed(
      tester,
      const ServiceDetailScreen(listingId: 42),
      overrides: [listingDetailProvider(42).overrideWith((ref) => Future<Listing>.error(Exception('network down')))],
    );
    await tester.pump(); // let the error state settle in

    expect(find.byType(BackButton), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Service Detail (loaded): the hero back button pops via Navigator.pop, not a hard redirect', (tester) async {
    await _pumpPushed(
      tester,
      const ServiceDetailScreen(listingId: 42),
      overrides: [listingDetailProvider(42).overrideWith((ref) => Future.value(_listing))],
    );
    await tester.pumpAndSettle();

    expect(find.text('AURORA QUINTET'), findsOneWidget);
    expect(find.byType(AppBackButton), findsOneWidget); // the styled hero back button, not the default BackButton

    await tester.tap(find.byType(AppBackButton));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('open'), findsOneWidget); // back on the screen we pushed from
    expect(find.text('AURORA QUINTET'), findsNothing);
  });

  testWidgets('ServicesScreen shows no back button as a tab root, but a real one when pushed on top of another screen', (tester) async {
    await tester.pumpWidget(_wrap(const ServicesScreen(), overrides: _noNetworkOverrides));
    await tester.pump();
    expect(find.byType(BackButton), findsNothing);
    expect(find.byType(AppBackButton), findsNothing);

    await _pumpPushed(tester, const ServicesScreen(), overrides: _noNetworkOverrides);
    await tester.pump();

    expect(find.byType(AppBackButton), findsOneWidget);
    await tester.tap(find.byType(AppBackButton));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('open'), findsOneWidget);
  });
}
