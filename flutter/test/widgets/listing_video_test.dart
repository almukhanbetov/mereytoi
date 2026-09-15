import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/screens/service_detail/service_detail_screen.dart';
import 'package:mereytoi_app/state/listings_provider.dart';

/// Stage 7 finding: `Listing.videoUrls` was already parsed from
/// GET /api/listings but nothing in the UI ever rendered it — a real
/// parity gap against `ServiceDetail.jsx`'s own "Видео" section. Fixed by
/// adding a "Смотреть видео" row (opens externally via `url_launcher`,
/// same as every other outbound link in this app) to the shared
/// `listingHeroSlivers`. These tests cover: the section actually appears
/// when a listing has videos, stays absent when it doesn't (no dead
/// section for the common case), and neither renders with any overflow.
Widget _wrap(Widget child) {
  return ProviderScope(
    child: MaterialApp(theme: AppTheme.dark, home: child),
  );
}

final _listingWithVideo = Listing(
  id: 42,
  categoryId: 1,
  nameRu: 'AURORA QUINTET',
  nameKz: 'AURORA QUINTET',
  descriptionRu: 'Живая музыка на торжество',
  descriptionKz: 'Той үшін тірі музыка',
  city: 'Алматы',
  phone: '+7 700 123 45 67',
  price: 250000,
  minGuests: 0,
  maxGuests: 0,
  rating: 4.8,
  emoji: '',
  colorFrom: '',
  colorTo: '',
  imageUrls: const [],
  videoUrls: const ['/uploads/demo1.mp4', '/uploads/demo2.mp4'],
  isActive: true,
);

final _listingWithoutVideo = Listing(
  id: 43,
  categoryId: 1,
  nameRu: 'Тамада',
  nameKz: 'Тамада',
  descriptionRu: '',
  descriptionKz: '',
  city: 'Алматы',
  phone: '',
  price: 150000,
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
  testWidgets(
    'a listing with video_urls shows one "Смотреть видео" row per video',
    (tester) async {
      await tester.pumpWidget(
        _wrap(
          ProviderScope(
            overrides: [
              listingDetailProvider(
                42,
              ).overrideWith((ref) => Future.value(_listingWithVideo)),
            ],
            child: const ServiceDetailScreen(listingId: 42),
          ),
        ),
      );
      await tester.pumpAndSettle();

      expect(find.text('Видео'), findsOneWidget);
      expect(find.text('Смотреть видео'), findsNWidgets(2));
      expect(tester.takeException(), isNull);
    },
  );

  testWidgets('a listing with no video_urls shows no video section at all', (
    tester,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          listingDetailProvider(
            43,
          ).overrideWith((ref) => Future.value(_listingWithoutVideo)),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const ServiceDetailScreen(listingId: 43),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Видео'), findsNothing);
    expect(find.text('Смотреть видео'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
