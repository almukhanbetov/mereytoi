import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/restaurant/restaurant_category.dart';
import '../../models/admin.dart';
import '../../state/admin_providers.dart';
import '../../state/auth_provider.dart';
import '../../state/categories_provider.dart';
import '../../widgets/app_card.dart';
import '../restaurant/restaurant_detail_screen.dart';
import '../service_detail/service_detail_screen.dart';
import 'admin_labels.dart';
import 'admin_widgets.dart';

/// One person: profile, provider profile, their listings with visibility,
/// sanctions history — and the actions: warn, block (term), unblock, hide or
/// restore a listing. Every action asks for a required reason and confirms
/// in a sheet; the server re-checks the rights and records it in the log.
class AdminUserScreen extends ConsumerWidget {
  const AdminUserScreen({super.key, required this.userId});

  static const title = 'Профиль пользователя';

  final int userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detail = ref.watch(adminUserDetailProvider(userId));
    return AdminGate(
      title: title,
      child: Scaffold(
        appBar: AppBar(title: const Text(title)),
        body: detail.when(
          loading: () => const AdminLoadingList(count: 3),
          error: (e, _) => AdminErrorBody(
            error: e,
            onRetry: () => ref.invalidate(adminUserDetailProvider(userId)),
          ),
          data: (d) => RefreshIndicator(
            onRefresh: () =>
                ref.refresh(adminUserDetailProvider(userId).future),
            child: _UserBody(detail: d),
          ),
        ),
      ),
    );
  }
}

class _UserBody extends ConsumerWidget {
  const _UserBody({required this.detail});

  final AdminUserDetail detail;

  void _changed(BuildContext context, WidgetRef ref, String message) {
    ref.invalidate(adminUserDetailProvider(detail.user.id));
    ref.invalidate(adminSummaryProvider);
    showAdminSnack(context, message);
  }

  Future<void> _warn(BuildContext context, WidgetRef ref) async {
    final u = detail.user;
    final ok = await showAdminActionSheet(
      context,
      title: 'Предупредить пользователя?',
      message:
          '${u.name} получит уведомление с этой причиной. Доступ не ограничивается.',
      confirmLabel: 'Предупредить',
      danger: false,
      onSubmit: (reason, _) =>
          ref.read(adminServiceProvider).warn(u.id, reason),
    );
    if (ok && context.mounted) {
      _changed(context, ref, 'Предупреждение отправлено');
    }
  }

  Future<void> _block(BuildContext context, WidgetRef ref) async {
    final u = detail.user;
    final ok = await showAdminActionSheet(
      context,
      title: 'Заблокировать пользователя?',
      message:
          'Все сеансы ${u.name} закроются, вход станет недоступен. Карточки '
          'пользователя скроются от посетителей до разблокировки; '
          'бронирования, переписки и отзывы сохранятся.',
      confirmLabel: 'Заблокировать',
      withDuration: true,
      subjectName: u.name.isEmpty ? u.email : '${u.name} (${u.email})',
      onSubmit: (reason, duration) =>
          ref.read(adminServiceProvider).block(u.id, reason, duration!),
    );
    if (ok && context.mounted) {
      _changed(context, ref, 'Пользователь заблокирован');
    }
  }

  Future<void> _unblock(BuildContext context, WidgetRef ref) async {
    final u = detail.user;
    final ok = await showAdminActionSheet(
      context,
      title: 'Разблокировать пользователя?',
      message:
          'Доступ ${u.name} восстановится. Вернутся только те карточки, '
          'что были видны до блокировки.',
      confirmLabel: 'Разблокировать',
      danger: false,
      onSubmit: (reason, _) =>
          ref.read(adminServiceProvider).unblock(u.id, reason),
    );
    if (ok && context.mounted) {
      _changed(context, ref, 'Пользователь разблокирован');
    }
  }

  Future<void> _toggleListing(
    BuildContext context,
    WidgetRef ref,
    AdminListing l,
  ) async {
    final restore = l.hiddenByAdmin;
    final ok = await showAdminActionSheet(
      context,
      title: restore ? 'Восстановить карточку?' : 'Скрыть карточку?',
      message: restore
          ? '«${l.nameRu}» снова станет видна посетителям, если владелец её '
                'не снял с публикации.'
          : '«${l.nameRu}» пропадёт из каталога и по прямой ссылке. Владелец '
                'не сможет отменить скрытие.',
      confirmLabel: restore ? 'Восстановить' : 'Скрыть',
      danger: !restore,
      onSubmit: (reason, _) => restore
          ? ref.read(adminServiceProvider).restoreListing(l.id, reason)
          : ref.read(adminServiceProvider).hideListing(l.id, reason),
    );
    if (ok && context.mounted) {
      _changed(
        context,
        ref,
        restore ? 'Карточка восстановлена' : 'Карточка скрыта',
      );
    }
  }

  void _openListing(BuildContext context, WidgetRef ref, AdminListing l) {
    String? slug;
    for (final c in ref.read(categoriesProvider).valueOrNull ?? const []) {
      if (c.id == l.categoryId) slug = c.slug;
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => isRestaurantCategory(slug)
            ? RestaurantDetailScreen(listingId: l.id)
            : ServiceDetailScreen(listingId: l.id),
      ),
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final u = detail.user;
    final auth = ref.watch(authProvider);
    final isSelf = auth is AuthAuthenticated && auth.user.id == u.id;
    final textTheme = Theme.of(context).textTheme;
    final colors = context.mereytoiColors;

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
              Text(
                u.name.isEmpty ? 'Без имени' : u.name,
                style: textTheme.titleMedium,
              ),
              const SizedBox(height: 4),
              SelectableText(u.email, style: textTheme.bodyMedium),
              if (u.phone.isNotEmpty)
                SelectableText(u.phone, style: textTheme.bodyMedium),
              const SizedBox(height: AppSpacing.xs),
              Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [
                  AdminPill('ID ${u.id}'),
                  if (u.isAdmin)
                    const AdminPill('Администратор', tone: AdminTone.accent),
                  if (u.status == 'pending')
                    const AdminPill('Не активирован', tone: AdminTone.warn),
                  if (u.isBlocked)
                    const AdminPill('Заблокирован', tone: AdminTone.bad)
                  else
                    const AdminPill('Активен', tone: AdminTone.good),
                  if (u.createdAt != null)
                    AdminPill('С ${formatAdminDate(u.createdAt)}'),
                ],
              ),
              if (u.isBlocked) ...[
                const SizedBox(height: AppSpacing.sm),
                Text(
                  u.block!.until == null
                      ? 'Блокировка бессрочная'
                      : 'Блокировка до ${formatAdminDate(u.block!.until)}',
                  style: textTheme.bodyMedium?.copyWith(color: colors.error),
                ),
                Text('Причина: ${u.block!.reason}', style: textTheme.bodySmall),
              ],
            ],
          ),
        ),
        if (u.provider != null) ...[
          const AdminSectionTitle('Услугодатель'),
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(u.provider!.displayName, style: textTheme.titleSmall),
                if (u.provider!.city.isNotEmpty)
                  Text(u.provider!.city, style: textTheme.bodySmall),
                const SizedBox(height: 4),
                Text(
                  'Телефон: ${u.provider!.phone.isEmpty ? '—' : u.provider!.phone}',
                  style: textTheme.bodySmall,
                ),
                Text(
                  'WhatsApp: ${u.provider!.whatsapp.isEmpty ? '—' : u.provider!.whatsapp}',
                  style: textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ],
        const AdminSectionTitle('Действия'),
        if (isSelf)
          Text(
            'Это ваш аккаунт — санкции к нему не применяются.',
            style: textTheme.bodySmall,
          )
        else
          Wrap(
            spacing: AppSpacing.xs,
            runSpacing: AppSpacing.xs,
            children: [
              OutlinedButton.icon(
                key: const ValueKey('admin-warn'),
                onPressed: () => _warn(context, ref),
                icon: const Icon(Icons.campaign_outlined, size: 18),
                label: const Text('Предупредить'),
              ),
              if (u.isBlocked)
                OutlinedButton.icon(
                  key: const ValueKey('admin-unblock'),
                  onPressed: () => _unblock(context, ref),
                  icon: const Icon(Icons.lock_open_rounded, size: 18),
                  label: const Text('Разблокировать'),
                )
              else if (!u.isAdmin)
                OutlinedButton.icon(
                  key: const ValueKey('admin-block'),
                  onPressed: () => _block(context, ref),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: colors.error,
                    side: BorderSide(color: colors.error),
                  ),
                  icon: const Icon(Icons.block_rounded, size: 18),
                  label: const Text('Заблокировать'),
                ),
            ],
          ),
        AdminSectionTitle('Карточки (${detail.listings.length})'),
        if (detail.listings.isEmpty)
          Text('Карточек нет.', style: textTheme.bodySmall),
        for (final l in detail.listings)
          _ListingRow(
            listing: l,
            onOpen: () => _openListing(context, ref, l),
            onToggle: () => _toggleListing(context, ref, l),
          ),
        const AdminSectionTitle('История санкций'),
        if (detail.history.isEmpty)
          Text('Действий не было.', style: textTheme.bodySmall),
        for (final e in detail.history) AdminAuditRow(event: e),
      ],
    );
  }
}

class _ListingRow extends StatelessWidget {
  const _ListingRow({
    required this.listing,
    required this.onOpen,
    required this.onToggle,
  });

  final AdminListing listing;
  final VoidCallback onOpen;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final l = listing;
    final colors = context.mereytoiColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              key: ValueKey('admin-listing-open-${l.id}'),
              onTap: onOpen,
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        l.nameRu,
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.open_in_new_rounded,
                      size: 18,
                      color: colors.textMuted,
                    ),
                  ],
                ),
              ),
            ),
            Wrap(
              spacing: 6,
              runSpacing: 6,
              children: [
                AdminPill('ID ${l.id}'),
                if (l.role == 'owner') const AdminPill('Владелец'),
                if (l.role == 'manager') const AdminPill('Менеджер'),
                l.publiclyVisible
                    ? const AdminPill('Видна посетителям', tone: AdminTone.good)
                    : const AdminPill(
                        'Не видна посетителям',
                        tone: AdminTone.warn,
                      ),
                if (!l.isActive) const AdminPill('Снята владельцем'),
                if (l.hiddenByAdmin)
                  const AdminPill(
                    'Скрыта администратором',
                    tone: AdminTone.bad,
                  ),
              ],
            ),
            if (l.hiddenByAdmin && l.moderationReason.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                'Причина скрытия: ${l.moderationReason}',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const SizedBox(height: AppSpacing.xs),
            Align(
              alignment: Alignment.centerLeft,
              child: TextButton.icon(
                key: ValueKey('admin-listing-toggle-${l.id}'),
                onPressed: onToggle,
                style: TextButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  foregroundColor: l.hiddenByAdmin
                      ? colors.goldPrimary
                      : colors.error,
                ),
                icon: Icon(
                  l.hiddenByAdmin
                      ? Icons.visibility_outlined
                      : Icons.visibility_off_outlined,
                  size: 18,
                ),
                label: Text(l.hiddenByAdmin ? 'Восстановить' : 'Скрыть'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One action-log row, shared by the profile history and the log screen.
class AdminAuditRow extends ConsumerWidget {
  const AdminAuditRow({
    super.key,
    required this.event,
    this.showTarget = false,
  });

  final AdminAuditEvent event;
  final bool showTarget;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final e = event;
    final textTheme = Theme.of(context).textTheme;
    final auth = ref.watch(authProvider);
    final mine = auth is AuthAuthenticated && auth.user.id == e.actorId;
    final actor = mine
        ? 'Вы'
        : e.actorName.isEmpty
        ? 'Администратор #${e.actorId}'
        : e.actorName;
    final tone = switch (e.action) {
      'user.block' || 'listing.hide' => AdminTone.bad,
      'user.warn' => AdminTone.warn,
      'user.unblock' || 'listing.restore' || 'report.resolve' => AdminTone.good,
      _ => AdminTone.neutral,
    };
    final until = e.changes['blocked_until'];
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: AppCard(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                AdminPill(labelOf(auditActionLabels, e.action), tone: tone),
                if (showTarget)
                  AdminPill(
                    '${labelOf(auditTargetLabels, e.targetType)} #${e.targetId}',
                  ),
              ],
            ),
            const SizedBox(height: 4),
            if (e.reason.isNotEmpty)
              Text(e.reason, style: textTheme.bodyMedium),
            if (e.action == 'user.block')
              Text(
                until == null
                    ? 'Срок: бессрочно'
                    : 'До ${formatAdminDate(DateTime.tryParse('$until')?.toLocal())}',
                style: textTheme.bodySmall,
              ),
            const SizedBox(height: 2),
            Text(
              '$actor · ${formatAdminDate(e.createdAt)}',
              style: textTheme.bodySmall,
            ),
          ],
        ),
      ),
    );
  }
}
