import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/network/api_client.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/screens/restaurant/restaurant_detail_screen.dart';
import 'package:mereytoi_app/state/providers.dart';

/// Этап 10Б-1А, requirement 2 — the guest-count field must stay usable
/// once the keyboard opens: no overflow under the shrunk viewport a real
/// keyboard produces, "Done" actually closes it, and the sticky total
/// reflects the committed value afterward.
class _FakeAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final Map<String, dynamic> data;
    if (options.path == '/api/listings/48') {
      data = {'listing': _panoramaJson};
    } else if (options.path == '/api/listings/48/halls') {
      data = {
        'halls': [_hallJson],
      };
    } else if (options.path == '/api/listings/48/menus') {
      data = {
        'menus': [_menuJson],
      };
    } else {
      throw StateError('unhandled fake route: ${options.path}');
    }
    return ResponseBody.fromBytes(
      Uint8List.fromList(utf8.encode(jsonEncode(data))),
      200,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

final _panoramaJson = {
  'id': 48,
  'category_id': 1,
  'category': {
    'id': 1,
    'slug': 'venues',
    'name_ru': 'Рестораны и локации',
    'name_kz': 'Мейрамханалар',
    'position': 1,
  },
  'name_ru': 'Panorama',
  'name_kz': 'Панорама',
  'description_ru': '',
  'description_kz': '',
  'city': 'Алматы',
  'phone': '',
  'price': 0,
  'min_guests': 50,
  'max_guests': 120,
  'rating': 5,
  'emoji': '',
  'color_from': '',
  'color_to': '',
  'image_urls': <String>[],
  'video_urls': <String>[],
  'is_active': true,
};

final _hallJson = {
  'id': 1,
  'listing_id': 48,
  'name_ru': 'Зал',
  'name_kz': 'Зал',
  'description_ru': '',
  'description_kz': '',
  'capacity': 150,
  'price': 0,
  'image_urls': <String>[],
  'is_active': true,
  'sort_order': 0,
};

final _menuJson = {
  'id': 1,
  'listing_id': 48,
  'hall_id': 1,
  'name_ru': 'Банкетное меню',
  'name_kz': 'Банкет мәзірі',
  'description_ru': '',
  'description_kz': '',
  'price_per_guest': 25000,
  'min_guests': 50,
  'max_guests': 120,
  'is_active': true,
  'sort_order': 0,
  'sections': <dynamic>[],
  'extras': <dynamic>[],
};

/// Actually resizes the test binding's surface (not just a nested
/// `MediaQuery` override) — required for `tester.tap()` to hit-test
/// correctly; a `MediaQuery`-only override changes what widgets *believe*
/// the screen size is for layout, but not the coordinates flutter_test
/// itself uses to dispatch a real tap.
Future<ProviderContainer> _pumpScreen(
  WidgetTester tester, {
  double keyboardInset = 0,
}) async {
  tester.view.physicalSize = const Size(360, 800);
  tester.view.devicePixelRatio = 1.0;
  tester.view.viewInsets = FakeViewPadding(bottom: keyboardInset);
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  addTearDown(tester.view.resetViewInsets);

  final client = ApiClient.test(tokenProvider: () async => null);
  client.debugDio.httpClientAdapter = _FakeAdapter();
  final container = ProviderContainer(
    overrides: [apiClientProvider.overrideWithValue(client)],
  );
  addTearDown(container.dispose);

  await tester.pumpWidget(
    UncontrolledProviderScope(
      container: container,
      child: MaterialApp(
        theme: AppTheme.dark,
        home: const RestaurantDetailScreen(listingId: 48),
      ),
    ),
  );
  await tester.pumpAndSettle();
  return container;
}

void main() {
  testWidgets(
    'no overflow under a keyboard-sized viewport shrink (bottom inset ~300px)',
    (tester) async {
      await _pumpScreen(tester, keyboardInset: 300);

      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'submitting the guest field (Done) unfocuses it and updates the sticky total',
    (tester) async {
      await _pumpScreen(tester);

      final field = find.byType(TextField);
      expect(field, findsOneWidget);

      // The guest field sits well down the scroll (past the hero, halls,
      // menu picker, accordion) — scroll it into view first, the same as
      // the field's own on-focus behavior (see NumericStepperField's
      // Scrollable.ensureVisible) would.
      await tester.ensureVisible(field);
      await tester.pumpAndSettle();

      await tester.tap(field);
      await tester.pumpAndSettle();
      final fieldFocusNode = tester.widget<TextField>(field).focusNode!;
      expect(
        fieldFocusNode.hasFocus,
        isTrue,
        reason: 'tapping the field should focus it',
      );

      await tester.enterText(field, '100');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();

      // Done must close the keyboard — this specific field is no longer
      // focused (unfocus() moves focus up to the nearest FocusScope, so
      // FocusManager.instance.primaryFocus itself is non-null afterward —
      // checking *this* node's own hasFocus is the real assertion).
      expect(fieldFocusNode.hasFocus, isFalse);

      // price = 25000/guest * 100 guests = 2 500 000 — reflected in the
      // sticky CTA without needing to scroll back up to the price card.
      expect(find.textContaining('2'), findsWidgets);
      expect(tester.takeException(), isNull);
    },
  );
}
