import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/deeplink/deep_link_service.dart';
import 'core/theme/app_theme.dart';
import 'screens/splash/splash_screen.dart';
import 'state/theme_provider.dart';

/// The app's single root [Navigator] key — [DeepLinkService] pushes
/// [ClaimScreen] onto it directly from outside the widget tree (an OS deep
/// link can arrive at any time, not just while some particular screen is
/// mounted), the same reason a global key rather than a per-screen
/// `Navigator.of(context)` is needed here.
final rootNavigatorKey = GlobalKey<NavigatorState>();

class MereytoiApp extends ConsumerStatefulWidget {
  const MereytoiApp({super.key});

  @override
  ConsumerState<MereytoiApp> createState() => _MereytoiAppState();
}

class _MereytoiAppState extends ConsumerState<MereytoiApp> {
  late final DeepLinkService _deepLinkService;

  @override
  void initState() {
    super.initState();
    _deepLinkService = DeepLinkService(rootNavigatorKey);
    _deepLinkService.start();
  }

  @override
  void dispose() {
    _deepLinkService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final themeMode = ref.watch(themeModeProvider);
    // Этап 10Б-А — one global status-bar/Android-nav-bar style, resolved
    // from the same two inputs `MaterialApp` itself uses to pick
    // light/dark (`themeMode` + the OS brightness for "Как в системе"),
    // computed independently rather than read back out of
    // `MaterialApp`'s own internal `Theme` via its `builder` — that
    // depends on exactly when `MaterialApp`'s internal Theme-resolution
    // widget rebuilds relative to `builder`, which isn't guaranteed to
    // happen on every `themeMode` change. Computing it here instead means
    // this `AnnotatedRegion` rebuilds on the same, plain
    // `ConsumerState.build` trigger as everything else in this widget.
    final brightness = resolveBrightness(
      themeMode,
      MediaQuery.platformBrightnessOf(context),
    );
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: AppSystemUiOverlay.forBrightness(brightness),
      child: MaterialApp(
        navigatorKey: rootNavigatorKey,
        title: 'MEREYTOI',
        debugShowCheckedModeBanner: false,
        theme: AppTheme.light,
        darkTheme: AppTheme.dark,
        themeMode: themeMode,
        home: const SplashScreen(),
      ),
    );
  }
}

/// `ThemeMode.system` resolves against the OS's own current brightness;
/// `.light`/`.dark` are an explicit user choice and ignore the platform
/// entirely — the exact same rule `MaterialApp` itself applies internally
/// to pick between `theme`/`darkTheme`, kept here as one small pure
/// function so [MereytoiApp]'s own `AnnotatedRegion` and any test can both
/// call it instead of duplicating a switch statement.
Brightness resolveBrightness(ThemeMode mode, Brightness platformBrightness) {
  return switch (mode) {
    ThemeMode.light => Brightness.light,
    ThemeMode.dark => Brightness.dark,
    ThemeMode.system => platformBrightness,
  };
}
