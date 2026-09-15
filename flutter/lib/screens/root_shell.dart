import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/cart_provider.dart';
import '../state/locale_provider.dart';
import '../widgets/app_bottom_nav.dart';
import 'cart/cart_screen.dart';
import 'events/events_screen.dart';
import 'home/home_screen.dart';
import 'services/services_screen.dart';

/// Which bottom-nav tab is active — a provider (not local State) so any
/// screen can switch tabs programmatically, e.g. Home's "browse services"
/// CTA jumping straight to the Услуги tab.
final selectedTabProvider = StateProvider<int>((ref) => 0);

/// The persistent app shell: bottom navigation for Главная / Услуги /
/// Мой той / Корзина. "Мой той" (Stage 4) rides as its own tab rather than
/// tucked under Profile — there's no Profile tab yet at all (auth isn't
/// part of the original nav spec), and a dedicated tab is the most
/// discoverable option consistent with how Корзина already works. No
/// badge on it: unlike Корзина's real local item count, there's no
/// equally real "pending" number to show here yet (Notifications are a
/// later stage) — never inventing one just to fill the slot.
class RootShell extends ConsumerWidget {
  const RootShell({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final index = ref.watch(selectedTabProvider);
    final locale = ref.watch(localeProvider);
    final cartCount = ref.watch(cartCountProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: index,
          children: const [
            HomeScreen(),
            ServicesScreen(),
            EventsScreen(),
            CartScreen(),
          ],
        ),
      ),
      bottomNavigationBar: AppBottomNav(
        currentIndex: index,
        onTap: (i) => ref.read(selectedTabProvider.notifier).state = i,
        items: [
          AppBottomNavItem(
            icon: Icons.home_outlined,
            activeIcon: Icons.home_rounded,
            label: t(locale, ru: 'Главная', kz: 'Басты'),
          ),
          AppBottomNavItem(
            icon: Icons.grid_view_outlined,
            activeIcon: Icons.grid_view_rounded,
            label: t(locale, ru: 'Услуги', kz: 'Қызметтер'),
          ),
          AppBottomNavItem(
            icon: Icons.celebration_outlined,
            activeIcon: Icons.celebration_rounded,
            label: t(locale, ru: 'Мой той', kz: 'Менің тойым'),
          ),
          AppBottomNavItem(
            icon: Icons.shopping_bag_outlined,
            activeIcon: Icons.shopping_bag_rounded,
            label: t(locale, ru: 'Корзина', kz: 'Себет'),
            badgeCount: cartCount,
          ),
        ],
      ),
    );
  }
}
