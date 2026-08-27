import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../state/locale_provider.dart';

/// The "Не удалось загрузить данные / Повторить" pattern every API screen
/// uses on failure — a friendly message plus a retry action, never a raw
/// exception on screen.
class AppErrorView extends StatelessWidget {
  const AppErrorView({super.key, required this.message, required this.locale, required this.onRetry});

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
            Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: const Icon(Icons.cloud_off_rounded, color: AppColors.textSecondary, size: 26),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(message, textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyLarge),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton(
              onPressed: onRetry,
              child: Text(t(locale, ru: 'Повторить', kz: 'Қайталау')),
            ),
          ],
        ),
      ),
    );
  }
}
