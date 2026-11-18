import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../models/user_report.dart';
import '../../state/locale_provider.dart';
import '../../state/report_providers.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_error_view.dart';
import '../../widgets/app_skeleton.dart';
import '../../widgets/report/report_labels.dart';

final _date = DateFormat('dd.MM.yyyy');

/// «Мои жалобы» — the user's own reports with their status. Only what,
/// why, status and dates: never who reviewed it or their notes.
class MyReportsScreen extends ConsumerWidget {
  const MyReportsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final l = ref.watch(localeProvider);
    final reports = ref.watch(myReportsProvider);
    return Scaffold(
      appBar: AppBar(
        title: Text(
          t(l, ru: 'Мои жалобы', kz: 'Менің шағымдарым', en: 'My reports'),
        ),
      ),
      body: reports.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: const [
            AppSkeleton(height: 84, borderRadius: AppRadius.lg),
            SizedBox(height: AppSpacing.sm),
            AppSkeleton(height: 84, borderRadius: AppRadius.lg),
          ],
        ),
        error: (e, _) => Center(
          child: AppErrorView(
            message: apiErrorMessage(l, e),
            error: e,
            locale: l,
            onRetry: () => ref.invalidate(myReportsProvider),
          ),
        ),
        data: (list) => RefreshIndicator(
          onRefresh: () => ref.refresh(myReportsProvider.future),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.all(AppSpacing.lg),
            children: [
              if (list.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxl),
                  child: Text(
                    t(
                      l,
                      ru:
                          'Вы ещё не отправляли жалоб. Пожаловаться можно на '
                          'карточке услуги или в профиле услугодателя.',
                      kz:
                          'Сіз әлі шағым жібермегенсіз. Шағымды қызмет '
                          'карточкасында немесе қызмет көрсетуші профилінде '
                          'жасауға болады.',
                      en:
                          "You haven't sent any reports yet. You can report a "
                          "listing or a provider's profile.",
                    ),
                    key: const ValueKey('my-reports-empty'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
              for (final r in list) _ReportRow(report: r, locale: l),
              if (list.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: AppSpacing.sm),
                  child: Text(
                    t(
                      l,
                      ru:
                          'Решение принимает администратор. Подробности '
                          'проверки не раскрываются.',
                      kz:
                          'Шешімді әкімші қабылдайды. Тексеру мәліметтері '
                          'ашылмайды.',
                      en: "An administrator decides. Review details aren't disclosed.",
                    ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReportRow extends StatelessWidget {
  const _ReportRow({required this.report, required this.locale});

  final UserReport report;
  final AppLocale locale;

  @override
  Widget build(BuildContext context) {
    final r = report;
    final l = locale;
    final c = context.mereytoiColors;
    final tone = switch (r.status) {
      'resolved' => c.success,
      'rejected' => c.textSecondary,
      'in_review' => c.warning,
      _ => c.goldPrimary,
    };
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        key: ValueKey('my-report-${r.id}'),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    r.targetTitle.isEmpty
                        ? reportTargetLabel(l, r.targetType)
                        : r.targetTitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.xs),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: tone.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                  ),
                  child: Text(
                    reportStatusLabel(l, r.status),
                    style: textTheme.labelSmall?.copyWith(
                      color: tone,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '${reportTargetLabel(l, r.targetType)} · ${reportReasonLabel(l, r.reason)}',
              style: textTheme.bodySmall,
            ),
            Text(
              [
                if (r.createdAt != null)
                  t(
                    l,
                    ru: 'Отправлена ${_date.format(r.createdAt!)}',
                    kz: 'Жіберілді ${_date.format(r.createdAt!)}',
                    en: 'Sent ${_date.format(r.createdAt!)}',
                  ),
                if (r.resolvedAt != null)
                  t(
                    l,
                    ru: 'решение ${_date.format(r.resolvedAt!)}',
                    kz: 'шешім ${_date.format(r.resolvedAt!)}',
                    en: 'decided ${_date.format(r.resolvedAt!)}',
                  ),
              ].join(' · '),
              style: textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
