import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/listing_hall.dart';
import '../../models/listing_menu.dart';
import '../../state/locale_provider.dart';

/// Этап 10Б-Б2 (brief section 4) — "пользователь должен понимать, на
/// каком этапе выбора он находится: Ресторан → Зал → Меню → Гости →
/// Дополнительные услуги → Итог", without a separate screen per step. A
/// compact, horizontally-scrollable strip of chips right under the hero
/// photo: each one reads "done" (gold, filled, shows what was picked) or
/// "pending" (outlined, just the label) — a glance tells you where you
/// are without scrolling back up to re-open a card. Purely a read-only
/// summary; it never changes selection state itself (the brief is
/// explicit that editing stays on the existing cards further down).
class SelectionProgressBar extends StatelessWidget {
  const SelectionProgressBar({
    super.key,
    required this.locale,
    required this.hasHalls,
    required this.selectedHall,
    required this.selectedMenu,
    required this.guests,
    required this.extrasCount,
    required this.hasPrice,
  });

  final AppLocale locale;

  /// Whether this listing has any hall at all — a listing with none skips
  /// straight from "Ресторан" to "Меню", the same way the halls section
  /// above already hides itself entirely when `halls.isEmpty`.
  final bool hasHalls;
  final ListingHall? selectedHall;
  final ListingMenu? selectedMenu;

  /// Null until a menu is selected (guest bounds depend on the menu), so
  /// this step reads "pending" until then even though a default guest
  /// count exists internally.
  final int? guests;
  final int extrasCount;

  /// Whether the calculator has resolved to a real number (some menus are
  /// "по запросу" — price on request — and never get a concrete total).
  final bool hasPrice;

  @override
  Widget build(BuildContext context) {
    final chips = <_StepChipData>[
      _StepChipData(
        label: t(locale, ru: 'Ресторан', kz: 'Мейрамхана', en: 'Restaurant'),
        icon: Icons.storefront_outlined,
        done: true,
      ),
      if (hasHalls)
        _StepChipData(
          label: t(locale, ru: 'Зал', kz: 'Зал', en: 'Hall'),
          icon: Icons.meeting_room_outlined,
          done: selectedHall != null,
          value: selectedHall?.name(locale),
        ),
      _StepChipData(
        label: t(locale, ru: 'Меню', kz: 'Мәзір', en: 'Menu'),
        icon: Icons.restaurant_menu_outlined,
        done: selectedMenu != null,
        value: selectedMenu?.name(locale),
      ),
      _StepChipData(
        label: t(locale, ru: 'Гости', kz: 'Қонақтар', en: 'Guests'),
        icon: Icons.groups_outlined,
        done: guests != null,
        value: guests == null
            ? null
            : '$guests ${t(locale, ru: "чел.", kz: "адам", en: "guests")}',
      ),
      _StepChipData(
        label: t(locale, ru: 'Доп. услуги', kz: 'Қосымша', en: 'Extras'),
        icon: Icons.add_circle_outline_rounded,
        done: extrasCount > 0,
        value: extrasCount > 0 ? '+$extrasCount' : null,
      ),
      _StepChipData(
        label: t(locale, ru: 'Итог', kz: 'Қорытынды', en: 'Total'),
        icon: Icons.receipt_long_outlined,
        done: hasPrice,
      ),
    ];

    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: chips.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
        itemBuilder: (context, i) => _StepChip(data: chips[i]),
      ),
    );
  }
}

class _StepChipData {
  const _StepChipData({
    required this.label,
    required this.icon,
    required this.done,
    this.value,
  });

  final String label;
  final IconData icon;
  final bool done;

  /// The concrete pick to show instead of the generic label once done —
  /// e.g. the hall's own name rather than just "Зал ✓". Falls back to
  /// [label] when null (a done step with nothing nameable, like "Итог").
  final String? value;
}

class _StepChip extends StatelessWidget {
  const _StepChip({required this.data});

  final _StepChipData data;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    final text = data.done ? (data.value ?? data.label) : data.label;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      decoration: BoxDecoration(
        color: data.done ? colors.goldPrimary.withValues(alpha: 0.14) : null,
        border: Border.all(
          color: data.done ? colors.goldPrimary : colors.divider,
        ),
        borderRadius: BorderRadius.circular(AppRadius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            data.done ? Icons.check_circle_rounded : data.icon,
            size: 14,
            color: data.done ? colors.goldPrimary : colors.textMuted,
          ),
          const SizedBox(width: 4),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 120),
            child: Text(
              text,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                color: data.done ? colors.textPrimary : colors.textMuted,
                fontWeight: data.done ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
