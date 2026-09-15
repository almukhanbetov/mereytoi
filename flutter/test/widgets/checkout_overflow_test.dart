import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage_platform_interface/flutter_secure_storage_platform_interface.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/models/booking.dart';
import 'package:mereytoi_app/models/cart_item.dart';
import 'package:mereytoi_app/models/restaurant_selection.dart';
import 'package:mereytoi_app/screens/checkout/booking_success_screen.dart';
import 'package:mereytoi_app/screens/checkout/checkout_screen.dart';
import 'package:mereytoi_app/state/cart_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Same empty in-memory secure storage `test/widgets/auth_gate_test.dart`
/// already uses — `AuthNotifier`'s own restore-on-construct then resolves
/// to `AuthUnauthenticated` with no real platform channel/network call.
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

/// A CartItem with deliberately long RU/KZ strings — hall/menu name, a
/// pile of extras — the same "make it unrealistically long" approach
/// `test/widgets/overflow_test.dart` already uses for other screens, now
/// covering the Stage 6 Checkout/Success screens that had no widget-level
/// overflow coverage yet (only the pure domain/service tests).
final _longRestaurantItem = CartItem(
  listingId: 42,
  name:
      'Sultan Palace Almaty · Очень длинное название банкетного меню премиум класса №1',
  category: 'Рестораны и банкетные залы для больших торжеств',
  image: null,
  unitPrice: 25000,
  guests: 250,
  totalPrice: 9876543,
  hallId: 1,
  hallName: 'Большой Императорский Зал с видом на горы Заилийского Алатау',
  menuId: 2,
  menuName: 'Очень длинное название банкетного меню премиум класса №1',
  menuPricePerGuest: 25000,
  selectedExtras: const [
    SelectedExtraLine(
      title: 'Детский стол с аниматором и отдельным меню',
      price: 12000,
      unit: 'per_guest',
      amount: 3000000,
    ),
    SelectedExtraLine(
      title: 'Сервисный сбор за обслуживание банкета',
      price: 10,
      unit: 'percent',
      amount: 987654,
    ),
    SelectedExtraLine(
      title: 'Дополнительное освещение и звуковое оборудование',
      price: 150000,
      unit: 'flat',
      amount: 150000,
    ),
  ],
  estimatedTotal: 9876543,
);

Widget _wrap(Widget child, {required Size size}) {
  return MediaQuery(
    data: MediaQueryData(size: size),
    child: ProviderScope(
      child: MaterialApp(theme: AppTheme.dark, home: child),
    ),
  );
}

const _narrowSizes = [Size(320, 700), Size(360, 800)];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    FlutterSecureStoragePlatform.instance = _EmptySecureStoragePlatform();
    SharedPreferences.setMockInitialValues({});
  });

  for (final size in _narrowSizes) {
    testWidgets(
      'CheckoutScreen with a long restaurant snapshot + extras does not overflow at ${size.width.toInt()}px',
      (tester) async {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        await container.read(cartProvider.notifier).ready;
        container.read(cartProvider.notifier).addItem(_longRestaurantItem);

        await tester.pumpWidget(
          UncontrolledProviderScope(
            container: container,
            child: MediaQuery(
              data: MediaQueryData(size: size),
              child: MaterialApp(
                theme: AppTheme.dark,
                home: const CheckoutScreen(),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );
  }

  for (final size in _narrowSizes) {
    testWidgets(
      'BookingSuccessScreen (created_pending onboarding, delivered via WhatsApp) does not overflow at ${size.width.toInt()}px',
      (tester) async {
        final result = BookingCreateResult(
          booking: Booking(
            id: 1,
            publicRef: 'abc123def456',
            name: 'Айгерим Жандарбекқызы',
            phone: '+77001234567',
            message: '',
            status: 'new',
            total: 9876543,
            items: [
              BookingItem(
                listingId: 5,
                name: 'Ведущий на очень большое и длинное торжество',
                category: 'Ведущие',
                guests: 0,
                unitPrice: 250000,
                totalPrice: 250000,
              ),
              BookingItem(
                listingId: 42,
                name:
                    'Sultan Palace Almaty · Очень длинное название банкетного меню премиум класса №1',
                category: 'Рестораны',
                guests: 250,
                unitPrice: 25000,
                totalPrice: 9626543,
                hallId: 1,
                hallName: 'Большой Императорский Зал',
                menuId: 2,
                menuName:
                    'Очень длинное название банкетного меню премиум класса №1',
                menuPricePerGuest: 25000,
                selectedExtras: const [
                  BookingItemExtra(
                    title: 'Детский стол с аниматором и отдельным меню',
                    price: 12000,
                    unit: 'per_guest',
                  ),
                ],
                estimatedTotal: 9626543,
              ),
            ],
          ),
          onboarding: const BookingOnboarding(
            status: 'created_pending',
            eventId: 9,
            claimToken: 'deadbeef1234',
            deliveryStatus: 'sent',
            deliveryChannel: 'whatsapp',
          ),
        );

        await tester.pumpWidget(
          _wrap(BookingSuccessScreen(result: result), size: size),
        );
        await tester.pumpAndSettle();

        expect(tester.takeException(), isNull);
      },
    );
  }

  testWidgets(
    'BookingSuccessScreen (existing_account onboarding) does not overflow at 320px',
    (tester) async {
      final result = BookingCreateResult(
        booking: Booking(
          id: 1,
          publicRef: 'abc123',
          name: 'A',
          phone: '+7',
          message: '',
          status: 'new',
          total: 0,
          items: const [],
        ),
        onboarding: const BookingOnboarding(status: 'existing_account'),
      );
      await tester.pumpWidget(
        _wrap(BookingSuccessScreen(result: result), size: const Size(320, 700)),
      );
      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
    },
  );
}
