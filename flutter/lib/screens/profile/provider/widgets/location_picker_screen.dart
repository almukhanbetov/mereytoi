import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:google_maps_flutter_android/google_maps_flutter_android.dart';
import 'package:google_maps_flutter_platform_interface/google_maps_flutter_platform_interface.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../models/listing.dart';
import '../../../../state/locale_provider.dart';

/// Where the map opens with no saved point: Almaty, the same default as the
/// web's address form. It is only a view: no point is set until one is picked.
const _defaultCenter = LatLng(43.238949, 76.889709);

/// How many one-second tries a map gets to show the right place, with its
/// tiles, before it's reported as unavailable, and how long it gets to answer
/// each question: a map that failed to load may never answer at all. Slow tiles
/// can still arrive later, so the check goes on, more rarely, while the screen
/// is open.
const _kMapCheckTries = 8;
const _kMapAnswerTimeout = Duration(seconds: 2);
const _kMapRecheckInterval = Duration(seconds: 3);

/// Google treats a tap on a place or transit icon as a tap on that object and
/// reports no map tap, so a tap on the venue's own icon would do nothing. Street
/// names stay for orientation.
const _kNoTappableIconsStyle = '''
[
  {"featureType": "poi", "elementType": "labels", "stylers": [{"visibility": "off"}]},
  {"featureType": "transit", "elementType": "labels", "stylers": [{"visibility": "off"}]}
]
''';

/// A saved or picked point as the provider forms show it.
String mapPointLabel(AppLocale locale, double latitude, double longitude) =>
    '${t(locale, ru: 'Точка', kz: 'Нүкте', en: 'Point')}: '
    '${latitude.toStringAsFixed(5)}, ${longitude.toStringAsFixed(5)}';

/// Full-screen map to set a venue's point: tap the map, then confirm. Returns the picked point, or null when closed without one,
/// so an unavailable map can never change a saved point.
Future<LatLng?> showLocationPicker(
  BuildContext context, {
  required AppLocale locale,
  double? latitude,
  double? longitude,
}) {
  return Navigator.of(context).push<LatLng>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => LocationPickerScreen(
        locale: locale,
        initial: isValidCoordinate(latitude, longitude)
            ? LatLng(latitude!, longitude!)
            : null,
      ),
    ),
  );
}

/// Whether a map snapshot (RGBA) shows a drawn map rather than one flat color,
/// which is what a map without tiles looks like. The middle (the marker) and
/// the lower corners (Google's logo, the zoom buttons) don't count: they're
/// drawn on a blank map too.
bool mapSnapshotLooksRendered(Uint8List rgba, int width, int height) {
  const grid = 48;
  final counts = <int, int>{};
  var total = 0;
  for (var gy = 0; gy < grid; gy++) {
    for (var gx = 0; gx < grid; gx++) {
      final fx = (gx + 0.5) / grid, fy = (gy + 0.5) / grid;
      final dx = fx - 0.5, dy = fy - 0.5;
      if (dx * dx + dy * dy < 0.18 * 0.18) continue;
      if (fy > 0.65 && (fx < 0.3 || fx > 0.8)) continue;
      final i = ((fy * height).floor() * width + (fx * width).floor()) * 4;
      if (i + 2 >= rgba.length) continue;
      final color =
          (rgba[i] >> 4) << 8 | (rgba[i + 1] >> 4) << 4 | rgba[i + 2] >> 4;
      counts[color] = (counts[color] ?? 0) + 1;
      total++;
    }
  }
  if (total == 0) return false;
  final dominant = counts.values.reduce((a, b) => a > b ? a : b);
  return dominant / total < 0.985;
}

/// The chosen point's marker. It can't be dragged: only a tap's coordinates
/// were verified, and a drag ended about 160 m from the finger.
@visibleForTesting
Marker locationPickerMarker(LatLng point) => Marker(
  markerId: const MarkerId('picked'),
  position: point,
  draggable: false,
);

/// What the screen asks the map to know it can be trusted.
abstract class LocationMapProbe {
  Future<bool> showsPoint(LatLng point);
  Future<bool> rendered();
  Future<void> moveTo(LatLng point, double zoom);
}

class _GoogleMapProbe implements LocationMapProbe {
  _GoogleMapProbe(this._controller);

  final GoogleMapController _controller;

  /// A snapshot still unanswered when the caller gave up. A failed map may
  /// never answer: ask again only once this one is done.
  Future<bool>? _pendingSnapshot;

  @override
  Future<bool> showsPoint(LatLng point) async =>
      (await _controller.getVisibleRegion()).contains(point);

  @override
  Future<bool> rendered() => _pendingSnapshot ??= _snapshot().whenComplete(
    () => _pendingSnapshot = null,
  );

  Future<bool> _snapshot() async {
    final png = await _controller.takeSnapshot();
    if (png == null) return false;
    final codec = await ui.instantiateImageCodec(png);
    final frame = await codec.getNextFrame();
    final image = frame.image;
    final data = await image.toByteData();
    final (width, height) = (image.width, image.height);
    image.dispose();
    codec.dispose();
    return data != null &&
        mapSnapshotLooksRendered(data.buffer.asUint8List(), width, height);
  }

  @override
  Future<void> moveTo(LatLng point, double zoom) =>
      _controller.moveCamera(CameraUpdate.newLatLngZoom(point, zoom));
}

enum _MapStatus { checking, ready, unavailable }

class LocationPickerScreen extends StatefulWidget {
  const LocationPickerScreen({super.key, required this.locale, this.initial});

  final AppLocale locale;
  final LatLng? initial;

  /// Widget tests can't host the native map view; they swap it for a
  /// placeholder that reports a picked point, and [debugProbe] for what the
  /// map would answer. Without a probe the placeholder counts as working.
  @visibleForTesting
  static Widget Function(LatLng? point, ValueChanged<LatLng> onPick)?
  debugMapBuilder;
  @visibleForTesting
  static LocationMapProbe? debugProbe;

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  late LatLng? _point = widget.initial;
  _MapStatus _status = _MapStatus.checking;
  LocationMapProbe? _probe;
  bool _checking = false;
  bool _moved = false;
  int _tries = 0;
  Timer? _recheck;
  // Once the camera was where it was asked to be: the user may then pan away.
  bool _cameraOk = false;

  LatLng get _target => widget.initial ?? _defaultCenter;
  double get _zoom => widget.initial == null ? 11 : 15;

  /// This screen's map skips the texture path (Hybrid Composition): on that
  /// path Flutter 3.44 aborted the app right after creating the map, with
  /// "Image is already closed" in ImageReaderSurfaceProducer. Set only while
  /// this screen is open, as the venue map's gestures rely on the default.
  void _useHybridComposition(bool on) {
    final platform = GoogleMapsFlutterPlatform.instance;
    if (platform is GoogleMapsFlutterAndroid) {
      platform.useAndroidViewSurface = on;
    }
  }

  @override
  void initState() {
    super.initState();
    _useHybridComposition(true);
    if (LocationPickerScreen.debugMapBuilder != null) {
      _probe = LocationPickerScreen.debugProbe;
      if (_probe == null) {
        _status = _MapStatus.ready;
      } else {
        unawaited(_check());
      }
    }
  }

  void _onMapCreated(GoogleMapController controller) {
    _probe = _GoogleMapProbe(controller);
    unawaited(_check());
  }

  /// Marks the map usable only once it shows the requested place and real
  /// tiles. Until then a tap can't be trusted: a map that failed to load can
  /// report coordinates of somewhere else entirely.
  Future<void> _check() async {
    final probe = _probe;
    if (probe == null || !mounted || _checking) return;
    _checking = true;
    var rendered = false;
    try {
      if (!_cameraOk) {
        _cameraOk = await _answer(probe.showsPoint(_target));
        if (!_cameraOk && !_moved) {
          _moved = true;
          await probe
              .moveTo(_target, _zoom)
              .timeout(_kMapAnswerTimeout, onTimeout: () {});
        }
      }
      rendered = _cameraOk && await _answer(probe.rendered());
    } catch (_) {
      rendered = false;
    } finally {
      _checking = false;
    }
    if (!mounted) return;
    _tries++;
    if (rendered || _tries == _kMapCheckTries) {
      debugPrint('[map] camera=$_cameraOk rendered=$rendered');
    }
    if (rendered) {
      setState(() => _status = _MapStatus.ready);
      return;
    }
    if (_tries >= _kMapCheckTries && _status != _MapStatus.unavailable) {
      setState(() => _status = _MapStatus.unavailable);
    }
    _recheck?.cancel();
    _recheck = Timer(
      _tries < _kMapCheckTries
          ? const Duration(seconds: 1)
          : _kMapRecheckInterval,
      () => unawaited(_check()),
    );
  }

  Future<bool> _answer(Future<bool> question) =>
      question.timeout(_kMapAnswerTimeout, onTimeout: () => false);

  void _retry() {
    _tries = 0;
    _recheck?.cancel();
    setState(() => _status = _MapStatus.checking);
    unawaited(_check());
  }

  @override
  void dispose() {
    _recheck?.cancel();
    _useHybridComposition(false);
    super.dispose();
  }

  /// A tap's coordinates are checked against what the map shows: on a broken
  /// map they were seen pointing elsewhere (at 57.8, 37.6) while the camera
  /// was correctly over the requested place.
  Future<void> _pick(LatLng point) async {
    if (_status != _MapStatus.ready) return;
    final probe = _probe;
    final onMap = probe == null || await _answer(probe.showsPoint(point));
    if (!mounted || _status != _MapStatus.ready) return;
    if (!onMap) {
      debugPrint('[map] picked point is outside the visible map');
      setState(() => _status = _MapStatus.unavailable);
      return;
    }
    setState(() => _point = point);
  }

  @override
  Widget build(BuildContext context) {
    final locale = widget.locale;
    final colors = context.mereytoiColors;
    final textTheme = Theme.of(context).textTheme;
    final point = _point;
    final ready = _status == _MapStatus.ready;
    final debugMap = LocationPickerScreen.debugMapBuilder;
    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: colors.backgroundPrimary,
        title: Text(
          t(
            locale,
            ru: 'Точка на карте',
            kz: 'Картадағы нүкте',
            en: 'Point on the map',
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: debugMap != null
                ? debugMap(point, (p) => unawaited(_pick(p)))
                : GoogleMap(
                    initialCameraPosition: CameraPosition(
                      target: _target,
                      zoom: _zoom,
                    ),
                    style: _kNoTappableIconsStyle,
                    onMapCreated: _onMapCreated,
                    onTap: (point) => unawaited(_pick(point)),
                    myLocationButtonEnabled: false,
                    markers: {if (point != null) locationPickerMarker(point)},
                  ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              color: colors.backgroundPrimary,
              border: Border(top: BorderSide(color: colors.border)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (_status == _MapStatus.unavailable) ...[
                      Text(
                        t(
                          locale,
                          ru: 'Карта недоступна, поэтому точку сейчас выбрать нельзя. Сохранённая точка не изменится.',
                          kz: 'Карта қолжетімсіз, сондықтан қазір нүктені таңдау мүмкін емес. Сақталған нүкте өзгермейді.',
                          en: 'The map is unavailable, so a point can\'t be chosen right now. The saved point won\'t change.',
                        ),
                        key: const ValueKey('location-picker-unavailable'),
                        textAlign: TextAlign.center,
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.error,
                        ),
                      ),
                      TextButton(
                        key: const ValueKey('location-picker-retry'),
                        style: TextButton.styleFrom(
                          minimumSize: const Size(48, 48),
                        ),
                        onPressed: _retry,
                        child: Text(
                          t(
                            locale,
                            ru: 'Повторить',
                            kz: 'Қайталау',
                            en: 'Retry',
                          ),
                        ),
                      ),
                    ] else
                      Text(
                        ready
                            ? t(
                                locale,
                                ru: 'Нажмите на карту, чтобы выбрать точку',
                                kz: 'Нүктені таңдау үшін картаны басыңыз',
                                en: 'Tap the map to choose the point',
                              )
                            : t(
                                locale,
                                ru: 'Проверяем карту…',
                                kz: 'Картаны тексеріп жатырмыз…',
                                en: 'Checking the map…',
                              ),
                        key: const ValueKey('location-picker-hint'),
                        textAlign: TextAlign.center,
                        style: textTheme.bodySmall?.copyWith(
                          color: colors.textSecondary,
                        ),
                      ),
                    const SizedBox(height: AppSpacing.sm),
                    SizedBox(
                      height: 52,
                      child: ElevatedButton(
                        key: const ValueKey('location-picker-confirm'),
                        onPressed: !ready || point == null
                            ? null
                            : () => Navigator.of(context).pop(point),
                        child: Text(
                          t(
                            locale,
                            ru: 'Подтвердить точку',
                            kz: 'Нүктені растау',
                            en: 'Confirm the point',
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
