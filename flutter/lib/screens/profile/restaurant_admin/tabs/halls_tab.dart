import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/error_messages.dart';
import '../../../../core/utils/format.dart';
import '../../../../models/listing_hall.dart';
import '../../../../state/listing_management_actions.dart';
import '../../../../state/locale_provider.dart';
import '../../../../widgets/admin/form_sheet_scaffold.dart';
import '../../../../widgets/app_card.dart';
import '../../../../widgets/app_error_view.dart';
import '../../../../widgets/app_icon_badge.dart';
import '../../../../widgets/app_skeleton.dart';
import '../../../../widgets/network_image_box.dart';
import '../widgets/hall_form_sheet.dart';
import '../widgets/manage_actions_button.dart';

/// "Залы" tab — every hall regardless of `is_active` (see
/// [listingAllHallsProvider]'s own doc comment on why management can't
/// reuse the public, active-only `listingHallsProvider`).
class HallsTab extends ConsumerWidget {
  const HallsTab({super.key, required this.listingId});

  final int listingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final hallsAsync = ref.watch(listingAllHallsProvider(listingId));

    return Stack(
      children: [
        hallsAsync.when(
          loading: () => ListView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.lg,
              AppSpacing.lg,
              88,
            ),
            children: const [
              AppSkeleton(height: 88, borderRadius: AppRadius.lg),
              SizedBox(height: AppSpacing.sm),
              AppSkeleton(height: 88, borderRadius: AppRadius.lg),
            ],
          ),
          error: (err, _) => AppErrorView(
            message: apiErrorMessage(locale, err),
            error: err,
            locale: locale,
            onRetry: () => ref.invalidate(listingAllHallsProvider(listingId)),
          ),
          data: (unsorted) {
            final halls = _sorted(unsorted);
            return RefreshIndicator(
              color: context.mereytoiColors.goldPrimary,
              backgroundColor: context.mereytoiColors.surfaceElevated,
              onRefresh: () =>
                  ref.refresh(listingAllHallsProvider(listingId).future),
              child: halls.isEmpty
                  ? ListView(
                      padding: const EdgeInsets.all(AppSpacing.xl),
                      children: [
                        Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const AppIconBadge(
                                icon: Icons.meeting_room_outlined,
                              ),
                              const SizedBox(height: AppSpacing.md),
                              Text(
                                t(
                                  locale,
                                  ru: 'Залы пока не добавлены',
                                  kz: 'Залдар әлі қосылмаған',
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
                      itemCount: halls.length,
                      separatorBuilder: (_, _) =>
                          const SizedBox(height: AppSpacing.sm),
                      itemBuilder: (context, i) => _HallCard(
                        listingId: listingId,
                        halls: halls,
                        index: i,
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
            onPressed: () => openHallFormSheet(
              context,
              listingId: listingId,
              nextSortOrder: hallsAsync.valueOrNull?.length ?? 0,
            ),
            icon: const Icon(Icons.add_rounded),
            label: Text(t(locale, ru: 'Добавить зал', kz: 'Зал қосу')),
          ),
        ),
      ],
    );
  }
}

List<ListingHall> _sorted(List<ListingHall> halls) => [...halls]
  ..sort((a, b) {
    final byOrder = a.sortOrder.compareTo(b.sortOrder);
    return byOrder != 0 ? byOrder : a.id.compareTo(b.id);
  });

class _HallCard extends ConsumerWidget {
  const _HallCard({
    required this.listingId,
    required this.halls,
    required this.index,
  });

  final int listingId;
  final List<ListingHall> halls;
  final int index;

  ListingHall get hall => halls[index];

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final locale = ref.read(localeProvider);
    final confirmed = await ConfirmDeleteSheet.show(
      context,
      title: t(
        locale,
        ru: 'Удалить зал «${hall.nameRu}»?',
        kz: '«${hall.nameRu}» залын жою керек пе?',
      ),
      confirmLabel: t(locale, ru: 'Удалить', kz: 'Жою'),
      cancelLabel: t(locale, ru: 'Отмена', kz: 'Бас тарту'),
    );
    if (!confirmed) return;
    try {
      await ref
          .read(listingManagementActionsProvider)
          .deleteHall(listingId, hall.id);
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
    return AppCard(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (hall.imageUrls.isNotEmpty) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: SizedBox(
                width: 56,
                height: 56,
                child: NetworkImageBox(
                  url: ApiConfig.mediaUrl(hall.imageUrls.first),
                  borderRadius: 0,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        hall.name(locale),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.titleSmall,
                      ),
                    ),
                    if (!hall.isActive)
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
                          t(locale, ru: 'Скрыт', kz: 'Жасырын'),
                          style: Theme.of(context).textTheme.labelSmall,
                        ),
                      ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '${t(locale, ru: "Вместимость", kz: "Сыйымдылық")}: ${hall.capacity}'
                  '${hall.price > 0 ? ' · ${formatPrice(hall.price)}' : ''}',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          IconButton(
            onPressed: () => openHallFormSheet(
              context,
              listingId: listingId,
              existing: hall,
            ),
            icon: Icon(
              Icons.edit_outlined,
              size: 18,
              color: colors.textSecondary,
            ),
          ),
          ManageActionsButton(
            key: ValueKey('hall-actions-${hall.id}'),
            locale: locale,
            actions: [
              ManageAction(
                label: hall.isActive
                    ? t(locale, ru: 'Скрыть', kz: 'Жасыру', en: 'Hide')
                    : t(locale, ru: 'Показать', kz: 'Көрсету', en: 'Show'),
                icon: hall.isActive
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                onTap: () => runManaged(
                  context,
                  locale,
                  () => actions.setHallActive(listingId, hall, !hall.isActive),
                ),
              ),
              ...moveActions(
                locale,
                index: index,
                count: halls.length,
                onMove: (delta) => runManaged(
                  context,
                  locale,
                  () => actions.reorderHalls(
                    listingId,
                    movedBy(halls, index, delta),
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
                  () => actions.duplicateHall(
                    listingId,
                    hall,
                    count: halls.length,
                  ),
                  doneMessage: t(
                    locale,
                    ru: 'Создана скрытая копия зала',
                    kz: 'Залдың жасырын көшірмесі жасалды',
                    en: 'A hidden copy of the hall was created',
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
    );
  }
}
