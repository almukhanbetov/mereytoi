import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/error_messages.dart';
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
    this.error,
  });

  final String message;
  final AppLocale locale;
  final VoidCallback onRetry;

  /// The failure behind [message]; when given, a small diagnostic line
  /// ([errorDiagnostics]: code + error type, no personal data) is shown
  /// under it so a tester's screenshot identifies the failure.
  final Object? error;

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
            if (error != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                errorDiagnostics(error!),
                key: const ValueKey('app-error-diagnostics'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.mereytoiColors.textSecondary,
                ),
              ),
            ],
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
