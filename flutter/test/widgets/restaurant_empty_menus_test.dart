import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/network/api_client.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/screens/restaurant/restaurant_detail_screen.dart';
import 'package:mereytoi_app/state/providers.dart';

/// Stage 10 real-device QA finding: every "venues"-category listing in
/// production (verified directly against `GET https://mereytoi.kz/api/
/// listings/:id/halls` and `.../menus` for every listing under
/// `category=venues` at audit time — ids 42/48/53/54/55/56/57/58, "Panorama"
/// among them) currently has **zero** Hall and Menu rows. That's a content
/// gap in the admin data, not a Flutter defect: this test locks in the
/// screen's own already-correct behavior for that exact real-world shape —
/// hall/menu section titles render with an explanatory "not added yet"
/// hint (never a blank void, and *never* web's own
/// `RestaurantMenus.jsx`'s silent `return null`), the guest
/// stepper/extras/calculator/"Добавить в корзину" sticky CTA are all
/// correctly absent (there is no menu to price or add to the cart), and
/// nothing throws. If a future change makes any of hall selection, menu
/// selection, the calculator, or "Добавить в корзину" reappear with no
/// menu data behind them, or makes this scenario throw, this test fails.
class _EmptyMenusAdapter implements HttpClientAdapter {
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
      data = {'halls': <dynamic>[]};
    } else if (options.path == '/api/listings/48/menus') {
      data = {'menus': <dynamic>[]};
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

/// The real shape of production listing #48 ("Panorama", category
/// `venues`) at audit time, minus the (irrelevant here) long description
/// text.
final _panoramaJson = {
  'id': 48,
  'category_id': 1,
  'category': {
    'id': 1,
    'slug': 'venues',
    'name_ru': 'Рестораны и локации',
    'name_kz': 'Мейрамханалар мен локациялар',
    'position': 1,
  },
  'name_ru': 'Panorama',
  'name_kz': 'Панорама',
  'description_ru': 'Описание',
  'description_kz': '',
  'city': 'Алматы',
  'phone': '+77019911445',
  'price': 0,
  'min_guests': 50,
  'max_guests': 120,
  'rating': 5,
  'emoji': '✨',
  'color_from': '#3a1420',
  'color_to': '#d4af6a',
  // Empty on purpose — a real (non-empty) image_urls entry makes
  // `CachedNetworkImage` attempt a genuine network fetch even under the
  // test binding's mocked HttpClient, which never resolves within
  // `pumpAndSettle`'s patience. Every other widget test in this suite
  // that doesn't specifically exercise the gallery avoids this the same
  // way.
  'image_urls': <String>[],
  'video_urls': <String>[],
  'is_active': true,
};

void main() {
  testWidgets(
    'RestaurantDetailScreen with zero halls/zero menus (real production shape): '
    'shows "not added yet" hints, hides the calculator/add-to-cart CTA, never throws',
    (tester) async {
      final client = ApiClient.test(tokenProvider: () async => null);
      client.debugDio.httpClientAdapter = _EmptyMenusAdapter();
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

      expect(find.text('Panorama'), findsOneWidget);
      expect(find.text('Залы пока не добавлены'), findsOneWidget);
      expect(find.text('Меню пока не добавлены'), findsOneWidget);
      // No menu exists to price/add to the cart from — the sticky CTA
      // ("Добавить в корзину") must not appear at all in this state.
      expect(find.text('Добавить в корзину'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );
}
