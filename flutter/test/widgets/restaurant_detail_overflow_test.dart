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

/// Stage 7 mobile-UX audit: `RestaurantDetailScreen` (halls/menus/guest
/// stepper/extras/calculator — brief section 3) had no widget-level
/// overflow coverage at all before this stage, only domain-level pricing
/// tests. Every string below is deliberately unrealistically long, same
/// approach as `test/widgets/overflow_test.dart`.
class _FakeAdapter implements HttpClientAdapter {
  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    final Map<String, dynamic> data;
    if (options.path == '/api/listings/16') {
      data = {'listing': _listingJson};
    } else if (options.path == '/api/listings/16/halls') {
      data = {
        'halls': [_hallJson],
      };
    } else if (options.path == '/api/listings/16/menus') {
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

final _listingJson = {
  'id': 16,
  'category_id': 2,
  'category': {
    'id': 2,
    'slug': 'venues',
    'name_ru': 'Рестораны и банкетные залы',
    'name_kz': 'Мейрамханалар',
    'position': 0,
  },
  'name_ru':
      'Sultan Palace Almaty — очень длинное название ресторана для банкетов и торжеств',
  'name_kz': 'Sultan Palace Almaty ұзақ атауы',
  'description_ru': 'Описание ' * 30,
  'description_kz': 'Сипаттама',
  'city': 'Алматы (очень длинное уточнение района для проверки переноса строк)',
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
  'address':
      'Алматы, очень длинный и подробный адрес с указанием ориентиров и подъезда со двора',
  'latitude': 43.238,
  'longitude': 76.945,
  'capacity': 500,
};

final _hallJson = {
  'id': 1,
  'listing_id': 16,
  'name_ru': 'Большой Императорский Зал с видом на горы Заилийского Алатау',
  'name_kz': 'Үлкен Императорлық Зал',
  'description_ru': '',
  'description_kz': '',
  'capacity': 500,
  'price': 0,
  'image_urls': <String>[],
  'is_active': true,
  'sort_order': 0,
};

final _menuJson = {
  'id': 2,
  'listing_id': 16,
  'hall_id': 1,
  'name_ru':
      'Очень длинное название банкетного меню премиум класса для больших торжеств №1',
  'name_kz': 'Ұзақ атау',
  'description_ru': '',
  'description_kz': '',
  'price_per_guest': 25000,
  'min_guests': 50,
  'max_guests': 500,
  'is_active': true,
  'sort_order': 0,
  'sections': [
    {
      'id': 3,
      'menu_id': 2,
      'title_ru':
          'Очень длинное название раздела меню с холодными закусками и салатами',
      'title_kz': 'Бөлім',
      'sort_order': 0,
      'items': [
        {
          'id': 5,
          'section_id': 3,
          'name_ru':
              'Мясное ассорти из говядины, баранины и конины с гарниром из свежих овощей',
          'name_kz': 'Ет ассортиси',
          'quantity_text': '250 г на человека',
          'sort_order': 0,
        },
      ],
    },
  ],
  'extras': [
    {
      'id': 9,
      'menu_id': 2,
      'type': 'kids_table',
      'title_ru':
          'Детский стол с аниматором, отдельным меню и украшением зала шарами',
      'title_kz': 'Балалар үстелі',
      'price': 12000,
      'unit': 'per_guest',
      'sort_order': 0,
    },
    {
      'id': 10,
      'menu_id': 2,
      'type': 'service_fee',
      'title_ru': 'Сервисный сбор за полное обслуживание банкета официантами',
      'title_kz': 'Қызмет ақысы',
      'price': 10,
      'unit': 'percent',
      'sort_order': 1,
    },
  ],
};

void main() {
  const sizes = [Size(320, 700), Size(360, 800)];

  for (final size in sizes) {
    testWidgets(
      'RestaurantDetailScreen (halls/menus/extras/calculator, long RU text) does not overflow at ${size.width.toInt()}px',
      (tester) async {
        final client = ApiClient.test(tokenProvider: () async => null);
        client.debugDio.httpClientAdapter = _FakeAdapter();
        final container = ProviderContainer(
          overrides: [apiClientProvider.overrideWithValue(client)],
        );
        addTearDown(container.dispose);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MediaQuery(
              data: MediaQueryData(size: size),
              child: MaterialApp(
                theme: AppTheme.dark,
                home: const RestaurantDetailScreen(listingId: 16),
              ),
            ),
          ),
        );
        // Two network round-trips (listing, then halls/menus) resolve
        // across a few pump cycles — pumpAndSettle drains them all.
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );
  }
}
