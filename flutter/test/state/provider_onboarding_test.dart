import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/models/city.dart';
import 'package:mereytoi_app/models/provider_profile.dart';
import 'package:mereytoi_app/state/provider_business.dart';
import 'package:mereytoi_app/state/provider_onboarding.dart';
import 'package:mereytoi_app/state/provider_provider.dart';
import 'package:mereytoi_app/state/providers.dart';

import '../helpers/provider_fake_api.dart';

const _almaty = City(
  id: 1,
  nameRu: 'Алматы',
  nameKz: 'Алматы',
  nameEn: 'Almaty',
);

void main() {
  (ProviderContainer, ProviderFakeApi, ProviderOnboardingController) setup({
    Map<String, dynamic>? existing,
  }) {
    final (client, api) = fakeProviderApi(existingProvider: existing);
    final container = ProviderContainer(
      overrides: [apiClientProvider.overrideWithValue(client)],
    );
    addTearDown(container.dispose);
    // Keep the autoDispose controller alive for the whole test.
    final sub = container.listen(providerOnboardingProvider, (_, _) {});
    addTearDown(sub.close);
    return (
      container,
      api,
      container.read(providerOnboardingProvider.notifier),
    );
  }

  void fillAll(ProviderOnboardingController c, {int photos = 2}) {
    c.selectCategory(2);
    c.setDisplayName('  Ерлан Тамада ');
    c.setDescription('Ведущий тоев');
    c.setExperience('7');
    c.setCity(_almaty);
    c.addPhotos(tempPhotos(photos));
    c.setServiceName('Проведение тоя');
    c.setServiceDescription('5 часов');
    c.setPrice('150000');
  }

  group('steps', () {
    test('cannot leave a step without its required data', () {
      final (container, _, c) = setup();
      ProviderOnboardingState s() => container.read(providerOnboardingProvider);

      expect(s().canProceed, isFalse);
      expect(c.next(), isFalse);
      c.selectCategory(3);
      expect(c.next(), isTrue);

      expect(s().step, 1);
      expect(c.next(), isFalse); // no name
      c.setDisplayName('   ');
      expect(c.next(), isFalse); // blank name
      c.setDisplayName('Dana');
      expect(c.next(), isTrue);

      expect(s().step, 2);
      expect(c.next(), isFalse); // no city
      c.setCity(_almaty);
      expect(c.next(), isTrue);

      expect(s().step, 3);
      expect(c.next(), isTrue); // photos optional

      expect(s().step, 4);
      expect(c.next(), isFalse);
      c.setServiceName('Шоу');
      expect(c.next(), isFalse); // no price
      c.setPrice('0');
      expect(c.next(), isTrue);
      expect(s().step, 5);
      expect(c.next(), isFalse); // last step
    });

    test('experience: blank is fine, otherwise a whole number 0–80', () {
      final (container, _, c) = setup();
      ProviderOnboardingState s() => container.read(providerOnboardingProvider);
      for (final (text, valid, value) in [
        ('', true, null),
        ('0', true, 0),
        ('7', true, 7),
        ('80', true, 80),
        ('81', false, 81),
        ('-1', false, -1),
        ('abc', false, null),
      ]) {
        c.setExperience(text);
        expect(s().experienceValid, valid, reason: text);
        if (valid) expect(s().experienceYears, value, reason: text);
      }
      c.selectCategory(1);
      c.next();
      c.setDisplayName('Dana');
      c.setExperience('99');
      expect(c.next(), isFalse);
    });

    test('back keeps everything entered', () {
      final (container, _, c) = setup();
      fillAll(c);
      for (var i = 0; i < 5; i++) {
        c.next();
      }
      while (c.back()) {}
      final s = container.read(providerOnboardingProvider);
      expect(s.step, 0);
      expect(s.categoryId, 2);
      expect(s.displayName.trim(), 'Ерлан Тамада');
      expect(s.city, _almaty);
      expect(s.photos, hasLength(2));
      expect(s.serviceName, 'Проведение тоя');
      expect(s.priceText, '150000');
    });

    test('photos: add (capped), remove, reorder', () {
      final (container, _, c) = setup();
      final paths = tempPhotos(12);
      c.addPhotos(paths);
      List<String> current() => [
        for (final p in container.read(providerOnboardingProvider).photos)
          p.path,
      ];
      expect(current(), paths.take(kMaxOnboardingPhotos));
      c.removePhoto(0);
      expect(current().first, paths[1]);
      c.movePhoto(2, 0); // onReorderItem semantics: final index
      expect(current().take(3), [paths[3], paths[1], paths[2]]);
    });

    test('prefill from an existing profile matches its city', () {
      final (container, _, c) = setup();
      c.prefillFrom(
        const ProviderProfile(
          id: 1,
          userId: 1,
          displayName: 'Old Name',
          city: 'Алматы ',
          description: 'Old',
          phone: '',
          whatsapp: '',
          telegram: '',
          avatarUrl: '',
          status: 'active',
          experienceYears: 4,
        ),
        cities: const [_almaty],
      );
      final s = container.read(providerOnboardingProvider);
      expect(s.displayName, 'Old Name');
      expect(s.experienceText, '4');
      expect(s.city, _almaty);
      expect(s.existingProvider, isNotNull);
    });
  });

  group('publish', () {
    test(
      'new provider: one profile, one upload, one service, in order',
      () async {
        final (container, api, c) = setup();
        fillAll(c);
        expect(await c.publish(), isTrue);

        expect(api.count('POST /api/provider'), 1);
        expect(api.count('PUT /api/provider/me'), 0);
        expect(api.count('POST /api/uploads'), 1);
        expect(api.count('POST /api/provider/me/listings'), 1);
        expect(
          api.calls.indexOf('POST /api/provider'),
          lessThan(api.calls.indexOf('POST /api/provider/me/listings')),
        );

        final profile = api.bodies['POST /api/provider']!.single! as Map;
        expect(profile['display_name'], 'Ерлан Тамада');
        expect(profile['city'], 'Алматы'); // canonical directory name
        expect(profile['experience_years'], 7);

        final listing = api.listings.single;
        expect(listing['category_id'], 2);
        expect(listing['city'], 'Алматы');
        expect(listing['name_ru'], 'Проведение тоя');
        expect(listing['name_kz'], 'Проведение тоя');
        expect(listing['price'], 150000);
        expect(listing['image_urls'], [
          '/uploads/photo0.jpg',
          '/uploads/photo1.jpg',
        ]);
        expect(
          container.read(providerOnboardingProvider).publishStatus,
          OnboardingPublishStatus.done,
        );
      },
    );

    test('existing provider is updated, never created again', () async {
      final (_, api, c) = setup(
        existing: {
          'id': 5,
          'user_id': 1,
          'display_name': 'Old',
          'city': '',
          'phone': '+7700',
          'status': 'active',
        },
      );
      c.prefillFrom(
        const ProviderProfile(
          id: 5,
          userId: 1,
          displayName: 'Old',
          city: '',
          description: '',
          phone: '+7700',
          whatsapp: '',
          telegram: '',
          avatarUrl: '',
          status: 'active',
        ),
      );
      fillAll(c);
      expect(await c.publish(), isTrue);
      expect(api.count('POST /api/provider'), 0);
      expect(api.count('PUT /api/provider/me'), 1);
      final body = api.bodies['PUT /api/provider/me']!.single! as Map;
      expect(body['phone'], '+7700'); // existing contact kept
      expect(body['experience_years'], 7);
      expect(api.listings, hasLength(1));
    });

    test('409 on create (made elsewhere) falls back to update', () async {
      final (_, api, c) = setup();
      api.conflictOnCreate = true;
      fillAll(c);
      expect(await c.publish(), isTrue);
      expect(api.count('POST /api/provider'), 1);
      // At least the lookup after the 409 (later reads are just cache
      // refreshes after the update).
      expect(api.count('GET /api/provider/me'), greaterThanOrEqualTo(1));
      expect(api.count('PUT /api/provider/me'), 1);
      expect(api.provider!['display_name'], 'Ерлан Тамада');
      expect(api.listings, hasLength(1));
    });

    test(
      'retry after a failed service create: no second provider or upload',
      () async {
        final (container, api, c) = setup();
        fillAll(c);
        api.failWith500['POST /api/provider/me/listings'] = 1;

        expect(await c.publish(), isFalse);
        expect(
          container.read(providerOnboardingProvider).publishStatus,
          OnboardingPublishStatus.failed,
        );
        expect(api.listings, isEmpty);

        expect(await c.publish(), isTrue);
        expect(api.count('POST /api/provider'), 1);
        expect(api.count('POST /api/uploads'), 1);
        expect(api.listings, hasLength(1));
      },
    );

    test('retry after a failed upload: profile not recreated', () async {
      final (_, api, c) = setup();
      fillAll(c);
      api.failWith500['POST /api/uploads'] = 1;
      expect(await c.publish(), isFalse);
      expect(await c.publish(), isTrue);
      expect(api.count('POST /api/provider'), 1);
      expect(api.count('POST /api/uploads'), 2);
      expect(api.listings, hasLength(1));
    });

    test(
      'a lost service-create response is found, not created twice',
      () async {
        final (_, api, c) = setup();
        fillAll(c);
        api.loseResponse['POST /api/provider/me/listings'] = 1;

        expect(await c.publish(), isFalse);
        expect(api.listings, hasLength(1)); // the server did create it

        expect(await c.publish(), isTrue);
        expect(api.count('GET /api/users/me/listings'), 1);
        expect(api.count('POST /api/provider/me/listings'), 1);
        expect(api.listings, hasLength(1));
      },
    );

    test('a lost profile-create response is not a second profile', () async {
      final (_, api, c) = setup();
      fillAll(c);
      api.loseResponse['POST /api/provider'] = 1;
      expect(await c.publish(), isFalse);
      expect(await c.publish(), isTrue);
      // Second POST hits 409 → GET + PUT, never a second profile.
      expect(api.count('POST /api/provider'), 2);
      expect(api.count('PUT /api/provider/me'), 1);
      expect(api.listings, hasLength(1));
    });

    test('publish refuses while data is incomplete', () async {
      final (_, api, c) = setup();
      c.selectCategory(1);
      expect(await c.publish(), isFalse);
      expect(api.calls, isEmpty);
    });
  });
  group('booking requests', () {
    final booking = {
      'id': 1,
      'public_ref': 'abc',
      'status': 'new',
      'created_at': '2026-10-18T10:15:00Z',
      'client_name': 'Клиент',
      'client_phone': '',
      'items': [
        {'listing_id': 101, 'title': 'Проведение тоя', 'total_price': 1},
      ],
      'total': 1,
    };

    test('not a provider yet: no requests, not an error', () async {
      final (container, _, _) = setup();
      expect(await container.read(providerBookingsProvider.future), isEmpty);
      expect(container.read(myBookingsCountProvider), 0);
    });

    test('a failed refetch hides the count, never shows the old one', () async {
      final (container, api, _) = setup(
        existing: {'id': 7, 'user_id': 1, 'display_name': 'X', 'city': ''},
      );
      api.bookings.add(booking);
      final sub = container.listen(myBookingsCountProvider, (_, _) {});
      addTearDown(sub.close);
      await container.read(providerBookingsProvider.future);
      expect(container.read(myBookingsCountProvider), 1);

      api.failWith500['GET /api/provider/me/bookings'] = 1;
      container.invalidate(providerBookingsProvider);
      await expectLater(
        container.read(providerBookingsProvider.future),
        throwsA(anything),
      );
      expect(container.read(myBookingsCountProvider), isNull);
    });

    test('becoming a provider refetches the requests', () async {
      final (container, api, _) = setup();
      final sub = container.listen(myBookingsCountProvider, (_, _) {});
      addTearDown(sub.close);
      await container.read(providerBookingsProvider.future);
      expect(container.read(myBookingsCountProvider), 0);

      api.bookings.add(booking);
      await container
          .read(providerActionsProvider)
          .become(displayName: 'Ерлан');
      await container.read(providerBookingsProvider.future);
      expect(container.read(myBookingsCountProvider), 1);
    });
  });
}
