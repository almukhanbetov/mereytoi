import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../core/utils/format.dart';
import '../../domain/event/event_status.dart';
import '../../models/event.dart';
import '../../models/event_request.dart';
import '../../state/event_actions.dart';
import '../../state/event_providers.dart';
import '../../state/locale_provider.dart';
import '../app_card.dart';
import '../app_error_view.dart';
import '../app_loader.dart';

/// Брифа section 8 — event identity, request status, and the live summary
/// numbers, with pull-to-refresh. The submit/cancel "заявка" CTA lives
/// here too (brief section 16) rather than as a 7th tab.
class OverviewTab extends ConsumerWidget {
  const OverviewTab({
    super.key,
    required this.eventId,
    required this.event,
    required this.myRole,
  });

  final int eventId;
  final Event event;
  final String myRole;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final summaryAsync = ref.watch(eventSummaryProvider(eventId));
    final requestAsync = ref.watch(eventRequestProvider(eventId));

    return RefreshIndicator(
      color: context.mereytoiColors.goldPrimary,
      backgroundColor: context.mereytoiColors.surfaceElevated,
      onRefresh: () async {
        ref.invalidate(eventDetailProvider(eventId));
        await Future.wait([
          ref.refresh(eventSummaryProvider(eventId).future),
          ref.refresh(eventRequestProvider(eventId).future),
        ]);
      },
      child: ListView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      eventTypeEmoji(event.type),
                      style: const TextStyle(fontSize: 22),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text(
                        event.title,
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                Wrap(
                  spacing: AppSpacing.xxs,
                  runSpacing: AppSpacing.xxs,
                  children: [
                    _Fact(
                      icon: Icons.category_outlined,
                      text: eventTypeLabel(locale, event.type),
                    ),
                    if (event.eventDate != null)
                      _Fact(
                        icon: Icons.event_outlined,
                        text: formatMenuDate(event.eventDate!),
                      ),
                    if (event.city.isNotEmpty)
                      _Fact(icon: Icons.place_outlined, text: event.city),
                    if (event.guests > 0)
                      _Fact(
                        icon: Icons.groups_outlined,
                        text:
                            '${event.guests} ${t(locale, ru: "гостей", kz: "қонақ")}',
                      ),
                  ],
                ),
                if (event.comment.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    event.comment,
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
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
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t(locale, ru: 'Сводка', kz: 'Жиынтық'),
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  _StatRow(
                    label: t(locale, ru: 'Бюджет', kz: 'Бюджет'),
                    value: formatPrice(summary.budgetTotal),
                  ),
                  _StatRow(
                    label: t(locale, ru: 'Потрачено', kz: 'Жұмсалды'),
                    value: formatPrice(summary.spent),
                  ),
                  _StatRow(
                    label: t(locale, ru: 'Остаток', kz: 'Қалды'),
                    value: formatPrice(summary.remaining),
                    valueColor: summary.remaining < 0
                        ? context.mereytoiColors.error
                        : context.mereytoiColors.goldSoft,
                  ),
                  const Padding(
                    padding: EdgeInsets.symmetric(vertical: AppSpacing.xxs),
                    child: Divider(height: 1),
                  ),
                  _StatRow(
                    label: t(
                      locale,
                      ru: 'Категорий выбрано',
                      kz: 'Санат таңдалды',
                    ),
                    value:
                        '${summary.categoriesCovered} / ${summary.categoriesTotal}',
                  ),
                  _StatRow(
                    label: t(locale, ru: 'В шортлисте', kz: 'Шортлисте'),
                    value: '${summary.shortlistedCount}',
                  ),
                  _StatRow(
                    label: t(
                      locale,
                      ru: 'Выбрано услуг',
                      kz: 'Таңдалған қызметтер',
                    ),
                    value: '${summary.selectedCount}',
                  ),
                  _StatRow(
                    label: t(locale, ru: 'Участников', kz: 'Қатысушылар'),
                    value: '${summary.membersCount}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.sm),
          requestAsync.when(
            loading: () => const SizedBox.shrink(),
            error: (err, _) => AppErrorView(
              message: apiErrorMessage(locale, err),
              locale: locale,
              onRetry: () => ref.invalidate(eventRequestProvider(eventId)),
            ),
            data: (data) => _RequestCard(
              eventId: eventId,
              request: data.$1,
              myRole: myRole,
              locale: locale,
            ),
          ),
        ],
      ),
    );
  }
}

class _RequestCard extends ConsumerStatefulWidget {
  const _RequestCard({
    required this.eventId,
    required this.request,
    required this.myRole,
    required this.locale,
  });

  final int eventId;
  final EventRequest request;
  final String myRole;
  final AppLocale locale;

  @override
  ConsumerState<_RequestCard> createState() => _RequestCardState();
}

class _RequestCardState extends ConsumerState<_RequestCard> {
  bool _busy = false;
  String? _error;

  Future<void> _submit() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final (_, alreadySubmitted) = await ref
          .read(eventActionsProvider)
          .submitRequest(widget.eventId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              alreadySubmitted
                  ? t(
                      widget.locale,
                      ru: 'Заявка уже отправлена',
                      kz: 'Өтінім жіберілген',
                    )
                  : t(
                      widget.locale,
                      ru: 'Заявка отправлена',
                      kz: 'Өтінім жіберілді',
                    ),
            ),
          ),
        );
      }
    } catch (err) {
      if (mounted) setState(() => _error = apiErrorMessage(widget.locale, err));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _cancel() async {
    final confirmed = await showModalBottomSheet<bool>(
      context: context,
      builder: (sheetContext) => _ConfirmSheet(
        locale: widget.locale,
        title: t(
          widget.locale,
          ru: 'Отменить заявку?',
          kz: 'Өтінімді болдырмау керек пе?',
        ),
      ),
    );
    if (confirmed != true) return;

    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(eventActionsProvider).cancelRequest(widget.eventId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              t(
                widget.locale,
                ru: 'Заявка отменена',
                kz: 'Өтінім болдырылмады',
              ),
            ),
          ),
        );
      }
    } catch (err) {
      if (mounted) setState(() => _error = apiErrorMessage(widget.locale, err));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final request = widget.request;
    final status = request.status;
    final isOwner = widget.myRole == eventRoleOwner;
    final editable = requestIsEditable(status);
    final cancellable = requestIsCancellable(status) && status != requestDraft;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                t(
                  widget.locale,
                  ru: 'Заявка в MEREYTOI',
                  kz: 'MEREYTOI-ге өтінім',
                ),
                style: Theme.of(context).textTheme.titleMedium,
              ),
              _StatusChip(text: requestStatusLabel(widget.locale, status)),
            ],
          ),
          if (request.managerComment.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${t(widget.locale, ru: "Комментарий менеджера", kz: "Менеджер пікірі")}: ${request.managerComment}',
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              _error!,
              style: TextStyle(
                color: context.mereytoiColors.error,
                fontSize: 13,
              ),
            ),
          ],
          if (isOwner && (editable || cancellable)) ...[
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                if (editable)
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _busy ? null : _submit,
                      child: Text(
                        t(
                          widget.locale,
                          ru: 'Отправить заявку',
                          kz: 'Өтінім жіберу',
                        ),
                      ),
                    ),
                  ),
                if (editable && cancellable)
                  const SizedBox(width: AppSpacing.xs),
                if (cancellable)
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _busy ? null : _cancel,
                      child: Text(
                        t(
                          widget.locale,
                          ru: 'Отменить заявку',
                          kz: 'Өтінімді болдырмау',
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _ConfirmSheet extends StatelessWidget {
  const _ConfirmSheet({required this.locale, required this.title});

  final AppLocale locale;
  final String title;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: Text(
                t(locale, ru: 'Да, продолжить', kz: 'Иә, жалғастыру'),
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: Text(t(locale, ru: 'Отмена', kz: 'Бас тарту')),
            ),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: AppSpacing.xxs,
      ),
      decoration: BoxDecoration(
        color: context.mereytoiColors.surfaceSoft,
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: context.mereytoiColors.textSecondary),
          const SizedBox(width: AppSpacing.xxs),
          Text(
            text,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: context.mereytoiColors.textPrimary,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: Theme.of(context).textTheme.bodyMedium),
          Text(
            value,
            style: TextStyle(
              color: valueColor ?? context.mereytoiColors.textPrimary,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusChip extends StatelessWidget {
  const _StatusChip({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: context.mereytoiColors.goldPrimary.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Text(
        text,
        style: TextStyle(
          color: context.mereytoiColors.goldSoft,
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }
}
