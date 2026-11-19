import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../models/admin.dart';
import '../../state/admin_providers.dart';
import '../../widgets/app_card.dart';
import '../profile/restaurant_admin/restaurant_admin_list_screen.dart';
import 'admin_audit_screen.dart';
import 'admin_reports_screen.dart';
import 'admin_services_screen.dart';
import 'admin_users_screen.dart';
import 'admin_widgets.dart';

/// «Администрирование» home: counters from GET /api/admin/summary and the
/// entries to the report queue, people search and the action log. Reached
/// from Profile only for an administrator; closes itself if the rights go.
class AdminHomeScreen extends ConsumerWidget {
  const AdminHomeScreen({super.key});

  static const title = 'Администрирование';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AdminGate(title: title, child: const _AdminHomeBody());
  }
}

class _AdminHomeBody extends ConsumerWidget {
  const _AdminHomeBody();

  void _open(BuildContext context, WidgetRef ref, Widget screen) {
    Navigator.of(context)
        .push(MaterialPageRoute(builder: (_) => screen))
        .then((_) => ref.invalidate(adminSummaryProvider));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final summary = ref.watch(adminSummaryProvider);
    return Scaffold(
      appBar: AppBar(title: const Text(AdminHomeScreen.title)),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(adminSummaryProvider.future),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.sm,
            AppSpacing.lg,
            AppSpacing.xl,
          ),
          children: [
            summary.when(
              loading: () => const SizedBox(
                height: 220,
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => SizedBox(
                height: 220,
                child: AdminErrorBody(
                  error: e,
                  onRetry: () => ref.invalidate(adminSummaryProvider),
                ),
              ),
              data: (s) => _SummaryGrid(
                summary: s,
                onReports: (status, mine) => _open(
                  context,
                  ref,
                  AdminReportsScreen(initialStatus: status, initialMine: mine),
                ),
                onBlocked: () => _open(
                  context,
                  ref,
                  const AdminUsersScreen(
                    initialFilter: AdminUserFilter.blocked,
                  ),
                ),
              ),
            ),
            const AdminSectionTitle('Разделы'),
            AdminRowCard(
              key: const ValueKey('admin-nav-reports'),
              leading: const Icon(Icons.flag_outlined),
              title: 'Жалобы',
              subtitle: 'Очередь, взятие в работу и решения',
              onTap: () => _open(context, ref, const AdminReportsScreen()),
            ),
            AdminRowCard(
              key: const ValueKey('admin-nav-users'),
              leading: const Icon(Icons.people_alt_outlined),
              title: 'Пользователи и услугодатели',
              subtitle: 'Поиск, профиль, карточки, санкции',
              onTap: () => _open(context, ref, const AdminUsersScreen()),
            ),
            AdminRowCard(
              key: const ValueKey('admin-nav-services'),
              leading: const Icon(Icons.design_services_outlined),
              title: 'Услуги',
              subtitle: 'Все категории: поиск, добавление, правка',
              onTap: () => _open(context, ref, const AdminServicesScreen()),
            ),
            AdminRowCard(
              key: const ValueKey('admin-nav-restaurants'),
              leading: const Icon(Icons.storefront_outlined),
              title: 'Рестораны и локации',
              subtitle: 'Добавление, залы, меню и адрес',
              onTap: () => _open(
                context,
                ref,
                const RestaurantAdminListScreen(title: 'Рестораны и локации'),
              ),
            ),
            AdminRowCard(
              key: const ValueKey('admin-nav-audit'),
              leading: const Icon(Icons.history_rounded),
              title: 'Журнал действий',
              subtitle: 'Кто, что и почему сделал',
              onTap: () => _open(context, ref, const AdminAuditScreen()),
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryGrid extends StatelessWidget {
  const _SummaryGrid({
    required this.summary,
    required this.onReports,
    required this.onBlocked,
  });

  final AdminSummary summary;
  final void Function(String status, bool mine) onReports;
  final VoidCallback onBlocked;

  @override
  Widget build(BuildContext context) {
    final tiles = <Widget>[
      _Tile(
        key: const ValueKey('admin-tile-reports-new'),
        value: summary.reportsNew,
        label: 'Новые жалобы',
        tone: summary.reportsNew > 0 ? AdminTone.bad : AdminTone.neutral,
        onTap: () => onReports('new', false),
      ),
      _Tile(
        key: const ValueKey('admin-tile-reports-review'),
        value: summary.reportsInReview,
        label: 'Жалобы в работе',
        tone: AdminTone.warn,
        onTap: () => onReports('in_review', false),
      ),
      _Tile(
        key: const ValueKey('admin-tile-reports-mine'),
        value: summary.reportsMine,
        label: 'Мои в работе',
        tone: AdminTone.accent,
        onTap: () => onReports('in_review', true),
      ),
      _Tile(
        key: const ValueKey('admin-tile-blocked'),
        value: summary.blockedUsers,
        label: 'Заблокированы',
        onTap: onBlocked,
      ),
      _Tile(value: summary.reviewsPending, label: 'Отзывы на проверке'),
      _Tile(value: summary.hiddenListings, label: 'Скрытые карточки'),
      _Tile(
        value: summary.recoveryRequestsPending,
        label: 'Запросы на восстановление',
      ),
      _Tile(value: summary.supportChatsOpen, label: 'Открытые чаты'),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        LayoutBuilder(
          builder: (context, c) {
            final w = (c.maxWidth - AppSpacing.sm) / 2;
            return Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [for (final t in tiles) SizedBox(width: w, child: t)],
            );
          },
        ),
        const SizedBox(height: AppSpacing.xs),
        Text(
          'Отзывы, восстановление и чаты разбираются в веб-админке.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    super.key,
    required this.value,
    required this.label,
    this.tone = AdminTone.neutral,
    this.onTap,
  });

  final int value;
  final String label;
  final AdminTone tone;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final c = context.mereytoiColors;
    final color = switch (tone) {
      AdminTone.bad => c.error,
      AdminTone.warn => c.warning,
      AdminTone.accent => c.goldPrimary,
      AdminTone.good => c.success,
      AdminTone.neutral => c.textPrimary,
    };
    return Semantics(
      button: onTap != null,
      label: '$label: $value',
      excludeSemantics: true,
      child: AppCard(
        padding: EdgeInsets.zero,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 84),
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    '$value',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontSize: 24,
                      color: value > 0 ? color : c.textMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
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
