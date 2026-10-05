import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/screens/service_detail/service_detail_screen.dart';
import 'package:mereytoi_app/state/listings_provider.dart';
import 'package:mereytoi_app/state/locale_provider.dart';
import 'package:mereytoi_app/widgets/video_preview_card.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A valid 1×1 PNG — stands in for a poster JPEG.
const _png = <int>[
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0,
  0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00,
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
];

/// Every HTTP request in this file: a poster URL containing "missing"
/// answers 404, anything else the PNG above. Also records what was asked
/// for — so the tests can tell no MP4 is ever fetched.
final _requested = <String>[];

class _FakeHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) => _FakeHttpClient();
}

class _FakeHttpClient extends Fake implements HttpClient {
  @override
  bool autoUncompress = false;

  @override
  Future<HttpClientRequest> getUrl(Uri url) async {
    _requested.add(url.toString());
    return _FakeRequest(url);
  }
}

class _FakeRequest extends Fake implements HttpClientRequest {
  _FakeRequest(this.url);
  final Uri url;

  @override
  final HttpHeaders headers = _FakeHeaders();

  @override
  Future<HttpClientResponse> close() async =>
      _FakeResponse(url.toString().contains('missing') ? 404 : 200);
}

class _FakeHeaders extends Fake implements HttpHeaders {
  @override
  void add(String name, Object value, {bool preserveHeaderCase = false}) {}
}

class _FakeResponse extends Stream<List<int>> implements HttpClientResponse {
  _FakeResponse(this.statusCode);

  @override
  final int statusCode;

  List<int> get _body => statusCode == 200 ? _png : const [];

  @override
  int get contentLength => _body.length;

  @override
  HttpClientResponseCompressionState get compressionState =>
      HttpClientResponseCompressionState.notCompressed;

  @override
  StreamSubscription<List<int>> listen(
    void Function(List<int>)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => Stream<List<int>>.value(_body).listen(
    onData,
    onError: onError,
    onDone: onDone,
    cancelOnError: cancelOnError,
  );

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void _setSize(WidgetTester tester, Size size) {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Lets the (real, async) image load and decode finish, then rebuilds.
/// Only with the plain test theme: real time would also let AppTheme's
/// google_fonts try (and fail) to download fonts.
Future<void> _settleImages(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

Future<void> _pumpCards(
  WidgetTester tester, {
  required List<String?> posters,
  AppLocale locale = AppLocale.ru,
  ThemeData? theme,
  Size size = const Size(390, 844),
  ValueChanged<String>? onOpen,
}) async {
  _setSize(tester, size);
  await tester.pumpWidget(
    MaterialApp(
      theme: theme ?? ThemeData.dark(),
      home: Scaffold(
        body: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            for (final (i, poster) in posters.indexed) ...[
              VideoPreviewCard(
                videoUrl: 'https://mereytoi.kz/uploads/$i.mp4',
                posterUrl: poster,
                locale: locale,
                onOpen: () =>
                    onOpen?.call('https://mereytoi.kz/uploads/$i.mp4'),
              ),
              const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    ),
  );
  if (theme == null) {
    await _settleImages(tester);
  } else {
    await tester.pump();
  }
}

const _poster = 'https://mereytoi.kz/uploads/posters/0.jpg';
final _frame = find.byKey(const ValueKey('video-preview-frame'));
final _fallback = find.byKey(const ValueKey('video-preview-fallback'));

void main() {
  setUpAll(() => HttpOverrides.global = _FakeHttpOverrides());
  setUp(() {
    _requested.clear();
    imageCache.clear();
  });

  testWidgets('A: poster_url → Image.network of that URL, play button, no '
      'fallback', (tester) async {
    await _pumpCards(tester, posters: [_poster]);

    final image = tester.widget<Image>(_frame);
    expect((image.image as NetworkImage).url, _poster);
    expect(image.fit, BoxFit.cover);
    expect(find.byType(RawImage), findsOneWidget); // decoded and painted
    expect(_fallback, findsNothing);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(_requested, [_poster]); // the poster only — never the MP4
  });

  testWidgets('B: no poster_url → «Видео» fallback, no request at all', (
    tester,
  ) async {
    await _pumpCards(tester, posters: [null]);
    expect(_frame, findsNothing);
    expect(_fallback, findsOneWidget);
    expect(find.text('Видео'), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(_requested, isEmpty);
  });

  testWidgets('C: poster fails to load → the same fallback', (tester) async {
    await _pumpCards(
      tester,
      posters: ['https://mereytoi.kz/uploads/posters/missing.jpg'],
    );
    expect(_fallback, findsOneWidget);
    expect(find.text('Видео'), findsOneWidget);
    expect(find.byType(RawImage), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('card is 16:9', (tester) async {
    await _pumpCards(tester, posters: [_poster]);
    final size = tester.getSize(
      find.byKey(const ValueKey('video-preview-card')),
    );
    expect(size.width / size.height, closeTo(16 / 9, 0.01));
  });

  testWidgets('E: tap opens the video URL via the caller, nothing auto-opens', (
    tester,
  ) async {
    final opened = <String>[];
    await _pumpCards(tester, posters: [_poster], onOpen: opened.add);
    expect(opened, isEmpty);
    await tester.tap(find.byKey(const ValueKey('video-preview-card')));
    expect(opened, ['https://mereytoi.kz/uploads/0.mp4']);
  });

  testWidgets('F: several cards, each with its own poster or fallback', (
    tester,
  ) async {
    await _pumpCards(
      tester,
      posters: [_poster, null, 'https://mereytoi.kz/uploads/posters/2.jpg'],
    );
    final cards = find.byKey(const ValueKey('video-preview-card'));
    expect(cards, findsNWidgets(3));
    expect(
      tester.getSize(cards.at(0)).width,
      tester.getSize(cards.at(2)).width,
    );
    expect(_frame, findsNWidgets(2));
    expect(_fallback, findsOneWidget);
    expect(_requested, [_poster, 'https://mereytoi.kz/uploads/posters/2.jpg']);
  });

  for (final width in [320.0, 390.0]) {
    for (final name in ['dark', 'light']) {
      testWidgets('G/H: ${width.toInt()}dp, $name theme — poster, fallback and '
          'failed cards, no overflow', (tester) async {
        await _pumpCards(
          tester,
          posters: [
            _poster,
            null,
            'https://mereytoi.kz/uploads/posters/missing.jpg',
          ],
          theme: name == 'dark' ? AppTheme.dark : AppTheme.light,
          size: Size(width, 900),
        );
        expect(tester.takeException(), isNull);
        expect(_fallback, findsNWidgets(2));
      });
    }
  }

  for (final (locale, label) in [
    (AppLocale.ru, 'Видео'),
    (AppLocale.kz, 'Видео'),
    (AppLocale.en, 'Video'),
  ]) {
    testWidgets('I: fallback label in ${locale.name}', (tester) async {
      await _pumpCards(tester, posters: [null], locale: locale);
      expect(find.text(label), findsOneWidget);
    });
  }

  testWidgets('ServiceDetailScreen: videos[] → cards with resolved poster '
      'URLs; legacy video_urls only → fallback cards', (tester) async {
    SharedPreferences.setMockInitialValues({});
    _setSize(tester, const Size(390, 2400));
    Listing listing({List<ListingVideo>? videos}) => Listing(
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
      videos: videos,
    );

    Future<void> pumpDetail(Listing l) async {
      await tester.pumpWidget(
        ProviderScope(
          key: UniqueKey(),
          overrides: [
            listingDetailProvider(60).overrideWith((ref) => Future.value(l)),
          ],
          child: MaterialApp(
            theme: AppTheme.dark,
            home: const ServiceDetailScreen(listingId: 60),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpDetail(
      listing(
        videos: const [
          ListingVideo(
            url: '/uploads/1.mp4',
            posterUrl: '/uploads/posters/1.jpg',
          ),
          ListingVideo(url: '/uploads/2.mp4'),
        ],
      ),
    );
    expect(find.byType(VideoPreviewCard), findsNWidgets(2));
    final cards = tester
        .widgetList<VideoPreviewCard>(find.byType(VideoPreviewCard))
        .toList();
    expect(cards[0].videoUrl, endsWith('/uploads/1.mp4'));
    expect(cards[0].videoUrl, startsWith('http'));
    expect(cards[0].posterUrl, endsWith('/uploads/posters/1.jpg'));
    expect(cards[0].posterUrl, startsWith('http'));
    expect(cards[1].posterUrl, isNull);
    expect(_requested.where((u) => u.endsWith('.mp4')), isEmpty);
    expect(tester.takeException(), isNull);

    // D: an older backend (no "videos") still gets one card per video.
    await pumpDetail(listing());
    expect(find.byType(VideoPreviewCard), findsNWidgets(2));
    expect(
      tester
          .widgetList<VideoPreviewCard>(find.byType(VideoPreviewCard))
          .every((c) => c.posterUrl == null),
      isTrue,
    );
    expect(tester.takeException(), isNull);
  });
}
