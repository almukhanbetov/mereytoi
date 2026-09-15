import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/models/booking.dart';

void main() {
  group('BookingCreateResult.fromJson — 1. booking model parsing', () {
    test('parses the full booking object, including items/total/message', () {
      final json = {
        'booking': {
          'id': 42,
          'public_ref': 'abc123',
          'name': 'Айгерим',
          'phone': '+77001234567',
          'message': 'Пожалуйста, перезвоните после 18:00',
          'user_id': null,
          'event_id': null,
          'status': 'new',
          'total': 275000,
          'created_at': '2026-03-01T12:00:00Z',
          'items': [
            {
              'listing_id': 5,
              'name': 'Ведущий',
              'category': 'Ведущие',
              'guests': 0,
              'unit_price': 250000,
              'total_price': 250000,
              'hall_id': null,
              'hall_name': '',
              'menu_id': null,
              'menu_name': '',
              'menu_price_per_guest': 0,
              'selected_extras': [],
              'estimated_total': 0,
            },
            {
              'listing_id': 42,
              'name': 'Sultan Palace · Банкетное меню №1',
              'category': 'Рестораны',
              'guests': 100,
              'unit_price': 25000,
              'total_price': 25000,
              'hall_id': 1,
              'hall_name': 'Sultan Hall',
              'menu_id': 2,
              'menu_name': 'Банкетное меню №1',
              'menu_price_per_guest': 25000,
              'selected_extras': [
                {'title': 'Детский стол', 'price': 12000, 'unit': 'per_guest'},
              ],
              'estimated_total': 2512000,
            },
          ],
        },
      };

      final result = BookingCreateResult.fromJson(json);

      expect(result.booking.id, 42);
      expect(result.booking.publicRef, 'abc123');
      expect(result.booking.name, 'Айгерим');
      expect(result.booking.message, 'Пожалуйста, перезвоните после 18:00');
      expect(result.booking.total, 275000);
      expect(result.booking.status, 'new');
      expect(result.booking.userId, isNull);
      expect(result.booking.eventId, isNull);
      expect(result.booking.createdAt, DateTime.utc(2026, 3, 1, 12));
      expect(result.booking.items, hasLength(2));

      final ordinary = result.booking.items[0];
      expect(ordinary.isRestaurantVariant, isFalse);
      expect(ordinary.hallName, isNull);
      expect(ordinary.menuName, isNull);

      final restaurant = result.booking.items[1];
      expect(restaurant.isRestaurantVariant, isTrue);
      expect(restaurant.hallName, 'Sultan Hall');
      expect(restaurant.menuName, 'Банкетное меню №1');
      expect(restaurant.selectedExtras, hasLength(1));
      expect(restaurant.selectedExtras.single.title, 'Детский стол');
      expect(restaurant.estimatedTotal, 2512000);
      expect(result.onboarding, isNull);
    });

    test('a booking created from/linked to an event carries event_id', () {
      final result = BookingCreateResult.fromJson({
        'booking': {
          'id': 1,
          'public_ref': 'ref1',
          'name': 'A',
          'phone': '+7',
          'message': '',
          'event_id': 9,
          'status': 'confirmed',
          'total': 0,
          'items': [],
        },
      });
      expect(result.booking.eventId, 9);
    });
  });

  group('BookingOnboarding.fromJson — the additive booking→account pipeline', () {
    test('existing_account has no claim token', () {
      final result = BookingCreateResult.fromJson({
        'booking': {
          'id': 1,
          'public_ref': 'ref1',
          'name': 'A',
          'phone': '+7',
          'message': '',
          'status': 'new',
          'total': 0,
          'items': [],
        },
        'onboarding': {'status': 'existing_account'},
      });
      expect(result.onboarding!.status, 'existing_account');
      expect(result.onboarding!.claimToken, isNull);
    });

    test('created_pending carries a claim token and event_id', () {
      final result = BookingCreateResult.fromJson({
        'booking': {
          'id': 1,
          'public_ref': 'ref1',
          'name': 'A',
          'phone': '+7',
          'message': '',
          'status': 'new',
          'total': 0,
          'items': [],
        },
        'onboarding': {
          'status': 'created_pending',
          'event_id': 5,
          'claim_token': 'deadbeef',
          'delivery_status': 'sent',
          'delivery_channel': 'whatsapp',
        },
      });
      final onboarding = result.onboarding!;
      expect(onboarding.status, 'created_pending');
      expect(onboarding.eventId, 5);
      expect(onboarding.claimToken, 'deadbeef');
      expect(onboarding.deliveryStatus, 'sent');
      expect(onboarding.deliveryChannel, 'whatsapp');
    });

    test(
      'a delivery-disabled pipeline omits delivery_status/delivery_channel entirely',
      () {
        final result = BookingCreateResult.fromJson({
          'booking': {
            'id': 1,
            'public_ref': 'ref1',
            'name': 'A',
            'phone': '+7',
            'message': '',
            'status': 'new',
            'total': 0,
            'items': [],
          },
          'onboarding': {
            'status': 'pending_claim',
            'event_id': 5,
            'claim_token': 'deadbeef',
          },
        });
        final onboarding = result.onboarding!;
        expect(onboarding.deliveryStatus, isNull);
        expect(onboarding.deliveryChannel, isNull);
      },
    );
  });
}
