import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../models/admin.dart';
import '../../state/admin_providers.dart';
import '../../state/auth_provider.dart';
import '../../widgets/app_card.dart';
import 'admin_labels.dart';
import 'admin_user_screen.dart';
import 'admin_widgets.dart';

/// One report: what, why, who reported it, the target, other reports on the
/// same target, its own history — and «Взять в работу», «Решена»,
/// «Отклонить». A decision only closes the report; a block or a hidden
/// listing is a separate action (open the person from here).
class AdminReportScreen extends ConsumerStatefulWidget {
  const AdminReportScreen({super.key, required this.reportId});

  static const title = 'Жалоба';

  final int reportId;

  @override
  ConsumerState<AdminReportScreen> createState() => _AdminReportScreenState();
}

class _AdminReportScreenState extends ConsumerState<AdminReportScreen> {
  bool _taking = false;

  void _refresh() {
    ref.invalidate(adminReportDetailProvider(widget.reportId));
    ref.invalidate(adminSummaryProvider);
  }

  Future<void> _take() async {
    if (_taking) return;
    final ok = await showAdminConfirm(
      context,
      title: 'Взять жалобу в работу?',
      message:
          'Жалоба будет закреплена за вами. Другие администраторы увидят, '
          'что она в работе.',
      confirmLabel: 'Взять в работу',
    );
    if (!ok || !mounted) return;
    setState(() => _taking = true);
    try {
      await ref.read(adminServiceProvider).takeReport(widget.reportId);
      if (!mounted) return;
      showAdminSnack(context, 'Жалоба взята в работу');
    } catch (e) {
      if (!mounted) return;
      if (!handleAdminRightsLost(ref, e)) {
        showAdminSnack(context, adminErrorText(e));
      }
    } finally {
      if (mounted) {
        setState(() => _taking = false);
        _refresh();
      }
    }
  }

  Future<void> _decide(String decision) async {
    final resolve = decision == 'resolved';
    final ok = await showAdminActionSheet(
      context,
      title: resolve ? 'Отметить жалобу решённой?' : 'Отклонить жалобу?',
      message: resolve
          ? 'Опишите, что сделано. Блокировка или скрытие, если нужны, '
                'выполняются отдельно — само решение ничего не применяет.'
          : 'Укажите, почему нарушения нет. Заявитель увидит только статус.',
      confirmLabel: resolve ? 'Жалоба решена' : 'Отклонить',
      danger: !resolve,
      reasonHint: 'Причина решения (обязательно)',
      onSubmit: (reason, _) => ref
          .read(adminServiceProvider)
          .decideReport(widget.reportId, decision, reason),
    );
    if (ok && mounted) {
      showAdminSnack(context, resolve ? 'Жалоба решена' : 'Жалоба отклонена');
    }
    if (mounted) _refresh();
  }

  @override
  Widget build(BuildContext context) {
    final detail = ref.watch(adminReportDetailProvider(widget.reportId));
    return AdminGate(
      title: AdminReportScreen.title,
      child: Scaffold(
        appBar: AppBar(
          title: Text('${AdminReportScreen.title} #${widget.reportId}'),
        ),
        body: detail.when(
          loading: () => const AdminLoadingList(count: 3),
          error: (e, _) => AdminErrorBody(error: e, onRetry: _refresh),
          data: (d) => RefreshIndicator(
            onRefresh: () =>
                ref.refresh(adminReportDetailProvider(widget.reportId).future),
            child: _body(context, d),
          ),
        ),
      ),
    );
  }

  Widget _body(BuildContext context, AdminReportDetail d) {
    final r = d.report;
    final textTheme = Theme.of(context).textTheme;
    final colors = context.mereytoiColors;
    final auth = ref.watch(authProvider);
    final myId = auth is AuthAuthenticated ? auth.user.id : 0;
    return ListView(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  AdminPill(
                    labelOf(reportStatusLabels, r.status),
                    tone: reportStatusTone(r.status),
                  ),
                  AdminPill(
                    labelOf(reportReasonLabels, r.reason),
                    tone: AdminTone.accent,
                  ),
                  AdminPill(labelOf(reportTargetLabels, r.targetType)),
                  if (r.status == 'in_review' && r.assigneeId == myId)
                    const AdminPill('У вас в работе', tone: AdminTone.warn),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                r.details.isEmpty ? 'Без описания' : r.details,
                style: textTheme.bodyMedium,
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                'Заявитель: ${r.reporter?.name ?? '#${r.reporterId}'}'
                '${(r.reporter?.email ?? '').isEmpty ? '' : ' (${r.reporter!.email})'}',
                style: textTheme.bodySmall,
              ),
              Text(
                'Создана: ${formatAdminDate(r.createdAt)}',
                style: textTheme.bodySmall,
              ),
              if (!r.isOpen) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  'Решение (${formatAdminDate(r.resolvedAt)}): ${r.resolution}',
                  style: textTheme.bodyMedium,
                ),
              ],
            ],
          ),
        ),
        const AdminSectionTitle('На что жалоба'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                r.target.exists
                    ? r.target.title
                    : '${labelOf(reportTargetLabels, r.targetType)} удалён(а)',
                style: textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              Text(
                '${labelOf(reportTargetLabels, r.targetType)} #${r.targetId}',
                style: textTheme.bodySmall,
              ),
              ..._targetFacts(r, textTheme),
            ],
          ),
        ),
        if (r.targetUser != null)
          AdminRowCard(
            key: const ValueKey('admin-report-target-user'),
            leading: const Icon(Icons.person_outline_rounded),
            title: r.targetUser!.name,
            subtitle: 'Профиль, карточки, предупреждение и блокировка',
            onTap: () async {
              await Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AdminUserScreen(userId: r.targetUser!.id),
                ),
              );
              if (mounted) _refresh();
            },
          ),
        if (r.isOpen) ...[
          const AdminSectionTitle('Решение'),
          if (r.status == 'new')
            OutlinedButton.icon(
              key: const ValueKey('admin-report-take'),
              onPressed: _taking ? null : _take,
              icon: _taking
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.assignment_ind_outlined, size: 18),
              label: const Text('Взять в работу'),
            ),
          const SizedBox(height: AppSpacing.xs),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('admin-report-resolve'),
                  onPressed: () => _decide('resolved'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.success,
                    side: BorderSide(color: colors.success),
                  ),
                  child: const Text('Решена'),
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: OutlinedButton(
                  key: const ValueKey('admin-report-reject'),
                  onPressed: () => _decide('rejected'),
                  child: const Text('Отклонить'),
                ),
              ),
            ],
          ),
        ],
        if (d.related.isNotEmpty) ...[
          AdminSectionTitle(
            'Другие жалобы на этот объект (${d.related.length})',
          ),
          for (final x in d.related)
            AdminRowCard(
              title: '${labelOf(reportReasonLabels, x.reason)} · #${x.id}',
              subtitle: formatAdminDate(x.createdAt),
              pills: [
                AdminPill(
                  labelOf(reportStatusLabels, x.status),
                  tone: reportStatusTone(x.status),
                ),
              ],
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => AdminReportScreen(reportId: x.id),
                ),
              ),
            ),
        ],
        const AdminSectionTitle('История'),
        if (d.history.isEmpty)
          Text('Действий ещё не было.', style: textTheme.bodySmall),
        for (final e in d.history) AdminAuditRow(event: e),
      ],
    );
  }

  List<Widget> _targetFacts(AdminReport r, TextTheme t) {
    final d = r.target.detail;
    final facts = <String>[];
    switch (r.targetType) {
      case 'listing':
        if (d['publicly_visible'] == true) {
          facts.add('Видна посетителям');
        } else if (d.isNotEmpty) {
          facts.add('Не видна посетителям');
        }
        if (d['moderation_hidden_at'] != null) {
          facts.add('Скрыта администратором: ${d['moderation_reason'] ?? ''}');
        }
        if (d['is_active'] == false) facts.add('Снята владельцем');
      case 'provider':
        if (d['status'] != null) {
          facts.add(
            'Статус профиля: ${labelOf(providerStatusLabels, '${d['status']}')}',
          );
        }
      case 'comment':
        if (d['rating'] != null) facts.add('Оценка: ${d['rating']}');
        if (d['listing_id'] != null) facts.add('Карточка #${d['listing_id']}');
        if (d['approved'] == false) facts.add('Не опубликован');
      case 'user':
        if (d['blocked'] == true) facts.add('Заблокирован');
    }
    return [for (final f in facts) Text(f, style: t.bodySmall)];
  }
}
