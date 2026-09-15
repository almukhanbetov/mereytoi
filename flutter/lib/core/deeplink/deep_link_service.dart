import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/material.dart';

import '../../domain/deeplink/claim_deep_link.dart';
import '../../screens/claim/claim_screen.dart';

/// The OS-level half of claim deep-link handling: listens for whatever the
/// platform actually hands Flutter (an Android App Links intent, an iOS
/// Universal Link, or the app being cold-started from one) and pushes
/// [ClaimScreen] when it's `https://mereytoi.kz/claim/:token` — parsing
/// itself lives in `claim_deep_link.dart` so it stays testable without a
/// platform channel.
///
/// This alone is only the app-side half of real interception — see the
/// Stage 6 report for exactly which web-domain-hosted verification files
/// (`assetlinks.json`/`apple-app-site-association`) are still needed
/// before Android/iOS will route a real `mereytoi.kz` link here instead of
/// (or in addition to) a browser.
class DeepLinkService {
  DeepLinkService(this._navigatorKey);

  final GlobalKey<NavigatorState> _navigatorKey;
  final AppLinks _appLinks = AppLinks();
  StreamSubscription<Uri>? _subscription;

  Future<void> start() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) _handle(initial);
    } catch (_) {
      // No initial link, or the platform channel isn't available (e.g.
      // running under `flutter test`) — nothing to recover from, just
      // don't crash startup over it.
    }
    _subscription = _appLinks.uriLinkStream.listen(_handle, onError: (_) {});
  }

  void _handle(Uri uri) {
    final token = parseClaimToken(uri);
    if (token == null) return;
    final navigator = _navigatorKey.currentState;
    if (navigator == null) return;
    navigator.push(
      MaterialPageRoute(builder: (_) => ClaimScreen(token: token)),
    );
  }

  void dispose() {
    _subscription?.cancel();
  }
}
