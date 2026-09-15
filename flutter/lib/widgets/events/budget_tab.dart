import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../core/utils/format.dart';
import '../../domain/event/event_budget.dart';
import '../../domain/event/event_status.dart';
import '../../models/event.dart';
import '../../models/event_candidate.dart';
import '../../state/event_providers.dart';
import '../../state/locale_provider.dart';
import '../app_card.dart';
import '../app_error_view.dart';
import '../app_loader.dart';

/// Brief section 11 — budget vs. what's actually shortlisted/selected.
/// `Общий бюджет`/`Выбрано`/`Остаток` come straight from
/// `GET /api/events/:id/summary` (never recomputed here); the per-candidate
/// breakdown underneath uses [candidateEstimate] on each candidate's own
/// frozen snapshot, exactly like eventHelpers.js's own Budget view — no
/// live menu/extras lookup for a restaurant candidate.
class BudgetTab extends ConsumerWidget {
  const BudgetTab({super.key, required this.eventId, required this.event});

  final int eventId;
  final Event event;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final summaryAsync = ref.watch(eventSummaryProvider(eventId));
    final candidatesAsync = ref.watch(eventCandidatesProvider(eventId));

    return RefreshIndicator(
      color: context.mereytoiColors.goldPrimary,
      backgroundColor: context.mereytoiColors.surfaceElevated,
      onRefresh: () => Future.wait([
        ref.refresh(eventSummaryProvider(eventId).future),
        ref.refresh(eventCandidatesProvider(eventId).future),
      ]),
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          summaryAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: AppLoader(compact: true),
            ),
            error: (err, _) => AppErrorView(
              message: apiErrorMessage(locale, err),
              locale: locale,
              onRetry: () => ref.invalidate(eventSummaryProvider(eventId)),
            ),
            data: (summary) => AppCard(
              color: context.mereytoiColors.surfaceElevated,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _BigRow(
                    label: t(locale, ru: 'Общий бюджет', kz: 'Жалпы бюджет'),
                    value: formatPrice(summary.budgetTotal),
                  ),
                  _BigRow(
                    label: t(locale, ru: 'Выбрано', kz: 'Таңдалды'),
                    value: formatPrice(summary.spent),
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                    child: Divider(height: 1),
                  ),
                  _BigRow(
                    label: t(locale, ru: 'Остаток', kz: 'Қалды'),
                    value: formatPrice(summary.remaining),
                    emphasize: true,
                    valueColor: summary.remaining < 0
                        ? context.mereytoiColors.error
                        : context.mereytoiColors.goldSoft,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            t(locale, ru: 'Вклад по услугам', kz: 'Қызметтер бойынша үлес'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          candidatesAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.symmetric(vertical: AppSpacing.lg),
              child: AppLoader(compact: true),
            ),
            error: (err, _) => AppErrorView(
              message: apiErrorMessage(locale, err),
              locale: locale,
              onRetry: () => ref.invalidate(eventCandidatesProvider(eventId)),
            ),
            data: (candidates) {
              final selected = candidates
                  .where((c) => c.status == candidateSelected)
                  .toList();
              if (selected.isEmpty) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
                  child: Text(
                    t(
                      locale,
                      ru: 'Пока ничего не выбрано',
                      kz: 'Әлі ештеңе таңдалмаған',
                    ),
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                );
              }
              return Column(
                children: selected
                    .map(
                      (c) => Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                        child: _CandidateBudgetRow(
                          candidate: c,
                          eventGuests: event.guests,
                          locale: locale,
                        ),
                      ),
                    )
                    .toList(),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _CandidateBudgetRow extends StatelessWidget {
  const _CandidateBudgetRow({
    required this.candidate,
    required this.eventGuests,
    required this.locale,
  });

  final EventCandidate candidate;
  final int eventGuests;
  final AppLocale locale;

  @override
  Widget build(BuildContext context) {
    final title =
        candidate.listing?.name(locale) ??
        t(locale, ru: 'Услуга', kz: 'Қызмет');
    final amount = candidateEstimate(candidate, eventGuests: eventGuests);

    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyLarge,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            formatPrice(amount),
            style: TextStyle(
              color: context.mereytoiColors.goldSoft,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _BigRow extends StatelessWidget {
  const _BigRow({
    required this.label,
    required this.value,
    this.emphasize = false,
    this.valueColor,
  });

  final String label;
  final String value;
  final bool emphasize;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyLarge),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? context.mereytoiColors.textPrimary,
              fontWeight: FontWeight.w800,
              fontSize: emphasize ? 20 : 15,
            ),
          ),
        ],
      ),
    );
  }
}
