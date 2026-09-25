import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/models/listing.dart';
import 'package:mereytoi_app/screens/service_detail/service_detail_screen.dart';
import 'package:mereytoi_app/state/listings_provider.dart';
import 'package:mereytoi_app/widgets/photo_viewer_screen.dart';

/// Этап 10Б-Б1 — tapping a listing's hero photo used to do nothing; the
/// brief calls for a real full-screen viewer (swipe between photos, a
/// page counter, pinch-to-zoom, and a clear way to close).
///
/// Every wait here is a bounded `pump(duration)`, never `pumpAndSettle()`:
/// these listings carry real `imageUrls`, and `flutter_test`'s own
/// `HttpClient` override makes every such network image request fail
/// (by design — see the framework's own warning), which keeps
/// `CachedNetworkImage` retrying forever and `pumpAndSettle()` never
/// settling — the exact same reason `overflow_test.dart`'s image-bearing
/// cards use a fixed-duration `pump()` instead.
///
/// The swipe test below uses `tester.fling()`, not `tester.drag()`: a
/// `drag()` delivers its pointer events instantaneously, which doesn't
/// give competing gesture recognizers (the page's own `InteractiveViewer`
/// vs. the `PageView`) the same chance to resolve as a real, time-spread
/// touch gesture does — `fling()` (and an actual finger on glass) resolve
/// it correctly. See `photo_viewer_screen.dart`'s own file doc.
final _listingWithPhotos = Listing(
  id: 48,
  categoryId: 1,
  nameRu: 'Panorama',
  nameKz: 'Panorama',
  descriptionRu: 'Ресторан для торжеств',
  descriptionKz: 'Той үшін мейрамхана',
  city: 'Алматы',
  phone: '+7 700 123 45 67',
  price: 15000,
  minGuests: 50,
  maxGuests: 300,
  rating: 4.9,
  emoji: '',
  colorFrom: '',
  colorTo: '',
  capacity: 300,
  imageUrls: const [
    '/uploads/panorama-1.jpg',
    '/uploads/panorama-2.jpg',
    '/uploads/panorama-3.jpg',
  ],
  isActive: true,
);

Widget _wrap(Widget child) {
  return ProviderScope(
    overrides: [
      listingDetailProvider(
        48,
      ).overrideWith((ref) => Future.value(_listingWithPhotos)),
    ],
    child: MaterialApp(theme: AppTheme.dark, home: child),
  );
}

const _settle = Duration(milliseconds: 400);

void main() {
  testWidgets('tapping the hero photo opens the full-screen viewer', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const ServiceDetailScreen(listingId: 48)));
    await tester.pump(_settle);

    expect(find.byType(PhotoViewerScreen), findsNothing);

    await tester.tapAt(tester.getCenter(find.byType(PageView).first));
    await tester.pump();
    await tester.pump(_settle);

    expect(find.byType(PhotoViewerScreen), findsOneWidget);
    // The page counter reflects the 3 photos this listing has — scoped to
    // the viewer itself since the listing screen underneath (kept mounted
    // by the non-opaque route) shows its own "1 / 3" hero-gallery badge.
    expect(
      find.descendant(
        of: find.byType(PhotoViewerScreen),
        matching: find.text('1 / 3'),
      ),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets(
    'pinch-to-zoom is available on every page via InteractiveViewer',
    (tester) async {
      await tester.pumpWidget(_wrap(const ServiceDetailScreen(listingId: 48)));
      await tester.pump(_settle);

      await tester.tapAt(tester.getCenter(find.byType(PageView).first));
      await tester.pump();
      await tester.pump(_settle);

      final viewer = find.descendant(
        of: find.byType(PhotoViewerScreen),
        matching: find.byType(InteractiveViewer),
      );
      expect(viewer, findsOneWidget);
      final config = tester.widget<InteractiveViewer>(viewer);
      // `panEnabled: false` is deliberate — see the widget's own file doc —
      // so one-finger swipe stays the PageView's job; pinch (2-finger
      // scale) still works.
      expect(config.panEnabled, isFalse);
      expect(config.maxScale, greaterThan(1.0));
    },
  );

  testWidgets(
    'swiping still works even though every page also supports pinch-to-zoom',
    (tester) async {
      await tester.pumpWidget(_wrap(const ServiceDetailScreen(listingId: 48)));
      await tester.pump(_settle);

      await tester.tapAt(tester.getCenter(find.byType(PageView).first));
      await tester.pump();
      await tester.pump(_settle);

      final counterInViewer = find.descendant(
        of: find.byType(PhotoViewerScreen),
        matching: find.textContaining(' / 3'),
      );
      expect(counterInViewer, findsOneWidget);
      expect(tester.widget<Text>(counterInViewer).data, '1 / 3');

      await tester.fling(
        find.byType(PhotoViewerScreen),
        const Offset(-400, 0),
        800,
      );
      await tester.pump();
      await tester.pump(_settle);

      expect(tester.widget<Text>(counterInViewer).data, '2 / 3');
    },
  );

  testWidgets('the close button pops back to the listing screen', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(const ServiceDetailScreen(listingId: 48)));
    await tester.pump(_settle);

    await tester.tapAt(tester.getCenter(find.byType(PageView).first));
    await tester.pump();
    await tester.pump(_settle);
    expect(find.byType(PhotoViewerScreen), findsOneWidget);

    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    await tester.pump(_settle);

    expect(find.byType(PhotoViewerScreen), findsNothing);
    expect(find.byType(ServiceDetailScreen), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('opening with an empty photo list is a no-op, never throws', (
    tester,
  ) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            ctx = context;
            return const Scaffold(body: SizedBox());
          },
        ),
      ),
    );

    await PhotoViewerScreen.open(ctx, imageUrls: const []);
    await tester.pump(_settle);

    expect(find.byType(PhotoViewerScreen), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
