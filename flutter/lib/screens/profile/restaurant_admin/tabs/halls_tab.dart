import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
import '../widgets/hall_form_sheet.dart';

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
            locale: locale,
            onRetry: () => ref.invalidate(listingAllHallsProvider(listingId)),
          ),
          data: (halls) => RefreshIndicator(
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
                    itemBuilder: (context, i) =>
                        _HallCard(listingId: listingId, hall: halls[i]),
                  ),
          ),
        ),
        Positioned(
          right: AppSpacing.lg,
          bottom: AppSpacing.lg,
          child: FloatingActionButton.extended(
            onPressed: () => openHallFormSheet(context, listingId: listingId),
            icon: const Icon(Icons.add_rounded),
            label: Text(t(locale, ru: 'Добавить зал', kz: 'Зал қосу')),
          ),
        ),
      ],
    );
  }
}

class _HallCard extends ConsumerWidget {
  const _HallCard({required this.listingId, required this.hall});

  final int listingId;
  final ListingHall hall;

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
    return AppCard(
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
          IconButton(
            onPressed: () => _delete(context, ref),
            icon: Icon(
              Icons.delete_outline_rounded,
              size: 18,
              color: colors.error,
            ),
          ),
        ],
      ),
    );
  }
}
