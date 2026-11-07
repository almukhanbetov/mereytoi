import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/error_messages.dart';
import '../../../../core/utils/format.dart';
import '../../../../models/listing_hall.dart';
import '../../../../models/listing_menu.dart';
import '../../../../state/listing_management_actions.dart';
import '../../../../state/listings_provider.dart';
import '../../../../state/locale_provider.dart';
import '../../../../widgets/admin/form_sheet_scaffold.dart';
import '../../../../widgets/app_card.dart';
import '../../../../widgets/app_error_view.dart';
import '../../../../widgets/app_icon_badge.dart';
import '../../../../widgets/app_skeleton.dart';
import '../menu_detail_screen.dart';
import '../widgets/manage_actions_button.dart';
import '../widgets/menu_form_sheet.dart';

/// "Меню" tab — `listingMenusProvider` (`GET /api/listings/:id/menus`)
/// already returns every menu regardless of `is_active` (`loadListingTree`
/// has no such filter at the SQL level, unlike the halls endpoint), so no
/// separate "all menus" provider is needed the way halls needed one.
class MenusTab extends ConsumerWidget {
  const MenusTab({super.key, required this.listingId});

  final int listingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final menusAsync = ref.watch(listingMenusProvider(listingId));
    final hallsAsync = ref.watch(listingAllHallsProvider(listingId));

    return Stack(
      children: [
        menusAsync.when(
          loading: () => ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              88,
            ),
            children: const [
              AppSkeleton(height: 96, borderRadius: AppRadius.lg),
              SizedBox(height: AppSpacing.sm),
              AppSkeleton(height: 96, borderRadius: AppRadius.lg),
            ],
          ),
          error: (err, _) => AppErrorView(
            message: apiErrorMessage(locale, err),
            error: err,
            locale: locale,
            onRetry: () => ref.invalidate(listingMenusProvider(listingId)),
          ),
          data: (unsorted) {
            final menus = _sorted(unsorted);
            return RefreshIndicator(
              color: context.mereytoiColors.goldPrimary,
              backgroundColor: context.mereytoiColors.surfaceElevated,
              onRefresh: () =>
                  ref.refresh(listingMenusProvider(listingId).future),
              child: menus.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      children: [
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const AppIconBadge(
                                icon: Icons.restaurant_menu_outlined,
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Text(
                                t(
                                  locale,
                                  ru: 'Меню пока не добавлены',
                                  kz: 'Мәзірлер әлі қосылмаған',
                                ),
                                style: Theme.of(context).textTheme.titleMedium,
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ],
                    )
                  : ListView.separated(
                      padding: const EdgeInsets.fromLTRB(
                        AppSpacing.lg,
                        AppSpacing.lg,
                        AppSpacing.lg,
                        88,
                      ),
                      itemCount: menus.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, i) => _MenuCard(
                        listingId: listingId,
                        menus: menus,
                        index: i,
                        halls: hallsAsync.valueOrNull ?? const [],
                      ),
                    ),
            );
          },
        ),
        Positioned(
          right: AppSpacing.lg,
          bottom: AppSpacing.lg,
          child: FloatingActionButton.extended(
            backgroundColor: context.mereytoiColors.goldPrimary,
            foregroundColor: context.mereytoiColors.onGold,
            onPressed: () => openMenuFormSheet(
              context,
              listingId: listingId,
              halls: hallsAsync.valueOrNull ?? const [],
              nextSortOrder: menusAsync.valueOrNull?.length ?? 0,
            ),
            icon: const Icon(Icons.add_rounded),
            label: Text(t(locale, ru: 'Добавить меню', kz: 'Мәзір қосу')),
          ),
        ),
      ],
    );
  }
}

List<ListingMenu> _sorted(List<ListingMenu> menus) => [...menus]
  ..sort((a, b) {
    final byOrder = a.sortOrder.compareTo(b.sortOrder);
    return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
  });

class _MenuCard extends ConsumerWidget {
  const _MenuCard({
    required this.listingId,
    required this.menus,
    required this.index,
    required this.halls,
  });

  final int listingId;
  final List<ListingMenu> menus;
  final int index;
  final List<ListingHall> halls;

  ListingMenu get menu => menus[index];

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final locale = ref.read(localeProvider);
    final confirmed = await ConfirmDeleteSheet.show(
      context,
      title: t(
        locale,
        ru: 'Удалить меню «${menu.nameRu}»? Разделы, позиции и опции будут удалены вместе с ним.',
        kz: '«${menu.nameRu}» мәзірін жою керек пе? Бөлімдер, позициялар және опциялар да жойылады.',
      ),
      confirmLabel: t(locale, ru: 'Удалить', kz: 'Жою'),
      cancelLabel: t(locale, ru: 'Отмена', kz: 'Бас тарту'),
    );
    if (!confirmed) return;
    try {
      await ref
          .read(listingManagementActionsProvider)
          .deleteMenu(listingId, menu.id);
    } catch (err) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiErrorMessage(locale, err))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final colors = context.mereytoiColors;
    final actions = ref.read(listingManagementActionsProvider);
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) =>
              MenuDetailScreen(listingId: listingId, menuId: menu.id),
        ),
      ),
      child: AppCard(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          menu.name(locale),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                      ),
                      if (!menu.isActive)
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.xxs,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colors.surfaceSoft,
                            borderRadius: BorderRadius.circular(AppRadius.chip),
                          ),
                          child: Text(
                            t(locale, ru: 'Скрыто', kz: 'Жасырын'),
                            style: Theme.of(context).textTheme.labelSmall,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 2),
                  Text(
                    menu.pricePerGuest > 0
                        ? '${formatPrice(menu.pricePerGuest)} / ${t(locale, ru: "гость", kz: "қонақ")}'
                        : t(
                            locale,
                            ru: 'Цена не указана',
                            kz: 'Баға көрсетілмеген',
                          ),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                  Text(
                    '${t(locale, ru: "Разделов", kz: "Бөлімдер")}: ${menu.sections.length} · '
                    '${t(locale, ru: "Опций", kz: "Опциялар")}: ${menu.extras.length}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            const SizedBox(width: AppSpacing.xs),
            IconButton(
              onPressed: () => openMenuFormSheet(
                context,
                listingId: listingId,
                halls: halls,
                existing: menu,
              ),
              icon: Icon(
                Icons.edit_outlined,
                size: 18,
                color: colors.textSecondary,
              ),
            ),
            ManageActionsButton(
              key: ValueKey('menu-actions-${menu.id}'),
              locale: locale,
              actions: [
                ManageAction(
                  label: menu.isActive
                      ? t(locale, ru: 'Скрыть', kz: 'Жасыру', en: 'Hide')
                      : t(locale, ru: 'Показать', kz: 'Көрсету', en: 'Show'),
                  icon: menu.isActive
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                  onTap: () => runManaged(
                    context,
                    locale,
                    () =>
                        actions.setMenuActive(listingId, menu, !menu.isActive),
                  ),
                ),
                ...moveActions(
                  locale,
                  index: index,
                  count: menus.length,
                  onMove: (delta) => runManaged(
                    context,
                    locale,
                    () => actions.reorderMenus(
                      listingId,
                      movedBy(menus, index, delta),
                    ),
                  ),
                ),
                ManageAction(
                  label: t(
                    locale,
                    ru: 'Дублировать',
                    kz: 'Көшіру',
                    en: 'Duplicate',
                  ),
                  icon: Icons.copy_rounded,
                  onTap: () => runManaged(
                    context,
                    locale,
                    () => actions.duplicateMenu(
                      listingId,
                      menu,
                      count: menus.length,
                    ),
                    doneMessage: t(
                      locale,
                      ru: 'Создана скрытая копия меню',
                      kz: 'Мәзірдің жасырын көшірмесі жасалды',
                      en: 'A hidden copy of the menu was created',
                    ),
                  ),
                ),
                ManageAction(
                  label: t(locale, ru: 'Удалить', kz: 'Жою', en: 'Delete'),
                  icon: Icons.delete_outline_rounded,
                  destructive: true,
                  onTap: () => _delete(context, ref),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
