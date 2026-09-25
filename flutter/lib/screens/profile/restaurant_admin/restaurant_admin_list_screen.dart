import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/config/api_config.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/error_messages.dart';
import '../../../state/listings_provider.dart';
import '../../../state/locale_provider.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_error_view.dart';
import '../../../widgets/app_icon_badge.dart';
import '../../../widgets/app_skeleton.dart';
import '../../../widgets/network_image_box.dart';
import 'restaurant_manage_screen.dart';

/// "Мои рестораны" / "Управление ресторанами" — every listing the caller
/// may manage, via `GET /api/users/me/listings` (see
/// [ListingHandler.MyListings] on the backend and [myListingsProvider]
/// here): a global admin sees every listing regardless of category or
/// active state; an owner/manager sees only the listings they're assigned
/// to via `ListingManager`. Server-side, not just hidden buttons — an
/// unrelated user can't reach another listing's management screens even
/// by guessing an id (`RequireListingAccess` re-checks on every mutation).
class RestaurantAdminListScreen extends ConsumerWidget {
  const RestaurantAdminListScreen({super.key, this.title});

  /// Profile passes a role-appropriate title ("Мои рестораны" for an
  /// owner/manager, "Управление ресторанами" for a global admin); falls
  /// back to a neutral label if opened without one.
  final String? title;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final listingsAsync = ref.watch(myListingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(
          title ??
              t(
                locale,
                ru: 'Рестораны и локации',
                kz: 'Мейрамханалар мен локациялар',
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
            locale: locale,
            onRetry: () => ref.invalidate(myListingsProvider),
          ),
        ),
        data: (listings) {
          if (listings.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppIconBadge(icon: Icons.storefront_outlined),
                    const SizedBox(height: AppSpacing.md),
                    Text(
                      t(
                        locale,
                        ru: 'Ресторанов пока нет',
                        kz: 'Мейрамханалар әлі жоқ',
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
              padding: const EdgeInsets.all(AppSpacing.lg),
              itemCount: listings.length,
              separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.sm),
              itemBuilder: (context, i) {
                final listing = listings[i];
                return GestureDetector(
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) =>
                          RestaurantManageScreen(listingId: listing.id),
                    ),
                  ),
                  child: AppCard(
                    padding: const EdgeInsets.all(AppSpacing.xs),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(AppRadius.sm),
                          child: SizedBox(
                            width: 52,
                            height: 52,
                            child: NetworkImageBox(
                              url: ApiConfig.mediaUrl(listing.coverImage),
                              fallbackIcon: Icons.storefront_outlined,
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
                                '${t(locale, ru: "Залов", kz: "Залдар")}: ${listing.hallCount ?? 0} · '
                                '${t(locale, ru: "Меню", kz: "Мәзір")}: ${listing.menuCount ?? 0}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right_rounded,
                          color: context.mereytoiColors.textMuted,
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
