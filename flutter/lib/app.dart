import 'package:flutter/material.dart';
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
    return MaterialApp(
      navigatorKey: rootNavigatorKey,
      title: 'MEREYTOI',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      home: const SplashScreen(),
    );
  }
}
