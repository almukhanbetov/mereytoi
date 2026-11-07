import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/api_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/format.dart';
import '../../../models/listing.dart';
import '../../../state/categories_provider.dart';
import '../../../state/listings_provider.dart';
import '../../../state/locale_provider.dart';
import '../../../state/provider_provider.dart';
import '../../../widgets/admin/form_sheet_scaffold.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_error_view.dart';
import '../../../widgets/app_icon_badge.dart';
import '../../../widgets/app_skeleton.dart';
import '../../../widgets/network_image_box.dart';
import 'widgets/provider_service_form_sheet.dart';

/// "Мои услуги" (Этап 11) — every listing the caller owns via
/// `ListingManager`, same server-side scoping `RestaurantAdminListScreen`
/// already relies on (`GET /api/users/me/listings`), filtered here to
/// non-"venues" categories: a restaurant/venue listing (halls/menus)
/// already has its own richer management flow
/// ([RestaurantAdminListScreen]/`RestaurantManageScreen`), reachable the
/// same way regardless of which screen created the listing — this screen
/// deliberately doesn't duplicate that, only plain single-price services.
class MyServicesScreen extends ConsumerWidget {
  const MyServicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final listingsAsync = ref.watch(myListingsProvider);
    final categoriesAsync = ref.watch(categoriesProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          t(
            locale,
            ru: 'Мои услуги',
            kz: 'Менің қызметтерім',
            en: 'My services',
          ),
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        key: const ValueKey('my-services-add'),
        onPressed: () => openProviderServiceForm(context),
        // Этап 11E QA finding: without an explicit color this rendered
        // as Material 3's default purple FAB — jarring against the
        // site's own gold/dark theme everywhere else.
        backgroundColor: context.mereytoiColors.goldPrimary,
        foregroundColor: context.mereytoiColors.onGold,
        icon: const Icon(Icons.add_rounded),
        label: Text(
          t(
            locale,
            ru: 'Добавить услугу',
            kz: 'Қызмет қосу',
            en: 'Add service',
          ),
        ),
      ),
      body: listingsAsync.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: const [
            AppSkeleton(height: 72, borderRadius: AppRadius.lg),
            SizedBox(height: AppSpacing.sm),
            AppSkeleton(height: 72, borderRadius: AppRadius.lg),
          ],
        ),
        error: (err, _) => Center(
          child: AppErrorView(
            message: apiErrorMessage(locale, err),
            error: err,
            locale: locale,
            onRetry: () => ref.invalidate(myListingsProvider),
          ),
        ),
        data: (all) {
          final venueCategoryIds = categoriesAsync.maybeWhen(
            data: (categories) => categories
                .where((c) => c.slug == 'venues')
                .map((c) => c.id)
                .toSet(),
            orElse: () => const <int>{},
          );
          final listings = all
              .where((l) => !venueCategoryIds.contains(l.categoryId))
              .toList();

          if (listings.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppIconBadge(icon: Icons.design_services_outlined),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      t(
                        locale,
                        ru: 'Пока нет ни одной услуги',
                        kz: 'Әзірге қызмет жоқ',
                        en: 'No services yet',
                      ),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ],
                ),
              ),
            );
          }

          return RefreshIndicator(
            color: context.mereytoiColors.goldPrimary,
            backgroundColor: context.mereytoiColors.surfaceElevated,
            onRefresh: () => ref.refresh(myListingsProvider.future),
            child: ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.lg,
                AppSpacing.lg,
                96,
              ),
              itemCount: listings.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, i) => _ServiceRow(listing: listings[i]),
            ),
          );
        },
      ),
    );
  }
}

class _ServiceRow extends ConsumerWidget {
  const _ServiceRow({required this.listing});

  final Listing listing;

  Future<void> _toggleActive(BuildContext context, WidgetRef ref) async {
    final locale = ref.read(localeProvider);
    // Hiding takes the service out of the public catalog: never on a stray
    // tap (the chip sits where people tap to open the service).
    if (listing.isActive && !await _confirmHide(context, locale)) return;
    if (!context.mounted) return;
    try {
      await ref
          .read(providerActionsProvider)
          .setListingActive(listing.id, !listing.isActive);
    } catch (err) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiErrorMessage(locale, err))));
      }
    }
  }

  Future<bool> _confirmHide(BuildContext context, AppLocale locale) async {
    final hide = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(
          t(
            locale,
            ru: 'Скрыть услугу?',
            kz: 'Қызметті жасыру керек пе?',
            en: 'Hide this service?',
          ),
        ),
        content: Text(
          t(
            locale,
            ru:
                'Клиенты перестанут видеть её в каталоге. Вернуть её можно '
                'в любой момент.',
            kz:
                'Клиенттер оны каталогта көрмейді. Кез келген уақытта қайта '
                'жариялай аласыз.',
            en:
                'Clients will no longer see it in the catalog. You can '
                'publish it again at any time.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(t(locale, ru: 'Отмена', kz: 'Болдырмау', en: 'Cancel')),
          ),
          TextButton(
            key: const ValueKey('hide-service-confirm'),
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(t(locale, ru: 'Скрыть', kz: 'Жасыру', en: 'Hide')),
          ),
        ],
      ),
    );
    return hide ?? false;
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final locale = ref.read(localeProvider);
    final confirmed = await ConfirmDeleteSheet.show(
      context,
      title: t(
        locale,
        ru: 'Удалить «${listing.name(locale)}»?',
        kz: '«${listing.name(locale)}» жоюды растайсыз ба?',
        en: 'Delete "${listing.name(locale)}"?',
      ),
      confirmLabel: t(locale, ru: 'Удалить', kz: 'Жою', en: 'Delete'),
      cancelLabel: t(locale, ru: 'Отмена', kz: 'Бас тарту', en: 'Cancel'),
    );
    if (!confirmed) return;
    try {
      await ref.read(providerActionsProvider).deleteListing(listing.id);
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

    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: InkWell(
              key: ValueKey('my-service-${listing.id}'),
              borderRadius: BorderRadius.circular(AppRadius.md),
              // Tapping the service opens it for editing.
              onTap: () => openProviderServiceForm(context, existing: listing),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                    child: SizedBox(
                      width: 52,
                      height: 52,
                      child: NetworkImageBox(
                        url: ApiConfig.mediaUrl(listing.coverImage),
                        fallbackIcon: Icons.design_services_outlined,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          listing.name(locale),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Text(
                          listing.price > 0
                              ? formatPrice(listing.price)
                              : t(
                                  locale,
                                  ru: 'По запросу',
                                  kz: 'Сұраныс бойынша',
                                  en: 'On request',
                                ),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: AppSpacing.xxs),
                        Wrap(
                          spacing: AppSpacing.xs,
                          children: [
                            ActionChip(
                              key: ValueKey('service-status-${listing.id}'),
                              avatar: Icon(
                                listing.isActive
                                    ? Icons.visibility_outlined
                                    : Icons.visibility_off_outlined,
                                size: 16,
                                color: listing.isActive
                                    ? context.mereytoiColors.success
                                    : context.mereytoiColors.error,
                              ),
                              label: Text(
                                listing.isActive
                                    ? t(
                                        locale,
                                        ru: 'Опубликовано',
                                        kz: 'Жарияланды',
                                        en: 'Published',
                                      )
                                    // Hidden says what it means for clients.
                                    : t(
                                        locale,
                                        ru: 'Скрыто — не видно клиентам',
                                        kz: 'Жасырын — клиенттерге көрінбейді',
                                        en: 'Hidden — clients can’t see it',
                                      ),
                              ),
                              onPressed: () => _toggleActive(context, ref),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          PopupMenuButton<String>(
            onSelected: (value) {
              if (value == 'edit') {
                openProviderServiceForm(context, existing: listing);
              } else if (value == 'delete') {
                _delete(context, ref);
              }
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                value: 'edit',
                child: Text(
                  t(locale, ru: 'Изменить', kz: 'Өзгерту', en: 'Edit'),
                ),
              ),
              PopupMenuItem(
                value: 'delete',
                child: Text(t(locale, ru: 'Удалить', kz: 'Жою', en: 'Delete')),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
