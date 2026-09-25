import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/utils/error_messages.dart';
import '../../../state/listings_provider.dart';
import '../../../state/locale_provider.dart';
import '../../../widgets/app_error_view.dart';
import '../../../widgets/app_loader.dart';
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
              locale: locale,
              onRetry: () => ref.invalidate(listingDetailProvider(listingId)),
            ),
          ),
          data: (listing) => TabBarView(
            children: [
              BasicInfoTab(listing: listing),
              HallsTab(listingId: listingId),
              MenusTab(listingId: listingId),
              AddressTab(listing: listing),
            ],
          ),
        ),
      ),
    );
  }
}
