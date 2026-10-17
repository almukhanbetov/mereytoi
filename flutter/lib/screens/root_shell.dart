import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/cart_provider.dart';
import '../state/locale_provider.dart';
import '../widgets/app_bottom_nav.dart';
import '../widgets/chat/chat_fab.dart';
import 'cart/cart_screen.dart';
import 'events/events_screen.dart';
import 'home/home_screen.dart';
import 'services/services_screen.dart';

/// Which bottom-nav tab is active — a provider (not local State) so any
/// screen can switch tabs programmatically, e.g. Home's "browse services"
/// CTA jumping straight to the Услуги tab.
final selectedTabProvider = StateProvider<int>((ref) => 0);

/// Корзина's tab index — the global chat button is hidden there, since that
/// tab ends in the checkout CTA it would otherwise sit on top of.
const _cartTabIndex = 3;

/// Услуги's tab index.
const _servicesTabIndex = 1;

/// The persistent app shell: bottom navigation for Главная / Услуги /
/// Мой той / Корзина. "Мой той" (Stage 4) rides as its own tab rather than
/// tucked under Profile — there's no Profile tab yet at all (auth isn't
/// part of the original nav spec), and a dedicated tab is the most
/// discoverable option consistent with how Корзина already works. No
/// badge on it: unlike Корзина's real local item count, there's no
/// equally real "pending" number to show here yet (Notifications are a
/// later stage) — never inventing one just to fill the slot.
class RootShell extends ConsumerStatefulWidget {
  const RootShell({super.key});

  @override
  ConsumerState<RootShell> createState() => _RootShellState();
}

class _RootShellState extends ConsumerState<RootShell> {
  // Услуги keeps the chat button hidden at the very top: its first service
  // card sits exactly under the button there. Home deliberately doesn't —
  // the button is the chat's main entry point on the first screen.
  late final _chatFabVisibility = ChatFabVisibility(
    hiddenAtTopTabs: const {_servicesTabIndex},
    initialTab: ref.read(selectedTabProvider),
  );

  @override
  void dispose() {
    _chatFabVisibility.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(
      selectedTabProvider,
      (_, tab) => _chatFabVisibility.selectTab(tab),
    );
    final index = ref.watch(selectedTabProvider);
    final locale = ref.watch(localeProvider);
    final cartCount = ref.watch(cartCountProvider);

    return Scaffold(
      body: SafeArea(
        bottom: false,
        child: IndexedStack(
          index: index,
          children: [
            for (final (i, tab) in const [
              HomeScreen(),
              ServicesScreen(),
              EventsScreen(),
              CartScreen(),
            ].indexed)
              // Each tab's own vertical scrolling drives the chat button's
              // hide-on-scroll-down / show-on-scroll-up behaviour.
              NotificationListener<ScrollNotification>(
                onNotification: (n) => _chatFabVisibility.handleScroll(i, n),
                child: tab,
              ),
          ],
        ),
      ),
      // Global entry to «Сообщения» (manager + provider chats), floated
      // above the bottom nav on the main tabs only — screens pushed on top
      // (chats, checkout, service pages) are separate routes without it.
      // Every tab's scroll view ends with [kChatFabClearance] so its last
      // item can scroll fully above the button; it hides while content
      // scrolls down so it never sits on the cards passing underneath.
      floatingActionButton: index == _cartTabIndex
          ? null
          : AutoHideChatFab(visibility: _chatFabVisibility),
      floatingActionButtonLocation: kChatFabLocation,
      bottomNavigationBar: AppBottomNav(
        currentIndex: index,
        onTap: (i) => ref.read(selectedTabProvider.notifier).state = i,
        items: [
          AppBottomNavItem(
            icon: Icons.home_outlined,
            activeIcon: Icons.home_rounded,
            label: t(locale, ru: 'Главная', kz: 'Басты', en: 'Home'),
          ),
          AppBottomNavItem(
            icon: Icons.grid_view_outlined,
            activeIcon: Icons.grid_view_rounded,
            label: t(locale, ru: 'Услуги', kz: 'Қызметтер', en: 'Services'),
          ),
          AppBottomNavItem(
            icon: Icons.celebration_outlined,
            activeIcon: Icons.celebration_rounded,
            label: t(locale, ru: 'Мой той', kz: 'Менің тойым', en: 'My Event'),
          ),
          AppBottomNavItem(
            icon: Icons.shopping_bag_outlined,
            activeIcon: Icons.shopping_bag_rounded,
            label: t(locale, ru: 'Корзина', kz: 'Себет', en: 'Cart'),
            badgeCount: cartCount,
          ),
        ],
      ),
    );
  }
}
