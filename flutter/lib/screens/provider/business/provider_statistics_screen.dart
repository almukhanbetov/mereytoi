import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../state/locale_provider.dart';

/// «Статистика» placeholder — there's no statistics API yet, so no
/// numbers are shown at all (never made-up ones).
class ProviderStatisticsScreen extends ConsumerWidget {
  const ProviderStatisticsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final colors = context.mereytoiColors;
    final textTheme = Theme.of(context).textTheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(
          t(locale, ru: 'Статистика', kz: 'Статистика', en: 'Statistics'),
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(
                  color: colors.goldPrimary.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.insights_rounded,
                  size: 34,
                  color: colors.goldPrimary,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(
                t(
                  locale,
                  ru: 'Статистика появится здесь',
                  kz: 'Статистика осында пайда болады',
                  en: 'Statistics will appear here',
                ),
                textAlign: TextAlign.center,
                style: textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: AppSpacing.xxs),
              Text(
                t(
                  locale,
                  ru: 'Мы покажем просмотры и заявки по вашим услугам',
                  kz: 'Қызметтеріңіздің қаралымдары мен өтінімдерін көрсетеміз',
                  en: 'We\'ll show views and requests for your services',
                ),
                textAlign: TextAlign.center,
                style: textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
