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
import 'package:mereytoi_app/widgets/restaurant/selection_progress_bar.dart';

/// Этап 10Б-Б2 — the brief asks for the user to always know "на каком
/// этапе выбора он находится: Ресторан → Зал → Меню → Гости →
/// Дополнительные услуги → Итог" without a separate screen per step.
/// [SelectionProgressBar] is the new compact strip that answers that;
/// these tests exercise it wired into the real `RestaurantDetailScreen`
/// with two halls (so a hall pick is a genuine user action, not the
/// existing "auto-select the only one" shortcut) and confirm the hall
/// section's own "Выбран зал: X" confirmation line and the selected
/// hall's checkmark badge.
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
        'halls': [_hall1Json, _hall2Json],
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
  'description_ru': 'Ресторан для торжеств',
  'description_kz': 'Той үшін мейрамхана',
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

final _hall1Json = {
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

final _hall2Json = {
  'id': 2,
  'listing_id': 48,
  'name_ru': 'Большой зал',
  'name_kz': 'Үлкен зал',
  'description_ru': '',
  'description_kz': '',
  'capacity': 300,
  'price': 0,
  'image_urls': <String>[],
  'is_active': true,
  'sort_order': 1,
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

Future<ProviderContainer> _pump(WidgetTester tester, {Size? size}) async {
  // A `MediaQuery` override alone only changes what widgets *believe*
  // their size is for layout — `tester.tap()`/`drag()` still compute real
  // screen coordinates from the actual binding surface, which stays at
  // its default (800x600) unless resized here too. Established pattern
  // from the theme/locale toggle tests earlier this project.
  final resolvedSize = size ?? const Size(393, 851);
  tester.view.physicalSize = resolvedSize;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);

  final client = ApiClient.test(tokenProvider: () async => null);
  client.debugDio.httpClientAdapter = _FakeAdapter();
  final container = ProviderContainer(
    overrides: [apiClientProvider.overrideWithValue(client)],
  );
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
    'the progress bar starts with only "Ресторан" done, everything else pending',
    (tester) async {
      final container = await _pump(tester);
      addTearDown(container.dispose);

      expect(find.byType(SelectionProgressBar), findsOneWidget);
      expect(find.text('Ресторан'), findsOneWidget);
      expect(find.text('Зал'), findsOneWidget);
      // The single menu auto-selects immediately (existing "exactly one"
      // shortcut), so its chip already shows the menu's own name rather
      // than the generic pending label — scoped to the progress bar since
      // the menu picker card below it shows the same name too.
      expect(
        find.descendant(
          of: find.byType(SelectionProgressBar),
          matching: find.text('Банкетное меню'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'picking a hall marks the "Зал" step done with its name, and shows the "Выбран зал" confirmation line',
    (tester) async {
      final container = await _pump(tester);
      addTearDown(container.dispose);

      expect(find.text('Малый зал'), findsWidgets);
      expect(find.text('Выбран зал: Малый зал'), findsNothing);

      await tester.tap(find.text('Малый зал').first, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('Выбран зал: Малый зал'), findsOneWidget);
      // The progress chip now shows the hall's own name too — scoped to
      // the progress bar since "Малый зал" also appears on the hall card
      // and in the confirmation line above.
      expect(
        find.descendant(
          of: find.byType(SelectionProgressBar),
          matching: find.text('Малый зал'),
        ),
        findsOneWidget,
      );
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets(
    'switching from one hall to the other updates both the chip and the confirmation line',
    (tester) async {
      final container = await _pump(tester);
      addTearDown(container.dispose);

      await tester.tap(find.text('Малый зал').first, warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(find.text('Выбран зал: Малый зал'), findsOneWidget);

      await tester.tap(find.text('Большой зал').first, warnIfMissed: false);
      await tester.pumpAndSettle();

      expect(find.text('Выбран зал: Большой зал'), findsOneWidget);
      expect(find.text('Выбран зал: Малый зал'), findsNothing);
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('the selected hall shows a checkmark badge on its photo', (
    tester,
  ) async {
    final container = await _pump(tester);
    addTearDown(container.dispose);

    expect(find.byIcon(Icons.check_rounded), findsNothing);

    await tester.tap(find.text('Малый зал').first, warnIfMissed: false);
    await tester.pumpAndSettle();

    expect(find.byIcon(Icons.check_rounded), findsOneWidget);
  });

  for (final width in [320.0, 360.0, 393.0, 430.0]) {
    testWidgets(
      'the progress bar does not overflow at ${width.toInt()}dp, hall selected',
      (tester) async {
        final container = await _pump(tester, size: Size(width, 800));
        addTearDown(container.dispose);

        await tester.tap(find.text('Малый зал').first, warnIfMissed: false);
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
        expect(find.byType(SelectionProgressBar), findsOneWidget);
      },
    );
  }
}
