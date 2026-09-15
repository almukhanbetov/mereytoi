import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/models/cart_item.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/state/cart_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

Listing _flatListing({int id = 1, int price = 100000}) => Listing(
  id: id,
  categoryId: 1,
  category: null,
  nameRu: 'Ведущий',
  nameKz: 'Ведущий',
  descriptionRu: '',
  descriptionKz: '',
  city: 'Алматы',
  phone: '',
  price: price,
  minGuests: 0,
  maxGuests: 0,
  rating: 4.5,
  emoji: '',
  colorFrom: '',
  colorTo: '',
  imageUrls: const [],
  isActive: true,
);

Listing _perPersonListing({int id = 2, int price = 5000}) => Listing(
  id: id,
  categoryId: 1,
  category: null,
  nameRu: 'Банкетный зал',
  nameKz: 'Банкетный зал',
  descriptionRu: '',
  descriptionKz: '',
  city: 'Алматы',
  phone: '',
  price: price,
  minGuests: 50,
  maxGuests: 300,
  rating: 4.9,
  emoji: '',
  colorFrom: '',
  colorTo: '',
  imageUrls: const [],
  isActive: true,
);

/// A restaurant variant cart item — same shape
/// `CartItem.fromRestaurantSelection` builds, constructed directly here so
/// each test can vary just the hall/menu/guests it cares about.
CartItem _restaurantItem({
  int listingId = 42,
  int? hallId,
  int? menuId,
  int guests = 100,
  int estimatedTotal = 2500000,
}) {
  return CartItem(
    listingId: listingId,
    name: 'Sultan Palace · Меню $menuId',
    category: 'Рестораны',
    image: null,
    unitPrice: 25000,
    guests: guests,
    totalPrice: estimatedTotal,
    hallId: hallId,
    hallName: hallId != null ? 'Hall $hallId' : null,
    menuId: menuId,
    menuName: 'Меню $menuId',
    menuPricePerGuest: 25000,
    estimatedTotal: estimatedTotal,
  );
}

void main() {
  // shared_preferences' mock channel needs a real TestWidgetsFlutterBinding
  // (plain `test()` blocks don't get one automatically the way
  // `testWidgets()` does) — without this, every SharedPreferences call
  // below silently no-ops instead of hitting the in-memory mock store.
  TestWidgetsFlutterBinding.ensureInitialized();

  // CartNotifier persists to shared_preferences on every mutation — the
  // real plugin's own test-mode mock, reset before each test so no cart
  // saved by one test leaks into the next.
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('CartItem.fromListing: flat-priced listing ignores guests entirely', () {
    final item = CartItem.fromListing(
      _flatListing(price: 250000),
      name: 'Ведущий',
      categoryLabel: 'Ведущие',
    );
    expect(item.guests, 0);
    expect(item.totalPrice, 250000);
    expect(item.hallId, isNull);
    expect(item.menuId, isNull);
  });

  test(
    'CartItem.fromListing: per-person listing multiplies guests × price',
    () {
      final item = CartItem.fromListing(
        _perPersonListing(price: 5000),
        name: 'Банкетный зал',
        categoryLabel: 'Рестораны',
        guests: 80,
      );
      expect(item.guests, 80);
      expect(item.totalPrice, 400000); // 80 * 5000
    },
  );

  test('cartTotalProvider sums totalPrice across all items', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container
        .read(cartProvider.notifier)
        .addItem(
          CartItem.fromListing(
            _flatListing(id: 1, price: 100000),
            name: 'A',
            categoryLabel: 'X',
          ),
        );
    container
        .read(cartProvider.notifier)
        .addItem(
          CartItem.fromListing(
            _perPersonListing(id: 2, price: 5000),
            name: 'B',
            categoryLabel: 'Y',
            guests: 50,
          ),
        );

    expect(container.read(cartTotalProvider), 100000 + 5000 * 50);
    expect(container.read(cartCountProvider), 2);
  });

  test(
    'two ordinary services (different listingId) stay two separate items',
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(cartProvider.notifier);

      notifier.addItem(
        CartItem.fromListing(
          _flatListing(id: 1),
          name: 'A',
          categoryLabel: 'X',
        ),
      );
      notifier.addItem(
        CartItem.fromListing(
          _flatListing(id: 2),
          name: 'B',
          categoryLabel: 'X',
        ),
      );

      expect(container.read(cartProvider), hasLength(2));
    },
  );

  test(
    "addItem for an already-present listingId replaces it rather than duplicating (matches the site's cart, no generic quantity field)",
    () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(cartProvider.notifier);

      notifier.addItem(
        CartItem.fromListing(
          _perPersonListing(id: 2, price: 5000),
          name: 'B',
          categoryLabel: 'Y',
          guests: 50,
        ),
      );
      notifier.addItem(
        CartItem.fromListing(
          _perPersonListing(id: 2, price: 5000),
          name: 'B',
          categoryLabel: 'Y',
          guests: 120,
        ),
      );

      expect(container.read(cartProvider).length, 1);
      expect(container.read(cartProvider).single.guests, 120);
      expect(container.read(cartTotalProvider), 5000 * 120);
    },
  );

  test('removeItem drops only the matching key', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(cartProvider.notifier);

    final a = CartItem.fromListing(
      _flatListing(id: 1),
      name: 'A',
      categoryLabel: 'X',
    );
    final b = CartItem.fromListing(
      _flatListing(id: 2),
      name: 'B',
      categoryLabel: 'X',
    );
    notifier.addItem(a);
    notifier.addItem(b);
    notifier.removeItem(a.key);

    expect(container.read(cartProvider).map((i) => i.listingId), [2]);
  });

  test('clear empties the cart', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(cartProvider.notifier);

    notifier.addItem(
      CartItem.fromListing(_flatListing(), name: 'A', categoryLabel: 'X'),
    );
    notifier.clear();

    expect(container.read(cartProvider), isEmpty);
    expect(container.read(cartTotalProvider), 0);
  });

  group('restaurant cart variants — key is (listingId, hallId, menuId)', () {
    test(
      'the same restaurant listing with two different hall/menu combinations produces 2 items, not 1',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(cartProvider.notifier);

        notifier.addItem(_restaurantItem(hallId: 1, menuId: 1));
        notifier.addItem(_restaurantItem(hallId: 1, menuId: 2));

        expect(container.read(cartProvider), hasLength(2));
        expect(container.read(cartCountProvider), 2);
      },
    );

    test(
      'adding the exact same listingId/hallId/menuId again updates the existing item instead of duplicating it',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(cartProvider.notifier);

        notifier.addItem(
          _restaurantItem(
            hallId: 1,
            menuId: 1,
            guests: 100,
            estimatedTotal: 2500000,
          ),
        );
        notifier.addItem(
          _restaurantItem(
            hallId: 1,
            menuId: 1,
            guests: 150,
            estimatedTotal: 3750000,
          ),
        );

        expect(container.read(cartProvider), hasLength(1));
        expect(container.read(cartProvider).single.guests, 150);
        expect(container.read(cartProvider).single.totalPrice, 3750000);
      },
    );

    test(
      'removing one hall/menu variant leaves the other variant of the same listing untouched',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(cartProvider.notifier);

        final variant1 = _restaurantItem(hallId: 1, menuId: 1);
        final variant2 = _restaurantItem(hallId: 1, menuId: 2);
        notifier.addItem(variant1);
        notifier.addItem(variant2);

        notifier.removeItem(variant1.key);

        expect(container.read(cartProvider), hasLength(1));
        expect(container.read(cartProvider).single.menuId, 2);
      },
    );

    test(
      'an ordinary service (listingId=10, hallId=null, menuId=null) and a restaurant variant of a different listing coexist',
      () {
        final container = ProviderContainer();
        addTearDown(container.dispose);
        final notifier = container.read(cartProvider.notifier);

        notifier.addItem(
          CartItem.fromListing(
            _flatListing(id: 10),
            name: 'Ведущий',
            categoryLabel: 'X',
          ),
        );
        notifier.addItem(_restaurantItem(listingId: 42, hallId: 1, menuId: 2));

        expect(container.read(cartProvider), hasLength(2));
        expect(container.read(cartCountProvider), 2);
      },
    );

    test('containsKey distinguishes variants of the same listing', () {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      final notifier = container.read(cartProvider.notifier);

      notifier.addItem(_restaurantItem(hallId: 1, menuId: 1));

      expect(
        notifier.containsKey((listingId: 42, hallId: 1, menuId: 1)),
        isTrue,
      );
      expect(
        notifier.containsKey((listingId: 42, hallId: 1, menuId: 2)),
        isFalse,
      );
    });
  });

  group('shared_preferences persistence', () {
    test(
      'addItem persists the cart, and a fresh CartNotifier restores it',
      () async {
        final firstContainer = ProviderContainer();
        final firstNotifier = firstContainer.read(cartProvider.notifier);
        firstNotifier.addItem(
          _restaurantItem(hallId: 1, menuId: 2, guests: 90),
        );
        // Deterministic instead of a guessed delay: wait for the exact
        // write this addItem call started to actually reach storage.
        await firstNotifier.debugPersisted;
        firstContainer.dispose();

        final secondContainer = ProviderContainer();
        addTearDown(secondContainer.dispose);
        // Same reasoning for the restore side — wait for the notifier's own
        // initial hydration attempt to finish, not a fixed delay.
        await secondContainer.read(cartProvider.notifier).ready;

        final restored = secondContainer.read(cartProvider);
        expect(restored, hasLength(1));
        expect(restored.single.hallId, 1);
        expect(restored.single.menuId, 2);
        expect(restored.single.guests, 90);
      },
    );
  });
}
