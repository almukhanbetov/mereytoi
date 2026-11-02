import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/widgets/restaurant/venue_map.dart';

// Release-build defect: a horizontal drag on the embedded map in «Мой той»
// switched the event tab (Услуги → Обзор) instead of moving the map. The
// tab PageView claims a drag at the device's touch slop (~8dp on Android),
// the map's recognizers used Flutter's default 18px, so with the small
// per-event steps of a release build the tab swipe always won. These
// tests replay that: an Android-like 8px slop and drags in 6px steps
// (under the 8 → 18px gap, as in a release build).

const _deviceSlop = DeviceGestureSettings(touchSlop: 8);

/// Stands in for the native map: claims exactly the gestures the real
/// map would (the set VenueMap hands to GoogleMap) and records drags.
Widget _fakeMap(
  Set<Factory<OneSequenceGestureRecognizer>> gestures,
  void Function(double dx) onDrag,
) {
  final factories = <Type, GestureRecognizerFactory>{};
  for (final f in gestures) {
    if (f.type == ScaleGestureRecognizer) {
      factories[ScaleGestureRecognizer] =
          GestureRecognizerFactoryWithHandlers<ScaleGestureRecognizer>(
            () => f.constructor() as ScaleGestureRecognizer,
            (r) => r.onStart ??= (_) {},
          );
    } else if (f.type == HorizontalDragGestureRecognizer) {
      factories[HorizontalDragGestureRecognizer] =
          GestureRecognizerFactoryWithHandlers<HorizontalDragGestureRecognizer>(
            () => f.constructor() as HorizontalDragGestureRecognizer,
            (r) => r.onUpdate = (d) => onDrag(d.delta.dx),
          );
    } else {
      fail('unexpected map gesture ${f.type}');
    }
  }
  return RawGestureDetector(
    gestures: factories,
    child: const ColoredBox(
      key: ValueKey('map-surface'),
      color: Colors.green,
      child: SizedBox.expand(),
    ),
  );
}

Widget _eventTabs(ThemeData theme) => MaterialApp(
  theme: theme,
  builder: (context, child) => MediaQuery(
    data: MediaQuery.of(context).copyWith(gestureSettings: _deviceSlop),
    child: child!,
  ),
  home: DefaultTabController(
    length: 2,
    child: Scaffold(
      appBar: AppBar(
        bottom: const TabBar(
          tabs: [
            Tab(text: 'Услуги'),
            Tab(text: 'Обзор'),
          ],
        ),
      ),
      body: TabBarView(
        children: [
          ListView(
            children: const [
              SizedBox(
                key: ValueKey('outside-map'),
                height: 120,
                child: Text('Panorama'),
              ),
              VenueMap(
                latitude: 43.2721509,
                longitude: 76.9976112,
                venueName: 'Panorama',
                address: 'улица Иштван Коныра, Алматы',
              ),
              SizedBox(height: 1500),
            ],
          ),
          const Center(child: Text('overview page')),
        ],
      ),
    ),
  ),
);

Future<void> _drag(WidgetTester tester, Offset from, Offset step) async {
  final gesture = await tester.startGesture(from);
  for (var i = 0; i < 40; i++) {
    await gesture.moveBy(step);
    await tester.pump(const Duration(milliseconds: 8));
  }
  await gesture.up();
  await tester.pumpAndSettle();
}

int _tabIndex(WidgetTester tester) =>
    DefaultTabController.of(tester.element(find.byType(TabBarView))).index;

void main() {
  late double mapDx;
  Set<Factory<OneSequenceGestureRecognizer>>? claimed;

  setUp(() {
    mapDx = 0;
    claimed = null;
    VenueMap.debugMapBuilder = (data, gestures) {
      claimed = gestures;
      return _fakeMap(gestures, (dx) => mapDx += dx);
    };
  });
  tearDown(() => VenueMap.debugMapBuilder = null);

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(400, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_eventTabs(AppTheme.light));
    await tester.pumpAndSettle();
  }

  Offset mapCenter(WidgetTester tester) =>
      tester.getCenter(find.byKey(const ValueKey('map-surface')));

  test('the map claims pinch and horizontal drag only; the drag at the '
      'device slop, pinch at the default slop', () {
    final gestures = VenueMap.gestureRecognizers(_deviceSlop);
    expect(gestures.map((f) => f.type).toSet(), {
      ScaleGestureRecognizer,
      HorizontalDragGestureRecognizer,
    });
    final byType = {for (final f in gestures) f.type: f.constructor()};
    expect(
      byType[HorizontalDragGestureRecognizer]!.gestureSettings,
      _deviceSlop,
    );
    // Device slop on pinch made the map steal vertical page scrolls on a
    // real device — keep it on Flutter's default.
    expect(byType[ScaleGestureRecognizer]!.gestureSettings, isNull);
  });

  testWidgets('VenueMap uses the device touch slop from MediaQuery', (
    tester,
  ) async {
    await pump(tester);
    expect(claimed, isNotNull);
    final drag = claimed!.firstWhere(
      (f) => f.type == HorizontalDragGestureRecognizer,
    );
    expect(drag.constructor().gestureSettings?.touchSlop, 8);
  });

  testWidgets('a horizontal drag on the map moves the map, not the tab', (
    tester,
  ) async {
    await pump(tester);
    for (final dir in [const Offset(-6, 0), const Offset(6, 0)]) {
      mapDx = 0;
      await _drag(tester, mapCenter(tester), dir);
      expect(_tabIndex(tester), 0, reason: 'drag $dir switched the tab');
      expect(mapDx.abs(), greaterThan(150), reason: 'map did not move');
    }
    // A diagonal drag that is mostly sideways goes to the map too.
    mapDx = 0;
    await _drag(tester, mapCenter(tester), const Offset(-6, 2));
    expect(_tabIndex(tester), 0);
    expect(mapDx, lessThan(-150));
    expect(find.text('overview page'), findsNothing);
  });

  testWidgets('regression: the old 18px map slop loses the drag to the tab', (
    tester,
  ) async {
    VenueMap.debugMapBuilder = (data, _) =>
        _fakeMap(VenueMap.gestureRecognizers(null), (dx) => mapDx += dx);
    await pump(tester);
    await _drag(tester, mapCenter(tester), const Offset(-6, 0));
    expect(_tabIndex(tester), 1);
    expect(mapDx, 0);
  });

  testWidgets('a swipe outside the map still switches the tab', (tester) async {
    await pump(tester);
    await _drag(
      tester,
      tester.getCenter(find.byKey(const ValueKey('outside-map'))),
      const Offset(-8, 0),
    );
    expect(_tabIndex(tester), 1);
    expect(find.text('overview page'), findsOneWidget);
    expect(mapDx, 0);
  });

  testWidgets('a vertical drag on the map scrolls the page', (tester) async {
    await pump(tester);
    final before = tester.getTopLeft(find.byType(VenueMap)).dy;
    await _drag(tester, mapCenter(tester), const Offset(0, -3));
    final after = tester.getTopLeft(find.byType(VenueMap)).dy;
    expect(after, lessThan(before - 50));
    expect(_tabIndex(tester), 0);
    expect(mapDx, 0);
  });

  testWidgets('tapping a tab still switches it; the map comes back', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Обзор'));
    await tester.pumpAndSettle();
    expect(_tabIndex(tester), 1);
    await tester.tap(find.text('Услуги'));
    await tester.pumpAndSettle();
    expect(_tabIndex(tester), 0);
    expect(find.byType(VenueMap), findsOneWidget);
    expect(find.byKey(const ValueKey('map-surface')), findsOneWidget);
  });
}
