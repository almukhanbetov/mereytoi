import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/domain/restaurant/restaurant_location.dart';
import 'package:mereytoi_app/models/listing.dart';

Listing _listing({
  String? address,
  double? latitude,
  double? longitude,
  String? placeId,
  String city = '',
}) {
  return Listing(
    id: 1,
    categoryId: 1,
    nameRu: 'Sultan Palace',
    nameKz: 'Sultan Palace',
    descriptionRu: '',
    descriptionKz: '',
    city: city,
    phone: '',
    price: 0,
    minGuests: 0,
    maxGuests: 0,
    rating: 0,
    emoji: '',
    colorFrom: '',
    colorTo: '',
    imageUrls: const [],
    isActive: true,
    address: address,
    latitude: latitude,
    longitude: longitude,
    placeId: placeId,
  );
}

void main() {
  group('restaurantDirectionsUrl — exact port of RestaurantLocation.jsx', () {
    test(
      'place_id present takes top priority, even with coordinates also set',
      () {
        final url = restaurantDirectionsUrl(
          _listing(
            address: 'пр. Абая, 10',
            latitude: 43.2,
            longitude: 76.9,
            placeId: 'ChIJtest123',
          ),
        );
        expect(url, contains('maps/dir/?api=1'));
        expect(url, contains('destination_place_id=ChIJtest123'));
        expect(
          url,
          contains('destination=${Uri.encodeComponent('пр. Абая, 10')}'),
        );
      },
    );

    test('no place_id, but coordinates are saved — uses lat,lng directly', () {
      final url = restaurantDirectionsUrl(
        _listing(
          address: 'пр. Абая, 10',
          latitude: 43.238293,
          longitude: 76.945465,
        ),
      );
      expect(
        url,
        'https://www.google.com/maps/dir/?api=1&destination=43.238293,76.945465',
      );
    });

    test(
      'no place_id, no coordinates — falls back to a search query built from the address',
      () {
        final url = restaurantDirectionsUrl(
          _listing(address: 'ул. Тестовая, 5'),
        );
        expect(url, contains('maps/search/?api=1&query='));
        expect(url, isNot(contains('maps/dir')));
      },
    );

    test('no address at all — falls back to city', () {
      final url = restaurantDirectionsUrl(_listing(city: 'Алматы'));
      expect(url, contains('query=${Uri.encodeComponent('Алматы')}'));
    });

    test(
      'nothing at all to route to — returns null, matching the component rendering nothing',
      () {
        expect(restaurantDirectionsUrl(_listing()), isNull);
      },
    );
  });
}
