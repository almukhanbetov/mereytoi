import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' show LatLng;
import 'package:mereytoi_app/core/theme/app_theme.dart';
import 'package:mereytoi_app/screens/profile/provider/widgets/location_picker_screen.dart';
import 'package:mereytoi_app/state/locale_provider.dart';

class _Probe implements LocationMapProbe {
  _Probe({this.shows = true, this.drawn = true, this.silent = false});

  bool shows;
  bool drawn;

  /// The map never answers about its tiles.
  bool silent;
  final moves = <LatLng>[];

  @override
  Future<bool> showsPoint(LatLng point) async => shows;
  @override
  Future<bool> rendered() =>
      silent ? Completer<bool>().future : Future.value(drawn);
  @override
  Future<void> moveTo(LatLng point, double zoom) async => moves.add(point);
}

Uint8List _image(int width, int height, int Function(int x, int y) gray) {
  final out = Uint8List(width * height * 4);
  for (var y = 0; y < height; y++) {
    for (var x = 0; x < width; x++) {
      final i = (y * width + x) * 4;
      out[i] = out[i + 1] = out[i + 2] = gray(x, y);
      out[i + 3] = 255;
    }
  }
  return out;
}

void main() {
  const saved = LatLng(43.25, 76.95);
  const tapped = LatLng(58.64, 37.62);
  LatLng? result;
  var returned = false;

  Future<void> open(
    WidgetTester tester, {
    LatLng? initial,
    required LocationMapProbe? probe,
    ThemeData? theme,
  }) async {
    result = null;
    returned = false;
    LocationPickerScreen.debugProbe = probe;
    LocationPickerScreen.debugMapBuilder = (point, onPick) => TextButton(
      key: const ValueKey('fake-map'),
      onPressed: () => onPick(tapped),
      child: Text('$point'),
    );
    addTearDown(() {
      LocationPickerScreen.debugProbe = null;
      LocationPickerScreen.debugMapBuilder = null;
    });
    await tester.pumpWidget(
      MaterialApp(
        theme: theme ?? AppTheme.light,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await Navigator.of(context).push<LatLng>(
                  MaterialPageRoute(
                    builder: (_) => LocationPickerScreen(
                      locale: AppLocale.ru,
                      initial: initial,
                    ),
                  ),
                );
                returned = true;
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
  }

  Finder confirm() => find.byKey(const ValueKey('location-picker-confirm'));
  VoidCallback? onConfirm(WidgetTester tester) =>
      tester.widget<ElevatedButton>(confirm()).onPressed;
  Finder unavailable() =>
      find.byKey(const ValueKey('location-picker-unavailable'));

  /// Runs out the map's tries.
  Future<void> timeOut(WidgetTester tester) async {
    for (var i = 0; i < 30; i++) {
      await tester.pump(const Duration(seconds: 1));
    }
  }

  group('a working map', () {
    testWidgets('no point yet: confirm waits for a tap, then returns it', (
      tester,
    ) async {
      await open(tester, probe: _Probe());
      expect(onConfirm(tester), isNull);
      await tester.tap(find.byKey(const ValueKey('fake-map')));
      await tester.pump();
      await tester.tap(confirm());
      await tester.pumpAndSettle();
      expect(result, tapped);
    });

    testWidgets('a saved point comes back exactly, with no shift', (
      tester,
    ) async {
      const precise = LatLng(43.2389498123456, 76.8897091234567);
      await open(tester, initial: precise, probe: _Probe());
      expect(find.text('$precise'), findsOneWidget);
      await tester.tap(confirm());
      await tester.pumpAndSettle();
      expect(result!.latitude, precise.latitude);
      expect(result!.longitude, precise.longitude);
    });
  });

  group('an unavailable map', () {
    testWidgets('a tap off the visible map is refused, the old point kept', (
      tester,
    ) async {
      final probe = _Probe();
      await open(tester, initial: saved, probe: probe);
      expect(onConfirm(tester), isNotNull);
      probe.shows = false; // the reported coordinates aren't on the map
      await tester.tap(find.byKey(const ValueKey('fake-map')));
      await tester.pump();
      await tester.pump();
      expect(find.text('$saved'), findsOneWidget);
      expect(unavailable(), findsOneWidget);
      expect(onConfirm(tester), isNull);
    });

    testWidgets('camera elsewhere: moved once, then tap and confirm are off', (
      tester,
    ) async {
      final probe = _Probe(shows: false);
      await open(tester, initial: saved, probe: probe);
      await timeOut(tester);
      expect(probe.moves, [saved]);
      expect(unavailable(), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('fake-map')));
      await tester.pump();
      expect(find.text('$saved'), findsOneWidget); // the tap changed nothing
      expect(onConfirm(tester), isNull);
    });

    testWidgets('camera right but no tiles: tap and confirm are off', (
      tester,
    ) async {
      await open(tester, initial: saved, probe: _Probe(drawn: false));
      await timeOut(tester);
      expect(unavailable(), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('fake-map')));
      await tester.pump();
      expect(find.text('$saved'), findsOneWidget);
      expect(onConfirm(tester), isNull);
    });

    testWidgets('slow tiles: unavailable, then ready by itself', (
      tester,
    ) async {
      final probe = _Probe(drawn: false);
      await open(tester, initial: saved, probe: probe);
      await timeOut(tester);
      expect(unavailable(), findsOneWidget);
      probe.drawn = true;
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(seconds: 1));
      }
      expect(unavailable(), findsNothing);
      expect(onConfirm(tester), isNotNull);
    });

    testWidgets('a map that never answers still ends as unavailable', (
      tester,
    ) async {
      await open(tester, initial: saved, probe: _Probe(silent: true));
      await timeOut(tester);
      expect(unavailable(), findsOneWidget);
      expect(find.text('Проверяем карту…'), findsNothing);
      expect(onConfirm(tester), isNull);
    });

    testWidgets('while still checking, a tap does nothing either', (
      tester,
    ) async {
      await open(tester, probe: _Probe(drawn: false));
      expect(find.text('Проверяем карту…'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('fake-map')));
      await tester.pump();
      expect(find.text('null'), findsOneWidget);
      await timeOut(tester);
    });

    testWidgets('closing returns nothing, so the saved point stays', (
      tester,
    ) async {
      await open(tester, initial: saved, probe: _Probe(drawn: false));
      await timeOut(tester);
      await tester.pageBack();
      await tester.pumpAndSettle();
      expect(returned, isTrue);
      expect(result, isNull);
    });

    testWidgets('Retry picks up a map that came back', (tester) async {
      final probe = _Probe(drawn: false);
      await open(tester, probe: probe);
      await timeOut(tester);
      probe.drawn = true;
      await tester.tap(find.byKey(const ValueKey('location-picker-retry')));
      await tester.pump();
      await tester.pump();
      expect(unavailable(), findsNothing);
      await tester.tap(find.byKey(const ValueKey('fake-map')));
      await tester.pump();
      expect(onConfirm(tester), isNotNull);
    });

    for (final dark in [false, true]) {
      for (final width in [320.0, 430.0]) {
        testWidgets(
          'no overflow: ${dark ? 'dark' : 'light'} · ${width.toInt()}',
          (tester) async {
            tester.view.physicalSize = Size(width, 700);
            tester.view.devicePixelRatio = 1;
            addTearDown(tester.view.reset);
            await open(
              tester,
              probe: _Probe(drawn: false),
              theme: dark ? AppTheme.dark : AppTheme.light,
            );
            await timeOut(tester);
            expect(tester.takeException(), isNull);
          },
        );
      }
    }
  });

  test('the marker can\'t be dragged', () {
    final marker = locationPickerMarker(saved);
    expect(marker.draggable, isFalse);
    expect(marker.position, saved);
  });

  testWidgets('the hint offers only tapping', (tester) async {
    await open(tester, probe: _Probe());
    expect(find.text('Нажмите на карту, чтобы выбрать точку'), findsOneWidget);
    expect(find.textContaining('перетащите'), findsNothing);
  });

  group('mapSnapshotLooksRendered', () {
    test('one flat color is a blank map', () {
      expect(
        mapSnapshotLooksRendered(_image(200, 300, (_, _) => 235), 200, 300),
        isFalse,
      );
    });

    test('a marker, logo and zoom buttons on a blank map don\'t count', () {
      final image = _image(200, 300, (x, y) {
        if ((x - 100).abs() < 20 && (y - 150).abs() < 30) return 40; // marker
        if (y > 230 && x < 50) return 90; // logo
        if (y > 220 && x > 170) return 255; // zoom buttons
        return 235;
      });
      expect(mapSnapshotLooksRendered(image, 200, 300), isFalse);
    });

    test('streets and blocks are a drawn map', () {
      final image = _image(
        200,
        300,
        (x, y) => x % 40 < 3 || y % 50 < 3 ? 255 : 200,
      );
      expect(mapSnapshotLooksRendered(image, 200, 300), isTrue);
    });
  });
}
