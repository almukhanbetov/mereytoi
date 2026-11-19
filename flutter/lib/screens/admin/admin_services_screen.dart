import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/api_config.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/restaurant/restaurant_category.dart';
import '../../models/category.dart';
import '../../models/listing.dart';
import '../../state/admin_providers.dart';
import '../../state/categories_provider.dart';
import '../../state/listing_management_actions.dart';
import '../../state/listings_provider.dart';
import '../../widgets/network_image_box.dart';
import '../profile/restaurant_admin/restaurant_manage_screen.dart';
import 'admin_labels.dart';
import 'admin_listing_form_screen.dart';
import 'admin_widgets.dart';

/// Why visitors don't see a listing, in the order they're shown.
enum AdminHideReason { adminHidden, ownerBlocked, ownerUnpublished }

/// Whether visitors see a listing now, and why not — from the server's own
/// rule (the admin's GET /api/users/me/listings carries it). A listing
/// from anywhere else, or from an older server, falls back to its own
/// fields, which can't tell an owner's block.
class AdminVisibility {
  const AdminVisibility({
    required this.visible,
    required this.reasons,
    this.ownerBlockedUntil,
  });

  final bool visible;
  final List<AdminHideReason> reasons;

  /// End of the owner's block; null with [AdminHideReason.ownerBlocked]
  /// means a permanent block.
  final DateTime? ownerBlockedUntil;
}

AdminVisibility adminVisibility(Listing l) {
  if (l.publiclyVisible != null) {
    final r = l.visibilityReasons;
    return AdminVisibility(
      visible: l.publiclyVisible!,
      reasons: [
        if (r.contains('admin_hidden')) AdminHideReason.adminHidden,
        if (r.contains('owner_blocked')) AdminHideReason.ownerBlocked,
        if (r.contains('owner_unpublished')) AdminHideReason.ownerUnpublished,
      ],
      ownerBlockedUntil: l.ownerBlockedUntil,
    );
  }
  final reasons = [
    if (l.hiddenByAdmin) AdminHideReason.adminHidden,
    if (!l.isActive) AdminHideReason.ownerUnpublished,
  ];
  return AdminVisibility(visible: reasons.isEmpty, reasons: reasons);
}

List<Widget> adminVisibilityPills(Listing l) {
  final v = adminVisibility(l);
  if (v.visible) {
    return const [AdminPill('Видна посетителям', tone: AdminTone.good)];
  }
  return [
    for (final r in v.reasons)
      switch (r) {
        AdminHideReason.adminHidden => const AdminPill(
          'Скрыта администратором',
          tone: AdminTone.bad,
        ),
        AdminHideReason.ownerBlocked => const AdminPill(
          'Владелец заблокирован',
          tone: AdminTone.bad,
        ),
        AdminHideReason.ownerUnpublished => const AdminPill(
          'Снята с публикации',
          tone: AdminTone.warn,
        ),
      },
    if (v.reasons.isEmpty)
      const AdminPill('Не видна посетителям', tone: AdminTone.warn),
  ];
}

/// Search by name (рус/қаз) or city, any case; [categoryId] null = all.
List<Listing> filterAdminListings(
  List<Listing> all, {
  String query = '',
  int? categoryId,
}) {
  final q = query.trim().toLowerCase();
  return [
    for (final l in all)
      if ((categoryId == null || l.categoryId == categoryId) &&
          (q.isEmpty ||
              l.nameRu.toLowerCase().contains(q) ||
              l.nameKz.toLowerCase().contains(q) ||
              l.city.toLowerCase().contains(q)))
        l,
  ];
}

/// Opens a listing the way the web admin edits it: a restaurant in its
/// four tabs (Основное / Залы / Меню / Адрес), any other service in the
/// web admin's ServiceForm.
Future<void> openAdminListing(
  BuildContext context,
  Listing listing,
  List<Category> categories,
) {
  final slug = categories
      .where((c) => c.id == listing.categoryId)
      .map((c) => c.slug)
      .firstOrNull;
  return Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => isRestaurantCategory(slug)
          ? RestaurantManageScreen(listingId: listing.id)
          : AdminServiceEditScreen(listingId: listing.id),
    ),
  );
}

/// «Услуги» in the mobile admin: every listing of every category — the
/// published ones, those the owner unpublished and those an administrator
/// hid (GET /api/users/me/listings returns them all to an admin; the web
/// admin's category tables only show what the public list shows).
class AdminServicesScreen extends ConsumerStatefulWidget {
  const AdminServicesScreen({super.key});

  static const title = 'Услуги';

  @override
  ConsumerState<AdminServicesScreen> createState() =>
      _AdminServicesScreenState();
}

class _AdminServicesScreenState extends ConsumerState<AdminServicesScreen> {
  final _search = TextEditingController();
  int? _categoryId;

  @override
  void initState() {
    super.initState();
    _search.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  Future<void> _delete(Listing l) async {
    final ok = await showAdminConfirm(
      context,
      title: 'Удалить «${l.nameRu}»?',
      message:
          'Карточка удалится вместе с залами и меню. Это действие нельзя '
          'отменить.',
      confirmLabel: 'Удалить',
    );
    if (!ok || !mounted) return;
    try {
      await ref.read(listingManagementActionsProvider).deleteListing(l.id);
      if (mounted) showAdminSnack(context, 'Удалено: «${l.nameRu}»');
    } catch (e) {
      if (handleAdminRightsLost(ref, e)) return;
      if (mounted) showAdminSnack(context, adminErrorText(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    return AdminGate(title: AdminServicesScreen.title, child: _body(context));
  }

  Widget _body(BuildContext context) {
    final listingsAsync = ref.watch(myListingsProvider);
    final categories = ref.watch(categoriesProvider).valueOrNull ?? const [];
    final colors = context.mereytoiColors;

    return Scaffold(
      appBar: AppBar(title: const Text(AdminServicesScreen.title)),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('services-add'),
        backgroundColor: colors.goldPrimary,
        foregroundColor: colors.onGold,
        onPressed: () => Navigator.of(context).push(
          MaterialPageRoute(
            builder: (_) =>
                AdminListingCreateScreen(presetCategoryId: _categoryId),
          ),
        ),
        icon: const Icon(Icons.add_rounded),
        label: const Text('Добавить услугу'),
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.xs,
            ),
            child: TextField(
              key: const ValueKey('services-search'),
              controller: _search,
              textInputAction: TextInputAction.search,
              decoration: InputDecoration(
                hintText: 'Название или город',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _search.text.isEmpty
                    ? null
                    : IconButton(
                        tooltip: 'Очистить',
                        onPressed: _search.clear,
                        icon: const Icon(Icons.close_rounded),
                      ),
              ),
            ),
          ),
          SizedBox(
            height: 56,
            child: ListView(
              key: const ValueKey('services-categories'),
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              children: [
                _chip(null, 'Все'),
                for (final c in categories) _chip(c.id, c.nameRu),
              ],
            ),
          ),
          Expanded(
            child: listingsAsync.when(
              loading: () => const AdminLoadingList(),
              error: (e, _) {
                handleAdminRightsLost(ref, e);
                return AdminErrorBody(
                  error: e,
                  onRetry: () => ref.invalidate(myListingsProvider),
                );
              },
              data: (all) {
                final items = filterAdminListings(
                  all,
                  query: _search.text,
                  categoryId: _categoryId,
                );
                return RefreshIndicator(
                  onRefresh: () => ref.refresh(myListingsProvider.future),
                  child: items.isEmpty
                      ? ListView(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.all(AppSpacing.xl),
                          children: [
                            Center(
                              key: const ValueKey('services-empty'),
                              child: Text(
                                all.isEmpty
                                    ? 'Услуг пока нет'
                                    : 'Ничего не найдено',
                                style: Theme.of(context).textTheme.titleMedium,
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          physics: const AlwaysScrollableScrollPhysics(),
                          padding: const EdgeInsets.fromLTRB(
                            AppSpacing.lg,
                            AppSpacing.xs,
                            AppSpacing.lg,
                            96,
                          ),
                          itemCount: items.length + 1,
                          itemBuilder: (context, i) {
                            if (i == 0) {
                              return Padding(
                                padding: const EdgeInsets.only(
                                  bottom: AppSpacing.xs,
                                ),
                                child: Text(
                                  'Найдено: ${items.length}',
                                  key: const ValueKey('services-count'),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              );
                            }
                            final l = items[i - 1];
                            return _row(context, l, categories);
                          },
                        ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  Widget _chip(int? id, String label) {
    final selected = _categoryId == id;
    return Padding(
      padding: const EdgeInsets.only(right: AppSpacing.xs),
      child: ChoiceChip(
        key: ValueKey('services-cat-${id ?? 'all'}'),
        label: Text(label),
        selected: selected,
        materialTapTargetSize: MaterialTapTargetSize.padded,
        onSelected: (_) => setState(() => _categoryId = id),
      ),
    );
  }

  Widget _row(BuildContext context, Listing l, List<Category> categories) {
    final category = categories
        .where((c) => c.id == l.categoryId)
        .map((c) => c.nameRu)
        .firstOrNull;
    final owner = l.provider?.displayName;
    final subtitle = [
      ?category,
      if (l.city.isNotEmpty) l.city,
      owner == null || owner.isEmpty ? 'Без владельца' : 'Владелец: $owner',
    ].join(' · ');
    return AdminRowCard(
      key: ValueKey('service-row-${l.id}'),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: SizedBox(
          width: 48,
          height: 48,
          child: NetworkImageBox(
            url: ApiConfig.mediaUrl(l.coverImage),
            borderRadius: AppRadius.sm,
          ),
        ),
      ),
      title: l.nameRu,
      subtitle: subtitle,
      pills: [
        ...adminVisibilityPills(l),
        _DeleteButton(onPressed: () => _delete(l), listingId: l.id),
      ],
      onTap: () => openAdminListing(context, l, categories),
    );
  }
}

class _DeleteButton extends StatelessWidget {
  const _DeleteButton({required this.onPressed, required this.listingId});

  final VoidCallback onPressed;
  final int listingId;

  @override
  Widget build(BuildContext context) {
    return TextButton(
      key: ValueKey('service-delete-$listingId'),
      style: TextButton.styleFrom(
        foregroundColor: context.mereytoiColors.error,
        minimumSize: const Size(48, 40),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
        tapTargetSize: MaterialTapTargetSize.padded,
      ),
      onPressed: onPressed,
      child: const Text('Удалить'),
    );
  }
}

/// «Скрыть» / «Восстановить» with a reason — the same server action and
/// audit entry as on the user's card in «Пользователи».
Future<void> toggleAdminListingHidden(
  BuildContext context,
  WidgetRef ref,
  Listing l,
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
  if (!ok) return;
  ref.invalidate(listingDetailProvider(l.id));
  ref.invalidate(myListingsProvider);
  if (context.mounted) {
    showAdminSnack(
      context,
      restore ? 'Карточка восстановлена' : 'Карточка скрыта',
    );
  }
}

/// «Редактировать услугу» for any category but restaurants: the web
/// admin's ServiceForm. Saving never touches the administrator's hiding or
/// the owner's publish switch — the form sends them back unchanged, and
/// hiding is changed only by «Скрыть» / «Восстановить» here, with a reason.
class AdminServiceEditScreen extends ConsumerWidget {
  const AdminServiceEditScreen({super.key, required this.listingId});

  final int listingId;

  static const title = 'Редактировать услугу';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final listingAsync = ref.watch(listingDetailProvider(listingId));
    return AdminGate(
      title: title,
      child: Scaffold(
        appBar: AppBar(
          title: const Text(title),
          actions: [
            if (listingAsync.valueOrNull case final l?)
              TextButton(
                key: const ValueKey('service-toggle-hidden'),
                style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
                onPressed: () => toggleAdminListingHidden(context, ref, l),
                child: Text(l.hiddenByAdmin ? 'Восстановить' : 'Скрыть'),
              ),
          ],
        ),
        body: listingAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) {
            handleAdminRightsLost(ref, e);
            return AdminErrorBody(
              error: e,
              onRetry: () => ref.invalidate(listingDetailProvider(listingId)),
            );
          },
          data: (l) => Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              AdminListingStatusBanner(listing: l),
              Expanded(
                child: AdminListingForm(
                  key: ValueKey('admin-edit-${l.id}'),
                  existing: l,
                  onSaved: (saved, category) {
                    // Moved to the restaurants category: its tabs now apply.
                    if (category != null &&
                        isRestaurantCategory(category.slug)) {
                      Navigator.of(context).pushReplacement(
                        MaterialPageRoute(
                          builder: (_) =>
                              RestaurantManageScreen(listingId: saved.id),
                        ),
                      );
                    }
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The card's state for visitors. The hiding reason comes from the admin's
/// list (GET /api/users/me/listings): the listing's own detail never
/// carries it.
class AdminListingStatusBanner extends ConsumerWidget {
  const AdminListingStatusBanner({super.key, required this.listing});

  final Listing listing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final fromList =
        (ref.watch(myListingsProvider).valueOrNull ?? const <Listing>[])
            .where((l) => l.id == listing.id)
            .firstOrNull;
    // The admin's list knows the owner's block and the hiding reason; the
    // listing's own detail doesn't. Hiding and publishing come from the
    // freshest copy, the detail.
    final v = adminVisibility(fromList ?? listing);
    final hidden = listing.hiddenByAdmin;
    final unpublished = !listing.isActive;
    final reasons = [
      if (hidden) AdminHideReason.adminHidden,
      if (v.reasons.contains(AdminHideReason.ownerBlocked))
        AdminHideReason.ownerBlocked,
      if (unpublished) AdminHideReason.ownerUnpublished,
    ];
    final visible = reasons.isEmpty;
    final reason = listing.moderationReason.isNotEmpty
        ? listing.moderationReason
        : fromList?.moderationReason ?? '';
    final colors = context.mereytoiColors;
    final lines = [
      for (final r in reasons)
        switch (r) {
          AdminHideReason.adminHidden =>
            '• скрыта администратором${reason.isEmpty ? '' : ': ${_trimDot(reason)}'}',
          AdminHideReason.ownerBlocked =>
            v.ownerBlockedUntil == null
                ? '• владелец заблокирован бессрочно'
                : '• владелец заблокирован до ${formatAdminDate(v.ownerBlockedUntil)}; '
                      'после окончания блокировки карточка вернётся, если нет '
                      'других причин',
          AdminHideReason.ownerUnpublished => '• снята с публикации владельцем',
        },
    ];
    final text = visible
        ? 'Видна посетителям.'
        : 'Не видна посетителям:\n${lines.join('\n')}\n'
              'Сохранение формы видимость не меняет.';
    final color = visible
        ? colors.success
        : reasons.contains(AdminHideReason.ownerUnpublished) &&
              reasons.length == 1
        ? colors.warning
        : colors.error;
    return Container(
      key: const ValueKey('service-status-banner'),
      margin: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        0,
      ),
      padding: const EdgeInsets.all(AppSpacing.sm),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      child: Text(text, style: TextStyle(color: color, fontSize: 14)),
    );
  }
}

String _trimDot(String s) => s.endsWith('.') ? s.substring(0, s.length - 1) : s;
