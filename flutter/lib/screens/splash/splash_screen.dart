import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../root_shell.dart';

/// Brand moment before the app shell loads — a soft fade/scale-in of the
/// MEREYTOI wordmark on the same dark radial-glow background as the site's
/// Hero, then a fade transition into the tab shell. No heavy animation, no
/// blocking network call — the shell's own screens fetch their own data.
class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 700));
    _opacity = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _scale = Tween<double>(begin: 0.98, end: 1.0).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic));
    _controller.forward();

    Future.delayed(const Duration(milliseconds: 1400), () {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        PageRouteBuilder(
          transitionDuration: const Duration(milliseconds: 500),
          pageBuilder: (context, animation, _) => FadeTransition(opacity: animation, child: const RootShell()),
        ),
      );
    });
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
        decoration: const BoxDecoration(
          gradient: RadialGradient(
            center: Alignment(0, -0.3),
            radius: 1.1,
            colors: [AppColors.heroGlow, AppColors.backgroundPrimary],
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
                      children: const [
                        TextSpan(text: 'MEREY', style: TextStyle(color: AppColors.textPrimary)),
                        TextSpan(text: 'TOI', style: TextStyle(color: AppColors.goldPrimary)),
                      ],
                    ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'АГЕНТСТВО ТОРЖЕСТВ',
                    style: const TextStyle(color: AppColors.goldPrimary, fontSize: 11.5, fontWeight: FontWeight.w700, letterSpacing: 2.4),
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
