import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/screens/service_detail/service_detail_screen.dart';
import 'package:mereytoi_app/services/video_thumbnail_service.dart';
import 'package:mereytoi_app/state/listings_provider.dart';
import 'package:mereytoi_app/state/locale_provider.dart';
import 'package:mereytoi_app/widgets/video_preview_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A valid 1×1 PNG — stands in for a decoded video frame.
final _png = Uint8List.fromList(const [
  0x89,
  0x50,
  0x4E,
  0x47,
  0x0D,
  0x0A,
  0x1A,
  0x0A,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x48,
  0x44,
  0x52,
  0x00,
  0x00,
  0x00,
  0x01,
  0x00,
  0x00,
  0x00,
  0x01,
  0x08,
  0x06,
  0x00,
  0x00,
  0x00,
  0x1F,
  0x15,
  0xC4,
  0x89,
  0x00,
  0x00,
  0x00,
  0x0D,
  0x49,
  0x44,
  0x41,
  0x54,
  0x78,
  0x9C,
  0x63,
  0xF8,
  0xCF,
  0xC0,
  0xF0,
  0x1F,
  0x00,
  0x05,
  0x00,
  0x01,
  0xFF,
  0x89,
  0x99,
  0x3D,
  0x1D,
  0x00,
  0x00,
  0x00,
  0x00,
  0x49,
  0x45,
  0x4E,
  0x44,
  0xAE,
  0x42,
  0x60,
  0x82,
]);

/// Records every URL asked for, answering with [result].
class _FakeLoader {
  _FakeLoader(this.result);
  final Uint8List? result;
  final calls = <String>[];
  Future<Uint8List?> call(String url) async {
    calls.add(url);
    return result;
  }
}

void _setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

Future<void> _pumpCards(
  WidgetTester tester, {
  required _FakeLoader loader,
  List<String> urls = const ['https://mereytoi.kz/uploads/a.mp4'],
  AppLocale locale = AppLocale.ru,
  ThemeData? theme,
  Size size = const Size(390, 844),
  double topSpacer = 0,
  ValueChanged<String>? onOpen,
}) async {
  _setSize(tester, size);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        videoThumbnailCacheProvider.overrideWithValue(
          VideoThumbnailCache(loader.call),
        ),
      ],
      child: MaterialApp(
        theme: theme ?? AppTheme.dark,
        home: Scaffold(
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              SizedBox(height: topSpacer),
              for (final url in urls) ...[
                VideoPreviewCard(
                  videoUrl: url,
                  locale: locale,
                  onOpen: () => onOpen?.call(url),
                ),
                const SizedBox(height: 12),
              ],
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('shows the real frame, a play button, no old link text', (
    tester,
  ) async {
    final loader = _FakeLoader(_png);
    await _pumpCards(tester, loader: loader);
    expect(find.byKey(const ValueKey('video-preview-frame')), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.text('Смотреть видео'), findsNothing);
    expect(find.byIcon(Icons.open_in_new_rounded), findsNothing);
    expect(find.byKey(const ValueKey('video-preview-fallback')), findsNothing);
  });

  testWidgets('card is 16:9', (tester) async {
    await _pumpCards(tester, loader: _FakeLoader(_png));
    final size = tester.getSize(
      find.byKey(const ValueKey('video-preview-card')),
    );
    expect(size.width / size.height, closeTo(16 / 9, 0.01));
  });

  testWidgets('no frame (offline/timeout): dark fallback labelled «Видео»', (
    tester,
  ) async {
    await _pumpCards(tester, loader: _FakeLoader(null));
    expect(find.byKey(const ValueKey('video-preview-frame')), findsNothing);
    expect(
      find.byKey(const ValueKey('video-preview-fallback')),
      findsOneWidget,
    );
    expect(find.text('Видео'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });

  for (final (locale, label) in [
    (AppLocale.ru, 'Видео'),
    (AppLocale.kz, 'Видео'),
    (AppLocale.en, 'Video'),
  ]) {
    testWidgets('fallback label in ${locale.name}', (tester) async {
      await _pumpCards(tester, loader: _FakeLoader(null), locale: locale);
      expect(find.text(label), findsOneWidget);
    });
  }

  testWidgets('tap opens the same URL via the caller and nothing auto-plays', (
    tester,
  ) async {
    final opened = <String>[];
    await _pumpCards(tester, loader: _FakeLoader(_png), onOpen: opened.add);
    expect(opened, isEmpty); // building/loading the preview opens nothing
    await tester.tap(find.byKey(const ValueKey('video-preview-card')));
    expect(opened, ['https://mereytoi.kz/uploads/a.mp4']);
  });

  testWidgets('frame is requested only once the card nears the viewport', (
    tester,
  ) async {
    final loader = _FakeLoader(_png);
    await _pumpCards(tester, loader: loader, topSpacer: 3000);
    expect(loader.calls, isEmpty);

    await tester.drag(find.byType(ListView), const Offset(0, -2800));
    await tester.pumpAndSettle();
    expect(loader.calls, ['https://mereytoi.kz/uploads/a.mp4']);
  });

  testWidgets('two videos: two cards of equal width, one request per URL', (
    tester,
  ) async {
    final loader = _FakeLoader(_png);
    await _pumpCards(
      tester,
      loader: loader,
      urls: const ['https://x/1.mp4', 'https://x/2.mp4'],
    );
    final cards = find.byKey(const ValueKey('video-preview-card'));
    expect(cards, findsNWidgets(2));
    expect(
      tester.getSize(cards.at(0)).width,
      tester.getSize(cards.at(1)).width,
    );
    expect(loader.calls, ['https://x/1.mp4', 'https://x/2.mp4']);
  });

  test('cache: same URL loads once; a failure is retried later', () async {
    var n = 0;
    final cache = VideoThumbnailCache((url) async => ++n == 1 ? null : _png);
    expect(await cache.load('u'), isNull); // first attempt fails
    expect(await cache.load('u'), isNotNull); // retried
    expect(await cache.load('u'), isNotNull); // now cached
    expect(n, 2);
  });

  for (final name in ['dark', 'light']) {
    testWidgets('320dp, $name theme: frame + fallback cards, no overflow', (
      tester,
    ) async {
      await _pumpCards(
        tester,
        loader: _FakeLoader(_png),
        urls: const ['https://x/1.mp4', 'https://x/2.mp4'],
        theme: name == 'dark' ? AppTheme.dark : AppTheme.light,
        size: const Size(320, 640),
      );
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('ServiceDetailScreen: video section uses preview cards', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    _setSize(tester, const Size(390, 2400));
    final listing = Listing(
      id: 60,
      categoryId: 2,
      nameRu: 'Ведущий',
      nameKz: 'Жүргізуші',
      descriptionRu: '',
      descriptionKz: '',
      city: 'Алматы',
      phone: '',
      price: 600000,
      minGuests: 0,
      maxGuests: 0,
      rating: 0,
      emoji: '',
      colorFrom: '',
      colorTo: '',
      imageUrls: const [],
      videoUrls: const ['/uploads/1.mp4', '/uploads/2.mp4'],
      isActive: true,
    );
    final loader = _FakeLoader(_png);
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          listingDetailProvider(
            60,
          ).overrideWith((ref) => Future.value(listing)),
          videoThumbnailCacheProvider.overrideWithValue(
            VideoThumbnailCache(loader.call),
          ),
        ],
        child: MaterialApp(
          theme: AppTheme.dark,
          home: const ServiceDetailScreen(listingId: 60),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(VideoPreviewCard), findsNWidgets(2));
    expect(find.text('Смотреть видео'), findsNothing);
    expect(
      loader.calls.every((u) => u.endsWith('.mp4') && u.startsWith('http')),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}
