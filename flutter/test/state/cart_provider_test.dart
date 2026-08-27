import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/models/cart_item.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/state/cart_provider.dart';

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

void main() {
  test('CartItem.fromListing: flat-priced listing ignores guests entirely', () {
    final item = CartItem.fromListing(_flatListing(price: 250000), name: 'Ведущий', categoryLabel: 'Ведущие');
    expect(item.guests, 0);
    expect(item.totalPrice, 250000);
  });

  test('CartItem.fromListing: per-person listing multiplies guests × price', () {
    final item = CartItem.fromListing(_perPersonListing(price: 5000), name: 'Банкетный зал', categoryLabel: 'Рестораны', guests: 80);
    expect(item.guests, 80);
    expect(item.totalPrice, 400000); // 80 * 5000
  });

  test('cartTotalProvider sums totalPrice across all items', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);

    container.read(cartProvider.notifier).addItem(CartItem.fromListing(_flatListing(id: 1, price: 100000), name: 'A', categoryLabel: 'X'));
    container.read(cartProvider.notifier).addItem(CartItem.fromListing(_perPersonListing(id: 2, price: 5000), name: 'B', categoryLabel: 'Y', guests: 50));

    expect(container.read(cartTotalProvider), 100000 + 5000 * 50);
    expect(container.read(cartCountProvider), 2);
  });

  test('addItem for an already-present listingId replaces it rather than duplicating (matches the site\'s cart, no generic quantity field)', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(cartProvider.notifier);

    notifier.addItem(CartItem.fromListing(_perPersonListing(id: 2, price: 5000), name: 'B', categoryLabel: 'Y', guests: 50));
    notifier.addItem(CartItem.fromListing(_perPersonListing(id: 2, price: 5000), name: 'B', categoryLabel: 'Y', guests: 120));

    expect(container.read(cartProvider).length, 1);
    expect(container.read(cartProvider).single.guests, 120);
    expect(container.read(cartTotalProvider), 5000 * 120);
  });

  test('removeItem drops only the matching listingId', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(cartProvider.notifier);

    notifier.addItem(CartItem.fromListing(_flatListing(id: 1), name: 'A', categoryLabel: 'X'));
    notifier.addItem(CartItem.fromListing(_flatListing(id: 2), name: 'B', categoryLabel: 'X'));
    notifier.removeItem(1);

    expect(container.read(cartProvider).map((i) => i.listingId), [2]);
  });

  test('clear empties the cart', () {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    final notifier = container.read(cartProvider.notifier);

    notifier.addItem(CartItem.fromListing(_flatListing(), name: 'A', categoryLabel: 'X'));
    notifier.clear();

    expect(container.read(cartProvider), isEmpty);
    expect(container.read(cartTotalProvider), 0);
  });
}
