import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../models/category.dart';
import '../../state/locale_provider.dart';
import 'services_style.dart';

/// A category's icon, picked from its slug. Slugs are admin-typed and not
/// uniform ("venues", "Photo and Video", "Betashar"), so matching is by
/// keyword; anything unknown gets a neutral sparkle.
IconData servicesCategoryIcon(String? slug) {
  if (slug == null) return Icons.apps_rounded;
  final s = slug.toLowerCase();
  if (s.contains('venue') || s.contains('restaurant')) {
    return Icons.restaurant_rounded;
  }
  if (s.contains('host')) return Icons.mic_rounded;
  if (s.contains('show')) return Icons.local_fire_department_rounded;
  if (s.contains('star')) return Icons.star_rounded;
  if (s.contains('artist') || s.contains('music')) {
    return Icons.music_note_rounded;
  }
  if (s.contains('photo') || s.contains('video')) {
    return Icons.photo_camera_rounded;
  }
  if (s.contains('anima')) return Icons.celebration_rounded;
  if (s.contains('betashar')) return Icons.favorite_rounded;
  if (s.contains('equipment') || s.contains('interactive')) {
    return Icons.videogame_asset_rounded;
  }
  return Icons.auto_awesome_rounded;
}

/// The category picker of the services catalog: a grid of large tiles —
/// «Все» first, then every category from the API. Two columns on phones,
/// three from 520dp. With many categories it starts collapsed to the
/// first [collapsedCount] tiles plus a «Показать все» toggle, so the
/// results stay close to the top; it starts expanded when the active
/// category would otherwise be hidden.
class ServicesCategoryGrid extends StatefulWidget {
  const ServicesCategoryGrid({
    super.key,
    required this.categories,
    required this.activeSlug,
    required this.locale,
    required this.onSelect,
    this.collapsedCount = 6,
  });

  final List<Category> categories;
  final String? activeSlug;
  final AppLocale locale;
  final ValueChanged<String?> onSelect;
  final int collapsedCount;

  @override
  State<ServicesCategoryGrid> createState() => _ServicesCategoryGridState();
}

class _ServicesCategoryGridState extends State<ServicesCategoryGrid> {
  late bool _expanded = _activeIndex() >= widget.collapsedCount;

  /// Position of the active tile in the full list («Все» is 0).
  int _activeIndex() {
    if (widget.activeSlug == null) return 0;
    final i = widget.categories.indexWhere((c) => c.slug == widget.activeSlug);
    return i < 0 ? 0 : i + 1;
  }

  @override
  Widget build(BuildContext context) {
    final locale = widget.locale;
    final total = widget.categories.length + 1;
    // Hiding a single tile behind a toggle isn't worth the extra tap.
    final collapsible = total > widget.collapsedCount + 1;
    final visible = !collapsible || _expanded ? total : widget.collapsedCount;

    return LayoutBuilder(
      builder: (context, constraints) {
        final columns = constraints.maxWidth >= 520 ? 3 : 2;
        // 76 at normal text size; grows only once two lines of the name
        // no longer fit (large system text).
        final textScaler = MediaQuery.textScalerOf(
          context,
        ).clamp(maxScaleFactor: kServicesTileMaxTextScale);
        final tileHeight = math.max(
          76.0,
          textScaler.scale(_kTileFontSizes.first) * _kTileLineHeight * 2 +
              AppSpacing.sm * 2,
        );

        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: EdgeInsets.zero,
              itemCount: visible,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: columns,
                mainAxisExtent: tileHeight,
                crossAxisSpacing: AppSpacing.xs,
                mainAxisSpacing: AppSpacing.xs,
              ),
              itemBuilder: (context, i) {
                if (i == 0) {
                  return ServicesCategoryTile(
                    label: t(locale, ru: 'Все', kz: 'Барлығы', en: 'All'),
                    icon: servicesCategoryIcon(null),
                    selected: widget.activeSlug == null,
                    onTap: () => widget.onSelect(null),
                  );
                }
                final category = widget.categories[i - 1];
                return ServicesCategoryTile(
                  label: category.name(locale),
                  icon: servicesCategoryIcon(category.slug),
                  selected: widget.activeSlug == category.slug,
                  onTap: () => widget.onSelect(category.slug),
                );
              },
            ),
            if (collapsible)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.xs),
                child: Center(
                  child: TextButton.icon(
                    style: TextButton.styleFrom(
                      minimumSize: const Size(48, 40),
                      padding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.sm,
                      ),
                      visualDensity: VisualDensity.compact,
                    ),
                    onPressed: () => setState(() => _expanded = !_expanded),
                    icon: Icon(
                      _expanded
                          ? Icons.keyboard_arrow_up_rounded
                          : Icons.keyboard_arrow_down_rounded,
                      size: 18,
                    ),
                    label: Text(
                      _expanded
                          ? t(
                              locale,
                              ru: 'Свернуть',
                              kz: 'Жию',
                              en: 'Show less',
                            )
                          : t(
                              locale,
                              ru: 'Показать все',
                              kz: 'Барлығын көрсету',
                              en: 'Show all',
                            ),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Tile name sizes, largest first: a name steps down only when it can't
/// fit in two lines without cutting a word.
const _kTileFontSizes = [15.0, 14.0, 13.0, 12.0];
const _kTileMinFontSize = 10.0;

/// Tile names follow the system text size only up to this factor: a tile
/// is ~110dp of text next to its icon, and with Montserrat at a larger
/// system size even "Интерактивное" can't fit whole at any readable size.
/// The rest of the screen still scales fully.
const kServicesTileMaxTextScale = 1.1;
const _kTileLineHeight = 1.25;

/// The largest of [_kTileFontSizes] at which [text] fits in two lines of
/// [maxWidth] with no word broken mid-way — so "Артисты и исполнители"
/// shrinks a step instead of turning into "Артисты и исполнит…". Breaks
/// after "-" and "/" count as word ends, as the line breaker uses them
/// too. If even the smallest step cuts a word (e.g. "Интерактивное" at a
/// large system text size), the size shrinks just enough for the longest
/// word to fit, down to [_kTileMinFontSize]; only below that does the
/// ellipsis take over.
double servicesTileFontSize(
  String text,
  TextStyle style,
  double maxWidth,
  TextScaler textScaler,
  TextDirection textDirection,
) {
  final words = text.split(RegExp(r'\s+|(?<=[-/])')).where((w) => w.isNotEmpty);
  double widestWord(double size) {
    var widest = 0.0;
    for (final w in words) {
      final p = TextPainter(
        text: TextSpan(
          text: w,
          style: style.copyWith(fontSize: size),
        ),
        textDirection: textDirection,
        textScaler: textScaler,
        maxLines: 1,
      )..layout();
      widest = math.max(widest, p.width);
      p.dispose();
    }
    return widest;
  }

  bool fitsTwoLines(double size) {
    final p = TextPainter(
      text: TextSpan(
        text: text,
        style: style.copyWith(fontSize: size),
      ),
      textDirection: textDirection,
      textScaler: textScaler,
      maxLines: 2,
    )..layout(maxWidth: maxWidth);
    final fits = !p.didExceedMaxLines;
    p.dispose();
    return fits;
  }

  for (final size in _kTileFontSizes) {
    if (widestWord(size) <= maxWidth && fitsTwoLines(size)) return size;
  }
  // Width scales linearly with font size, so this is the size at which the
  // longest word exactly fits (rounded down to a half point).
  final smallest = _kTileFontSizes.last;
  final exact = smallest * maxWidth / widestWord(smallest);
  return math.max(_kTileMinFontSize, (exact * 2).floorToDouble() / 2);
}

/// One category tile: an icon badge and the name in up to two lines. The
/// selected tile gets a very light gold tint, a thin gold border and a
/// filled gold badge; its text stays dark and keeps the same weight, so
/// selecting never re-wraps the name.
class ServicesCategoryTile extends StatelessWidget {
  const ServicesCategoryTile({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    final baseStyle =
        (Theme.of(context).textTheme.bodyLarge ?? const TextStyle()).copyWith(
          height: _kTileLineHeight,
          color: colors.textPrimary,
          fontWeight: FontWeight.w600,
        );
    return Semantics(
      button: true,
      selected: selected,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        decoration: servicesCardDecoration(
          context,
          color: selected
              ? colors.goldPrimary.withValues(alpha: 0.06)
              : colors.surface,
          borderColor: selected ? colors.goldPrimary : colors.border,
          borderWidth: selected ? 1.5 : 1,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(kServicesRadius),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: selected
                          ? colors.goldPrimary
                          : colors.goldPrimary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      size: 20,
                      color: selected ? colors.onGold : colors.goldPrimary,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: MediaQuery.withClampedTextScaling(
                      maxScaleFactor: kServicesTileMaxTextScale,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final fontSize = servicesTileFontSize(
                            label,
                            baseStyle,
                            constraints.maxWidth,
                            MediaQuery.textScalerOf(context),
                            Directionality.of(context),
                          );
                          return Text(
                            label,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: baseStyle.copyWith(fontSize: fontSize),
                          );
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
