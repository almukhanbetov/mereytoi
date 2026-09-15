import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';

class AppBottomNavItem {
  const AppBottomNavItem({
    required this.icon,
    required this.activeIcon,
    required this.label,
    this.badgeCount = 0,
  });

  final IconData icon;
  final IconData activeIcon;
  final String label;
  final int badgeCount;
}

/// A quiet, native-feeling tab bar: the active tab is simply drawn in gold
/// (icon + label) with a small dot underneath — no filled pill, no heavy
/// rectangle behind the icon. Depth comes from sitting on
/// [MereytoiColors.navigationBackground] above the page, not from a
/// border — on light theme that's a plain white bar (the raised shadow
/// alone separates it from the ivory page), on dark it's the same
/// `backgroundSecondary` this always used.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({
    super.key,
    required this.items,
    required this.currentIndex,
    required this.onTap,
  });

  final List<AppBottomNavItem> items;
  final int currentIndex;
  final ValueChanged<int> onTap;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.mereytoiColors.navigationBackground,
        boxShadow: AppShadows.raised,
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 54,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (var i = 0; i < items.length; i++)
                Expanded(
                  child: _NavTile(
                    item: items[i],
                    selected: i == currentIndex,
                    onTap: () => onTap(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavTile extends StatelessWidget {
  const _NavTile({
    required this.item,
    required this.selected,
    required this.onTap,
  });

  final AppBottomNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    final color = selected ? colors.goldPrimary : colors.textMuted;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // A soft gold-tinted pill behind the active icon — the M3
            // "container indicator" pattern top apps use now, instead of a
            // hard bar underneath that reads as a dated tab-strip cue.
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              curve: Curves.easeOut,
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 3,
              ),
              decoration: BoxDecoration(
                color: selected ? colors.surfaceTint : Colors.transparent,
                borderRadius: BorderRadius.circular(AppRadius.chip),
              ),
              child: Badge(
                label: Text('${item.badgeCount}'),
                isLabelVisible: item.badgeCount > 0,
                backgroundColor: colors.error,
                textStyle: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                ),
                child: Icon(
                  selected ? item.activeIcon : item.icon,
                  color: color,
                  size: 22,
                ),
              ),
            ),
            const SizedBox(height: 3),
            Text(
              item.label,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: color,
                fontSize: 9.5,
                letterSpacing: 0,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
