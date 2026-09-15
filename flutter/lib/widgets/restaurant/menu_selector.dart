import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../models/listing_menu.dart';
import '../../state/locale_provider.dart';

/// Horizontal menu cards — brief section 3: RU/KZ name, price per guest,
/// min/max guests, valid period, description. Callers pass in the result of
/// `sortedActiveMenus` (then `menusForHall`) — matching
/// `RestaurantMenus.jsx`, which filters to `is_active` menus before
/// rendering anything, an inactive menu never reaches this widget at all.
class MenuSelector extends StatelessWidget {
  const MenuSelector({
    super.key,
    required this.menus,
    required this.selectedMenuId,
    required this.locale,
    required this.onSelect,
  });

  final List<ListingMenu> menus;
  final int? selectedMenuId;
  final AppLocale locale;
  final ValueChanged<ListingMenu> onSelect;

  @override
  Widget build(BuildContext context) {
    if (menus.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 158,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: menus.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) {
          final menu = menus[i];
          return _MenuCard(
            menu: menu,
            selected: menu.id == selectedMenuId,
            locale: locale,
            onTap: () => onSelect(menu),
          );
        },
      ),
    );
  }
}

class _MenuCard extends StatelessWidget {
  const _MenuCard({
    required this.menu,
    required this.selected,
    required this.locale,
    required this.onTap,
  });

  final ListingMenu menu;
  final bool selected;
  final AppLocale locale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hasGuestFact = menu.minGuests != null || menu.maxGuests != null;
    final hasPeriod = menu.validFrom != null || menu.validUntil != null;

    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: 208,
        padding: const EdgeInsets.all(AppSpacing.sm),
        decoration: BoxDecoration(
          color: context.mereytoiColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: selected
                ? context.mereytoiColors.goldPrimary
                : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              menu.name(locale),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall,
            ),
            const SizedBox(height: 4),
            Text(
              '${formatPrice(menu.pricePerGuest)} / ${t(locale, ru: "чел.", kz: "адам")}',
              style: TextStyle(
                color: context.mereytoiColors.goldSoft,
                fontWeight: FontWeight.w700,
                fontSize: 13,
              ),
            ),
            if (menu.description(locale).isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(
                menu.description(locale),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
            const Spacer(),
            if (hasGuestFact)
              _Fact(
                icon: Icons.groups_outlined,
                text:
                    '${menu.minGuests ?? "—"}–${menu.maxGuests ?? "—"} ${t(locale, ru: "гостей", kz: "қонақ")}',
              ),
            if (hasPeriod)
              _Fact(
                icon: Icons.event_outlined,
                text: [
                  if (menu.validFrom != null)
                    'с ${formatMenuDate(menu.validFrom!)}',
                  if (menu.validUntil != null)
                    'по ${formatMenuDate(menu.validUntil!)}',
                ].join(' '),
              ),
          ],
        ),
      ),
    );
  }
}

class _Fact extends StatelessWidget {
  const _Fact({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: Row(
        children: [
          Icon(icon, size: 11, color: context.mereytoiColors.textMuted),
          const SizedBox(width: 3),
          Expanded(
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(fontSize: 10.5),
            ),
          ),
        ],
      ),
    );
  }
}
