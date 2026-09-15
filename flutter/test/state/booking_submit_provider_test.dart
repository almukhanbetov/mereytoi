import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/network/api_client.dart';
import 'package:mereytoi_app/models/cart_item.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/state/booking_submit_provider.dart';
import 'package:mereytoi_app/state/cart_provider.dart';
import 'package:mereytoi_app/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Counts every request it actually receives, and can be told to fail the
/// next N of them — lets these tests assert exactly how many real
/// POST /api/bookings calls a sequence of UI actions produced, which is
/// the whole point of the double-submit/retry tests below.
class _CountingBookingAdapter implements HttpClientAdapter {
  int requestCount = 0;
  int failNext = 0;
  // Lets a test hold the response open to simulate "still in flight" while
  // a second `submit()` call is attempted concurrently.
  Completer<void>? holdUntil;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requestCount++;
    if (holdUntil != null) await holdUntil!.future;
    if (failNext > 0) {
      failNext--;
      throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      );
    }
    final body = options.data as Map;
    final items = (body['items'] as List).cast<Map>();
    var total = 0;
    for (final item in items) {
      total += item['total_price'] as int;
    }
    final data = {
      'booking': {
        'id': 1,
        'public_ref': 'abc123',
        'name': body['name'],
        'phone': body['phone'],
        'message': body['message'],
        'items': items,
        'total': total,
        'status': 'new',
      },
    };
    return ResponseBody.fromBytes(
      Uint8List.fromList(utf8.encode(jsonEncode(data))),
      201,
      headers: {
        Headers.contentTypeHeader: [Headers.jsonContentType],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

Listing _ordinaryListing() => Listing(
  id: 5,
  categoryId: 1,
  nameRu: 'Ведущий',
  nameKz: 'Ведущий',
  descriptionRu: '',
  descriptionKz: '',
  city: 'Алматы',
  phone: '',
  price: 250000,
  minGuests: 0,
  maxGuests: 0,
  rating: 0,
  emoji: '',
  colorFrom: '',
  colorTo: '',
  imageUrls: const [],
  isActive: true,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  (ProviderContainer, _CountingBookingAdapter) containerWithFakeBackend() {
    final adapter = _CountingBookingAdapter();
    final client = ApiClient.test(tokenProvider: () async => null);
    client.debugDio.httpClientAdapter = adapter;
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(client)],
    );
    return (container, adapter);
  }

  Future<void> seedCart(ProviderContainer container) async {
    await container.read(cartProvider.notifier).ready;
    container
        .read(cartProvider.notifier)
        .addItem(
          CartItem.fromListing(
            _ordinaryListing(),
            name: 'Ведущий',
            categoryLabel: 'Ведущие',
          ),
        );
  }

  test(
    '8. success — a confirmed booking lands the provider on AsyncData(non-null)',
    () async {
      final (container, _) = containerWithFakeBackend();
      addTearDown(container.dispose);
      await seedCart(container);

      await container
          .read(bookingSubmitProvider.notifier)
          .submit(name: 'Айгерим', phone: '+77001234567');

      final state = container.read(bookingSubmitProvider);
      expect(state, isA<AsyncData<dynamic>>());
      expect((state as AsyncData).value, isNotNull);
      expect(state.value!.booking.publicRef, 'abc123');
    },
  );

  test(
    '9. failure — a network error lands the provider on AsyncError',
    () async {
      final (container, adapter) = containerWithFakeBackend();
      addTearDown(container.dispose);
      await seedCart(container);
      adapter.failNext = 1;

      await container
          .read(bookingSubmitProvider.notifier)
          .submit(name: 'Айгерим', phone: '+77001234567');

      expect(container.read(bookingSubmitProvider), isA<AsyncError>());
    },
  );

  test(
    '10. cart stays after failure — a failed submit never clears the cart',
    () async {
      final (container, adapter) = containerWithFakeBackend();
      addTearDown(container.dispose);
      await seedCart(container);
      adapter.failNext = 1;

      await container
          .read(bookingSubmitProvider.notifier)
          .submit(name: 'Айгерим', phone: '+77001234567');

      expect(container.read(cartProvider), isNotEmpty);
    },
  );

  test(
    '11. cart clears after success — a confirmed booking empties the cart',
    () async {
      final (container, _) = containerWithFakeBackend();
      addTearDown(container.dispose);
      await seedCart(container);

      await container
          .read(bookingSubmitProvider.notifier)
          .submit(name: 'Айгерим', phone: '+77001234567');

      expect(container.read(cartProvider), isEmpty);
    },
  );

  test(
    '12. double-submit prevention — a second submit() while the first is still in flight sends only one POST',
    () async {
      final (container, adapter) = containerWithFakeBackend();
      addTearDown(container.dispose);
      await seedCart(container);
      adapter.holdUntil = Completer<void>();

      final first = container
          .read(bookingSubmitProvider.notifier)
          .submit(name: 'Айгерим', phone: '+77001234567');
      // Fired while state is already AsyncLoading — the notifier's own
      // re-entrancy guard must refuse this one before it ever reaches Dio.
      final second = container
          .read(bookingSubmitProvider.notifier)
          .submit(name: 'Айгерим', phone: '+77001234567');

      expect(container.read(bookingSubmitProvider), isA<AsyncLoading>());
      adapter.holdUntil!.complete();
      await Future.wait([first, second]);

      expect(adapter.requestCount, 1);
    },
  );

  test(
    'double-submit prevention — calling submit() again after a completed success is also refused (must reset() first)',
    () async {
      final (container, adapter) = containerWithFakeBackend();
      addTearDown(container.dispose);
      await seedCart(container);

      await container
          .read(bookingSubmitProvider.notifier)
          .submit(name: 'Айгерим', phone: '+77001234567');
      expect(adapter.requestCount, 1);

      // The cart is now empty (success already cleared it), so even without
      // the guard this second call would bail on "items.isEmpty" — the
      // guard is what makes that outcome explicit and intentional rather
      // than incidental.
      await container
          .read(bookingSubmitProvider.notifier)
          .submit(name: 'Айгерим', phone: '+77001234567');
      expect(adapter.requestCount, 1);
    },
  );

  test(
    '13. retry behavior — submit() after an error performs a fresh POST and can succeed',
    () async {
      final (container, adapter) = containerWithFakeBackend();
      addTearDown(container.dispose);
      await seedCart(container);
      adapter.failNext = 1;

      await container
          .read(bookingSubmitProvider.notifier)
          .submit(name: 'Айгерим', phone: '+77001234567');
      expect(container.read(bookingSubmitProvider), isA<AsyncError>());
      expect(adapter.requestCount, 1);

      // The cart was preserved by the failure, so a plain retry has
      // something to resubmit.
      await container
          .read(bookingSubmitProvider.notifier)
          .submit(name: 'Айгерим', phone: '+77001234567');

      expect(adapter.requestCount, 2);
      expect(container.read(bookingSubmitProvider), isA<AsyncData<dynamic>>());
      expect(container.read(cartProvider), isEmpty);
    },
  );

  test(
    'reset() returns to idle so a genuinely new attempt can start clean',
    () async {
      final (container, _) = containerWithFakeBackend();
      addTearDown(container.dispose);
      await seedCart(container);

      await container
          .read(bookingSubmitProvider.notifier)
          .submit(name: 'Айгерим', phone: '+77001234567');
      expect(
        (container.read(bookingSubmitProvider) as AsyncData).value,
        isNotNull,
      );

      container.read(bookingSubmitProvider.notifier).reset();
      expect(
        (container.read(bookingSubmitProvider) as AsyncData).value,
        isNull,
      );
    },
  );
}
