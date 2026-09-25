import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/manager_chat/manager_chat_context.dart';
import '../../models/listing.dart';
import '../../screens/manager_chat/manager_chat_screen.dart';
import '../../state/locale_provider.dart';

/// «Спросить менеджера» (brief section 9) — the entry point shared by
/// `ServiceDetailScreen` and `RestaurantDetailScreen` (both build their
/// header via `listingHeroSlivers`, so this one button covers both).
/// Carries the same listing context web's plain top-level action bar
/// sends (`listingId/listingName/listingPrice` only — no invented
/// hall/menu identity here; that richer context only ever exists once a
/// hall/menu is actually selected, which this shared header doesn't know
/// about). Auth gating happens inside `ManagerChatScreen` itself, so this
/// button is always tappable — a guest sees the login prompt there, then
/// lands right back in this same chat once signed in.
class AskManagerButton extends StatelessWidget {
  const AskManagerButton({
    super.key,
    required this.listing,
    required this.locale,
    this.hallName,
    this.menuName,
    this.menuPricePerGuest,
    this.guestCount,
    this.estimatedTotal,
  });

  final Listing listing;
  final AppLocale locale;

  /// Этап 10Б-53 — once a restaurant's hall/menu/guest count are actually
  /// chosen, `RestaurantDetailScreen` passes them through here (via
  /// `listingHeroSlivers`'s own matching optional params) so the manager
  /// sees the same calculator snapshot the customer is looking at, not
  /// just "which listing" — `ServiceDetailScreen` (every non-restaurant
  /// category) never has these, so they default to null there.
  final String? hallName;
  final String? menuName;
  final int? menuPricePerGuest;
  final int? guestCount;
  final int? estimatedTotal;

  @override
  Widget build(BuildContext context) {
    return OutlinedButton.icon(
      onPressed: () => Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => ManagerChatScreen(
            chatContext: ManagerChatContext(
              listingId: listing.id,
              listingName: listing.name(locale),
              listingPrice: listing.price,
              hallName: hallName,
              menuName: menuName,
              menuPricePerGuest: menuPricePerGuest,
              guestCount: guestCount,
              estimatedTotal: estimatedTotal,
            ),
          ),
        ),
      ),
      style: OutlinedButton.styleFrom(
        minimumSize: const Size(0, 40),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
      ),
      icon: const Icon(Icons.support_agent_rounded, size: 16),
      label: Text(
        t(
          locale,
          ru: 'Спросить менеджера',
          kz: 'Менеджерден сұрау',
          en: 'Ask the manager',
        ),
      ),
    );
  }
}
