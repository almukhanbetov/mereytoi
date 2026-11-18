import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/error_messages.dart';
import '../../../domain/restaurant/restaurant_category.dart';
import '../../../state/admin_providers.dart';
import '../../../state/listings_provider.dart';
import '../../../state/locale_provider.dart';
import '../../../widgets/app_error_view.dart';
import '../../../widgets/app_loader.dart';
import '../../admin/admin_listing_form_screen.dart';
import 'tabs/address_tab.dart';
import 'tabs/basic_info_tab.dart';
import 'tabs/halls_tab.dart';
import 'tabs/menus_tab.dart';

/// "Управление рестораном" — Основное / Залы / Меню / Адрес, per the
/// brief's own nav sketch. Admin-only: gated by [RestaurantAdminListScreen]
/// (the one entry point that pushes this), never reachable for a guest.
class RestaurantManageScreen extends ConsumerWidget {
  const RestaurantManageScreen({super.key, required this.listingId});

  final int listingId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final listingAsync = ref.watch(listingDetailProvider(listingId));
    // An administrator gets the web admin's own forms here: the complete
    // «Основное» (ServiceForm) and the address with the city and the
    // read-only Google Place ID. An owner keeps the owner's forms.
    final isAdmin = ref.watch(isAdminProvider);

    return DefaultTabController(
      length: 4,
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            listingAsync.valueOrNull?.name(locale) ??
                t(
                  locale,
                  ru: 'Управление рестораном',
                  kz: 'Мейрамхананы басқару',
                ),
          ),
          bottom: TabBar(
            isScrollable: true,
            tabAlignment: TabAlignment.start,
            tabs: [
              Tab(
                text: t(locale, ru: 'Основное', kz: 'Негізгі'),
              ),
              Tab(
                text: t(locale, ru: 'Залы', kz: 'Залдар'),
              ),
              Tab(
                text: t(locale, ru: 'Меню', kz: 'Мәзір'),
              ),
              Tab(
                text: t(locale, ru: 'Адрес', kz: 'Мекенжай'),
              ),
            ],
          ),
        ),
        body: listingAsync.when(
          loading: () => const AppLoader(),
          error: (err, _) => Center(
            child: AppErrorView(
              message: apiErrorMessage(locale, err),
              error: err,
              locale: locale,
              onRetry: () => ref.invalidate(listingDetailProvider(listingId)),
            ),
          ),
          data: (listing) => TabBarView(
            children: [
              if (isAdmin)
                AdminListingForm(
                  key: ValueKey('admin-basic-$listingId'),
                  existing: listing,
                  onSaved: (saved, category) {
                    // Now an ordinary service: nothing left to manage here.
                    if (category != null &&
                        !isRestaurantCategory(category.slug)) {
                      Navigator.of(context).pop();
                    }
                  },
                )
              else
                BasicInfoTab(listing: listing),
              HallsTab(listingId: listingId),
              MenusTab(listingId: listingId),
              AddressTab(listing: listing, admin: isAdmin),
            ],
          ),
        ),
      ),
    );
  }
}
