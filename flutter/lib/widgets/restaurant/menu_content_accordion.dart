import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/listing_menu_section.dart';
import '../../state/locale_provider.dart';

/// Brief section 4 — the menu's sections/items as an accordion, not a flat
/// table. Mirrors RestaurantMenuDetail.jsx's default-open rule (all open
/// when there are 2 sections or fewer, otherwise all start collapsed) but
/// each section is independently toggled via a real `ExpansionTile`.
class MenuContentAccordion extends StatefulWidget {
  const MenuContentAccordion({
    super.key,
    required this.sections,
    required this.locale,
  });

  final List<ListingMenuSection> sections;
  final AppLocale locale;

  @override
  State<MenuContentAccordion> createState() => _MenuContentAccordionState();
}

class _MenuContentAccordionState extends State<MenuContentAccordion> {
  late List<ListingMenuSection> _sorted;
  late Set<int> _openIds;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant MenuContentAccordion oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sections != widget.sections) _resolve();
  }

  void _resolve() {
    _sorted = [...widget.sections]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    _openIds = _sorted.length <= 2 ? _sorted.map((s) => s.id).toSet() : <int>{};
  }

  @override
  Widget build(BuildContext context) {
    if (_sorted.isEmpty) return const SizedBox.shrink();

    // Этап 10Б-1А fix: title and the two toggle actions used to share one
    // Row with no Expanded/Wrap — on a narrow screen (or at a larger
    // system text scale) the row's unconstrained children genuinely don't
    // fit and RenderFlex overflows horizontally. The title now owns its
    // own row; the actions sit below in a Wrap, which reflows to a second
    // line instead of overflowing if it ever still doesn't fit — never
    // clipped, never shrunk to an unreadable size.
    final compactButtonStyle = TextButton.styleFrom(
      minimumSize: const Size(0, 32),
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
      visualDensity: VisualDensity.compact,
      textStyle: Theme.of(context).textTheme.labelMedium,
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t(
            widget.locale,
            ru: 'Состав меню',
            kz: 'Мәзір құрамы',
            en: 'Menu contents',
          ),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.xxs),
        Wrap(
          spacing: AppSpacing.xs,
          children: [
            TextButton(
              style: compactButtonStyle,
              onPressed: () =>
                  setState(() => _openIds = _sorted.map((s) => s.id).toSet()),
              child: Text(
                t(
                  widget.locale,
                  ru: 'Развернуть всё',
                  kz: 'Барлығын жаю',
                  en: 'Expand all',
                ),
              ),
            ),
            TextButton(
              style: compactButtonStyle,
              onPressed: () => setState(() => _openIds = {}),
              child: Text(
                t(
                  widget.locale,
                  ru: 'Свернуть всё',
                  kz: 'Барлығын жию',
                  en: 'Collapse all',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxs),
        ..._sorted.map(
          (section) => _SectionTile(
            section: section,
            locale: widget.locale,
            open: _openIds.contains(section.id),
            onToggle: (open) => setState(() {
              if (open) {
                _openIds.add(section.id);
              } else {
                _openIds.remove(section.id);
              }
            }),
          ),
        ),
      ],
    );
  }
}

class _SectionTile extends StatelessWidget {
  const _SectionTile({
    required this.section,
    required this.locale,
    required this.open,
    required this.onToggle,
  });

  final ListingMenuSection section;
  final AppLocale locale;
  final bool open;
  final ValueChanged<bool> onToggle;

  @override
  Widget build(BuildContext context) {
    final items = [...section.items]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return Container(
      margin: const EdgeInsets.only(bottom: AppSpacing.xs),
      // A plain Material (not Container+BoxDecoration) so this card's own
      // background is also the nearest Material ancestor for the
      // ExpansionTile's internal ListTile — otherwise the tile's ink
      // splash/ripple paints *under* this container's background and is
      // invisible on tap (Flutter warns about exactly this).
      child: Material(
        color: context.mereytoiColors.surface,
        borderRadius: BorderRadius.circular(AppRadius.md),
        clipBehavior: Clip.antiAlias,
        child: Theme(
          data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
          child: ExpansionTile(
            initiallyExpanded: open,
            onExpansionChanged: onToggle,
            tilePadding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
            childrenPadding: const EdgeInsets.fromLTRB(
              AppSpacing.sm,
              0,
              AppSpacing.sm,
              AppSpacing.sm,
            ),
            iconColor: context.mereytoiColors.goldPrimary,
            collapsedIconColor: context.mereytoiColors.textSecondary,
            title: Row(
              children: [
                Expanded(
                  child: Text(
                    section.title(locale),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xxs,
                    vertical: 2,
                  ),
                  decoration: BoxDecoration(
                    color: context.mereytoiColors.surfaceSoft,
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                  ),
                  child: Text(
                    '${items.length}',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
              ],
            ),
            children: items.isEmpty
                ? [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        t(
                          locale,
                          ru: 'Позиции пока не добавлены',
                          kz: 'Позициялар әлі қосылмаған',
                          en: 'No items added yet',
                        ),
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ),
                  ]
                : items
                      .map(
                        (item) => Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Expanded(
                                    child: Text(
                                      item.name(locale),
                                      style: Theme.of(
                                        context,
                                      ).textTheme.bodyLarge,
                                    ),
                                  ),
                                  if (item.quantityText.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(
                                        left: AppSpacing.xs,
                                      ),
                                      child: Text(
                                        item.quantityText,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ),
                                ],
                              ),
                              if (item.description(locale).isNotEmpty)
                                Text(
                                  item.description(locale),
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                            ],
                          ),
                        ),
                      )
                      .toList(),
          ),
        ),
      ),
    );
  }
}
