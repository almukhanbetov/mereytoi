import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/domain/event/event_budget.dart';
import 'package:mereytoi_app/models/event_candidate.dart';
import 'package:mereytoi_app/models/listing.dart';

Listing _listing({int price = 250000}) => Listing(
  id: 5,
  categoryId: 1,
  nameRu: 'Ведущий',
  nameKz: 'Ведущий',
  descriptionRu: '',
  descriptionKz: '',
  city: '',
  phone: '',
  price: price,
  minGuests: 0,
  maxGuests: 0,
  rating: 0,
  emoji: '',
  colorFrom: '',
  colorTo: '',
  imageUrls: const [],
  isActive: true,
);

EventCandidate _candidate({
  int? menuId,
  int? estimatedTotal,
  int? menuPricePerGuest,
  int? guests,
  Listing? listing,
}) {
  return EventCandidate(
    id: 1,
    eventId: 7,
    listingId: 5,
    listing: listing,
    menuId: menuId,
    menuPricePerGuest: menuPricePerGuest,
    guests: guests,
    estimatedTotal: estimatedTotal,
    status: 'selected',
    addedById: 3,
    createdAt: DateTime(2026),
    updatedAt: DateTime(2026),
  );
}

void main() {
  group('candidateEstimate — exact port of eventHelpers.js', () {
    test('prefers the frozen estimatedTotal when a menu is set', () {
      final candidate = _candidate(
        menuId: 2,
        estimatedTotal: 3850000,
        menuPricePerGuest: 25000,
        guests: 150,
      );
      expect(candidateEstimate(candidate, eventGuests: 100), 3850000);
    });

    test(
      'falls back to menuPricePerGuest × guests when estimatedTotal is absent',
      () {
        final candidate = _candidate(
          menuId: 2,
          menuPricePerGuest: 25000,
          guests: 150,
        );
        expect(candidateEstimate(candidate, eventGuests: 100), 25000 * 150);
      },
    );

    test(
      "falls back to the event's own guests when the candidate has none",
      () {
        final candidate = _candidate(menuId: 2, menuPricePerGuest: 25000);
        expect(candidateEstimate(candidate, eventGuests: 80), 25000 * 80);
      },
    );

    test(
      'a non-restaurant candidate (no menuId) uses the plain listing price',
      () {
        final candidate = _candidate(listing: _listing(price: 250000));
        expect(candidateEstimate(candidate, eventGuests: 100), 250000);
      },
    );

    test('missing listing and no menu falls back to 0, never throws', () {
      final candidate = _candidate();
      expect(candidateEstimate(candidate, eventGuests: 100), 0);
    });

    test(
      'an explicit 0 estimatedTotal is falsy (JS semantics) — falls through to menuPricePerGuest×guests',
      () {
        final candidate = _candidate(
          menuId: 2,
          estimatedTotal: 0,
          menuPricePerGuest: 25000,
          guests: 10,
        );
        expect(candidateEstimate(candidate, eventGuests: 100), 25000 * 10);
      },
    );
  });
}
