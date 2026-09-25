import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/network/api_client.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/models/user.dart';
import 'package:mereytoi_app/screens/manager_chat/manager_chat_screen.dart';
import 'package:mereytoi_app/screens/restaurant/restaurant_detail_screen.dart';
import 'package:mereytoi_app/state/auth_provider.dart';
import 'package:mereytoi_app/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Этап 10Б-53, brief item 4 — "для выбранного зала, меню, количества
/// гостей и рассчитанной стоимости используй существующий механизм
/// передачи контекста". The mechanism (`ManagerChatContext`'s
/// hallName/menuName/guestCount/estimatedTotal fields +
/// `restaurantContextText`) already existed but no caller ever populated
/// it — this exercises the fix wiring `RestaurantDetailScreen`'s live
/// selection into the hero's "Спросить менеджера" button.
class _EmptySecureStoragePlatform extends FlutterSecureStoragePlatform {
  @override
  Future<bool> containsKey({
    required String key,
    required Map<String, String> options,
  }) => Future.value(false);
  @override
  Future<void> delete({
    required String key,
    required Map<String, String> options,
  }) async {}
  @override
  Future<void> deleteAll({required Map<String, String> options}) async {}
  @override
  Future<String?> read({
    required String key,
    required Map<String, String> options,
  }) => Future.value(null);
  @override
  Future<Map<String, String>> readAll({required Map<String, String> options}) =>
      Future.value(const {});
  @override
  Future<void> write({
    required String key,
    required String value,
    required Map<String, String> options,
  }) async {}
}

class _FakeAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final Map<String, dynamic> data;
    if (options.path == '/api/listings/48') {
      data = {'listing': _listingJson};
    } else if (options.path == '/api/listings/48/halls') {
      data = {
        'halls': [_hallJson],
      };
    } else if (options.path == '/api/listings/48/menus') {
      data = {
        'menus': [_menuJson],
      };
    } else if (options.path == '/api/manager-chat/start') {
      // A plain contextless "peek" — this test only cares about what the
      // chat screen was *opened with*, not the conversation round trip
      // (that's `manager_chat_screen_test.dart`'s job).
      data = {'conversation': null, 'messages': <Map<String, dynamic>>[]};
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

final _listingJson = {
  'id': 48,
  'category_id': 2,
  'category': {
    'id': 2,
    'slug': 'venues',
    'name_ru': 'Рестораны',
    'name_kz': 'Мейрамханалар',
    'position': 0,
  },
  'name_ru': 'Panorama',
  'name_kz': 'Panorama',
  'description_ru': '',
  'description_kz': '',
  'city': 'Алматы',
  'phone': '+7 700 123 45 67',
  'price': 0,
  'min_guests': 50,
  'max_guests': 500,
  'rating': 4.8,
  'emoji': '',
  'color_from': '',
  'color_to': '',
  'image_urls': <String>[],
  'video_urls': <String>[],
  'is_active': true,
  'capacity': 500,
};

final _hallJson = {
  'id': 1,
  'listing_id': 48,
  'name_ru': 'Малый зал',
  'name_kz': 'Кіші зал',
  'description_ru': '',
  'description_kz': '',
  'capacity': 80,
  'price': 0,
  'image_urls': <String>[],
  'is_active': true,
  'sort_order': 0,
};

final _menuJson = {
  'id': 2,
  'listing_id': 48,
  'hall_id': null,
  'name_ru': 'Банкетное меню',
  'name_kz': 'Банкет мәзірі',
  'description_ru': '',
  'description_kz': '',
  'price_per_guest': 25000,
  'min_guests': 50,
  'max_guests': 500,
  'is_active': true,
  'sort_order': 0,
  'sections': <Map<String, dynamic>>[],
  'extras': <Map<String, dynamic>>[],
};

final _user = User(
  id: 9,
  name: 'Алия',
  email: 'aliya@example.com',
  phone: '+7 700 000 00 00',
  role: 'user',
  status: 'active',
  createdAt: DateTime(2026, 1, 1),
  updatedAt: DateTime(2026, 1, 1),
);

void main() {
  testWidgets(
    '"Спросить менеджера" on the restaurant page carries the selected hall/menu/guests into the chat context card',
    (tester) async {
      FlutterSecureStoragePlatform.instance = _EmptySecureStoragePlatform();
      SharedPreferences.setMockInitialValues({});

      final client = ApiClient.test(tokenProvider: () async => 'test-token');
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
      // `RestaurantDetailScreen`'s own listing/halls/menus round-trips can
      // make `pumpAndSettle()` return *before* `AuthNotifier`'s
      // background session-restore has actually finished (it's still
      // `AuthLoading` here, not yet `AuthUnauthenticated`) — overriding
      // too early gets silently clobbered the moment that restore does
      // resolve. Poll past it explicitly first.
      while (container.read(authProvider) is AuthLoading ||
          container.read(authProvider) is AuthInitial) {
        await tester.pump(const Duration(milliseconds: 10));
      }
      container.read(authProvider.notifier).state = AuthAuthenticated(_user);
      await tester.pumpAndSettle();

      // The single hall and single menu both auto-select — same shortcut
      // `restaurant_selection_progress_test.dart` already exercises
      // directly; here it's just the setup for a populated context.
      await tester.tap(find.text('Спросить менеджера'));
      await tester.pumpAndSettle();

      expect(find.byType(ManagerChatScreen), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ManagerChatScreen),
          matching: find.text('Малый зал'),
        ),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: find.byType(ManagerChatScreen),
          matching: find.text('Банкетное меню'),
        ),
        findsOneWidget,
      );

      container.dispose();
    },
  );
}
