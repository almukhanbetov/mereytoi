import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../state/locale_provider.dart';
import 'app_icon_badge.dart';

/// The "Не удалось загрузить данные / Повторить" pattern every API screen
/// uses on failure — a friendly message plus a retry action, never a raw
/// exception on screen.
class AppErrorView extends StatelessWidget {
  const AppErrorView({
    super.key,
    required this.message,
    required this.locale,
    required this.onRetry,
  });

  final String message;
  final AppLocale locale;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppIconBadge(
              icon: Icons.cloud_off_rounded,
              size: 56,
              iconSize: 26,
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              message,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton(
              onPressed: onRetry,
              child: Text(
                t(locale, ru: 'Повторить', kz: 'Қайталау', en: 'Retry'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
