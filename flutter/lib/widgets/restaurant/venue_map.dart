import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';

import '../../core/theme/app_theme.dart';
import '../../models/listing.dart';
import '../../state/locale_provider.dart';

/// What the embedded map shows for a venue: its own saved coordinates and
/// one marker there. `null` without a valid point ([isValidCoordinate]) —
/// no map is ever drawn around a guessed point (the city, 0,0, or the
/// user's position).
@immutable
class VenueMapData {
  const VenueMapData({required this.target, required this.marker});

  static const zoom = 15.0;
  static const markerId = MarkerId('venue');

  final LatLng target;
  final Marker marker;

  static VenueMapData? fromPoint({
    required double? latitude,
    required double? longitude,
    required String venueName,
    String? address,
  }) {
    if (!isValidCoordinate(latitude, longitude)) return null;
    final target = LatLng(latitude!, longitude!);
    final snippet = address ?? '';
    return VenueMapData(
      target: target,
      marker: Marker(
        markerId: markerId,
        position: target,
        infoWindow: InfoWindow(
          title: venueName,
          snippet: snippet.isEmpty ? null : snippet,
        ),
      ),
    );
  }

  static VenueMapData? of(Listing listing, AppLocale locale) => fromPoint(
    latitude: listing.latitude,
    longitude: listing.longitude,
    venueName: listing.name(locale),
    address: listing.address,
  );
}

/// The embedded Google Map of one venue (google_maps_flutter; key from
/// android/local.properties / ios/Flutter/Secrets.xcconfig). Sits inside
/// scrolling lists and swipeable tabs, so it claims only pinch and
/// horizontal drag ([gestureRecognizers]): a vertical swipe that starts on
/// the map still scrolls the page, a sideways/diagonal drag moves the map
/// instead of switching the tab. Renders nothing for an invalid
/// point — never an empty map.
class VenueMap extends StatefulWidget {
  const VenueMap({
    super.key,
    required this.latitude,
    required this.longitude,
    required this.venueName,
    this.address,
    this.height = 240,
  });

  final double? latitude;
  final double? longitude;
  final String venueName;
  final String? address;
  final double height;

  VenueMapData? get data => VenueMapData.fromPoint(
    latitude: latitude,
    longitude: longitude,
    venueName: venueName,
    address: address,
  );

  /// Widget tests can't host the native map view; they swap it for a
  /// placeholder and assert on [VenueMapData] and on the gestures the map
  /// would claim instead.
  @visibleForTesting
  static Widget Function(
    VenueMapData data,
    Set<Factory<OneSequenceGestureRecognizer>> gestures,
  )?
  debugMapBuilder;

  /// The gestures the map claims: pinch and horizontal/diagonal drag, no
  /// vertical drag (that keeps scrolling the page).
  ///
  /// The horizontal drag uses the device's touch slop ([settings], from
  /// MediaQuery) — the same slop the enclosing TabBarView's PageView uses.
  /// With Flutter's default 18px slop the map lost every horizontal drag
  /// to the tab swipe (which claims it at the device's smaller slop, ~8dp
  /// on Android) in release builds; at equal slop both reach it on the
  /// same pointer event and the map, deeper in the tree and so asked
  /// first, wins.
  ///
  /// Pinch keeps Flutter's default slop on purpose: given the device slop
  /// too, its lower pan slop made the map win vertical drags as well on a
  /// real device (POCO X3 Pro, release), so the page stopped scrolling
  /// from the map.
  static Set<Factory<OneSequenceGestureRecognizer>> gestureRecognizers(
    DeviceGestureSettings? settings,
  ) => {
    Factory<ScaleGestureRecognizer>(ScaleGestureRecognizer.new),
    Factory<HorizontalDragGestureRecognizer>(
      () => HorizontalDragGestureRecognizer()..gestureSettings = settings,
    ),
  };

  @override
  State<VenueMap> createState() => _VenueMapState();
}

class _VenueMapState extends State<VenueMap> {
  GoogleMapController? _controller;

  DeviceGestureSettings? _gestureSettings;
  Set<Factory<OneSequenceGestureRecognizer>> _gestures =
      VenueMap.gestureRecognizers(null);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final settings = MediaQuery.maybeGestureSettingsOf(context);
    if (settings != _gestureSettings) {
      _gestureSettings = settings;
      _gestures = VenueMap.gestureRecognizers(settings);
    }
  }

  @override
  void didUpdateWidget(VenueMap old) {
    super.didUpdateWidget(old);
    // Another venue in the same slot: move the camera to it (the marker
    // follows from build).
    final target = widget.data?.target;
    if (target != null && old.data?.target != target) {
      _controller?.animateCamera(CameraUpdate.newLatLng(target));
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    if (data == null) return const SizedBox.shrink();
    final builder = VenueMap.debugMapBuilder;
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: Container(
        height: widget.height,
        color: context.mereytoiColors.surfaceSoft,
        child: builder != null
            ? builder(data, _gestures)
            : GoogleMap(
                initialCameraPosition: CameraPosition(
                  target: data.target,
                  zoom: VenueMapData.zoom,
                ),
                markers: {data.marker},
                gestureRecognizers: _gestures,
                onMapCreated: (c) => _controller = c,
                myLocationEnabled: false,
                myLocationButtonEnabled: false,
                mapToolbarEnabled: false,
                zoomControlsEnabled: false,
                compassEnabled: false,
              ),
      ),
    );
  }
}
