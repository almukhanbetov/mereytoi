import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../state/app_mode_provider.dart';
import '../../state/auth_provider.dart';
import '../../state/provider_provider.dart';
import '../role_choice/role_choice_screen.dart';

/// Brand moment before the app shell loads — a soft fade/scale-in of the
/// MEREYTOI wordmark on the same dark radial-glow background as the site's
/// Hero, then a fade transition into the tab shell. No heavy animation, no
/// blocking network call — the shell's own screens fetch their own data.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scale = Tween<double>(
      begin: 0.98,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();

    _launch();
  }

  /// First launch: the role choice. Later launches: the last chosen mode —
  /// the client app, with «Мой бизнес» opened on top when that was the
  /// mode and the account still has a provider profile.
  Future<void> _launch() async {
    await Future<void>.delayed(const Duration(milliseconds: 1400));
    final modes = ref.read(appModeProvider.notifier);
    await modes.ready;
    if (!mounted) return;
    final mode = ref.read(appModeProvider);
    if (mode == null) {
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 500),
          pageBuilder: (context, animation, _) => FadeTransition(
            opacity: animation,
            child: const RoleChoiceScreen(),
          ),
        ),
      );
      return;
    }
    final business = mode == AppMode.business
        ? await _businessRouteIfProvider()
        : null;
    if (!mounted) return;
    final navigator = Navigator.of(context)..pushReplacement(clientRootRoute());
    if (business != null) navigator.push(business);
  }

  /// «Мой бизнес» when the restored session belongs to a provider. Anything
  /// else (signed out, no provider profile, a slow or failed request)
  /// opens the client app and switches the mode back to it — launch never
  /// drops someone into the onboarding uninvited.
  Future<Route<void>?> _businessRouteIfProvider() async {
    try {
      final auth = await _settledAuth().timeout(const Duration(seconds: 5));
      if (auth is AuthAuthenticated) {
        final provider = await ref
            .read(providerProfileProvider.future)
            .timeout(const Duration(seconds: 5));
        if (provider != null) return businessRoute(provider);
      }
    } catch (_) {
      // Fall through to the client app.
    }
    if (mounted) ref.read(appModeProvider.notifier).set(AppMode.client);
    return null;
  }

  /// The auth state once the stored session has been restored (or not).
  Future<AuthState> _settledAuth() {
    bool settled(AuthState s) =>
        s is AuthAuthenticated || s is AuthUnauthenticated;
    final now = ref.read(authProvider);
    if (settled(now)) return Future.value(now);
    final done = Completer<AuthState>();
    late final ProviderSubscription<AuthState> sub;
    sub = ref.listenManual<AuthState>(authProvider, (_, next) {
      if (settled(next) && !done.isCompleted) {
        done.complete(next);
        sub.close();
      }
    });
    return done.future;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.3),
            radius: 1.1,
            colors: [
              context.mereytoiColors.heroGlow,
              context.mereytoiColors.backgroundPrimary,
            ],
          ),
        ),
        child: Center(
          child: FadeTransition(
            opacity: _opacity,
            child: ScaleTransition(
              scale: _scale,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  RichText(
                    text: TextSpan(
                      style: Theme.of(context).textTheme.displayLarge,
                      children: [
                        TextSpan(
                          text: 'MEREY',
                          style: TextStyle(
                            color: context.mereytoiColors.textPrimary,
                          ),
                        ),
                        TextSpan(
                          text: 'TOI',
                          style: TextStyle(
                            color: context.mereytoiColors.goldPrimary,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'АГЕНТСТВО ТОРЖЕСТВ',
                    style: TextStyle(
                      color: context.mereytoiColors.goldPrimary,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 2.4,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
