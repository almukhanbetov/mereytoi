import 'package:flutter/material.dart';

import '../core/config/api_config.dart';
import '../core/theme/app_theme.dart';
import '../models/category.dart';
import '../state/locale_provider.dart';
import 'network_image_box.dart';

/// The full category picker — a draggable sheet with every category as a
/// 2-column photo/icon grid. This is what replaced the old infinite
/// horizontally-scrolling chip strip on the Services screen: instead of
/// hiding most categories off-screen with no signal there's more, every
/// option is laid out at once in a scannable grid, the way Airbnb/Booking/
/// Kaspi-style apps handle a filter with more than a handful of options.
Future<void> showCategoryPickerSheet(
  BuildContext context, {
  required List<Category> categories,
  required String? activeSlug,
  required AppLocale locale,
  required ValueChanged<String?> onSelect,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (context) => _CategoryPickerSheet(
      categories: categories,
      activeSlug: activeSlug,
      locale: locale,
      onSelect: onSelect,
    ),
  );
}

class _CategoryPickerSheet extends StatefulWidget {
  const _CategoryPickerSheet({required this.categories, required this.activeSlug, required this.locale, required this.onSelect});

  final List<Category> categories;
  final String? activeSlug;
  final AppLocale locale;
  final ValueChanged<String?> onSelect;

  @override
  State<_CategoryPickerSheet> createState() => _CategoryPickerSheetState();
}

class _CategoryPickerSheetState extends State<_CategoryPickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _pick(String? slug) {
    widget.onSelect(slug);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty ? widget.categories : widget.categories.where((c) => c.name(widget.locale).toLowerCase().contains(query)).toList();
    final showAllTile = query.isEmpty;

    // 65–85% of the screen, draggable within that band only — big enough to
    // browse comfortably, never taller than a hand can reach.
    return DraggableScrollableSheet(
      initialChildSize: 0.75,
      minChildSize: 0.65,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) {
        return DecoratedBox(
          decoration: const BoxDecoration(
            color: AppColors.surfaceElevated,
            borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
          ),
          child: SafeArea(
            top: false,
            child: Column(
              children: [
                const SizedBox(height: AppSpacing.xs),
                Container(width: 36, height: 4, decoration: BoxDecoration(color: AppColors.divider, borderRadius: BorderRadius.circular(AppRadius.chip))),
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.sm, AppSpacing.sm),
                  child: Row(
                    children: [
                      Expanded(child: Text(t(widget.locale, ru: 'Категории', kz: 'Санаттар'), style: Theme.of(context).textTheme.titleLarge)),
                      IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded)),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.sm),
                  child: SizedBox(
                    height: 44,
                    child: TextField(
                      controller: _searchController,
                      onChanged: (v) => setState(() => _query = v),
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlignVertical: TextAlignVertical.center,
                      decoration: InputDecoration(
                        isDense: true,
                        hintText: t(widget.locale, ru: 'Поиск категории', kz: 'Санатты іздеу'),
                        prefixIcon: const Icon(Icons.search_rounded, color: AppColors.textSecondary, size: 18),
                        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: 0),
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: filtered.isEmpty && !showAllTile
                      ? Center(
                          child: Text(
                            t(widget.locale, ru: 'Ничего не найдено', kz: 'Ештеңе табылмады'),
                            style: Theme.of(context).textTheme.bodyMedium,
                          ),
                        )
                      : GridView.builder(
                          controller: scrollController,
                          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
                          itemCount: filtered.length + (showAllTile ? 1 : 0),
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 2,
                            mainAxisSpacing: AppSpacing.sm,
                            crossAxisSpacing: AppSpacing.sm,
                            mainAxisExtent: 132,
                          ),
                          itemBuilder: (context, i) {
                            if (showAllTile && i == 0) {
                              return _CategoryGridTile(
                                label: t(widget.locale, ru: 'Все услуги', kz: 'Барлық қызметтер'),
                                selected: widget.activeSlug == null,
                                image: const _AllIcon(),
                                onTap: () => _pick(null),
                              );
                            }
                            final category = filtered[i - (showAllTile ? 1 : 0)];
                            return _CategoryGridTile(
                              label: category.name(widget.locale),
                              selected: widget.activeSlug == category.slug,
                              image: NetworkImageBox(url: ApiConfig.mediaUrl(category.imageUrl), borderRadius: 0, fallbackIcon: Icons.celebration_outlined),
                              onTap: () => _pick(category.slug),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _AllIcon extends StatelessWidget {
  const _AllIcon();

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [AppColors.surface, AppColors.backgroundSecondary]),
      ),
      alignment: Alignment.center,
      child: const Icon(Icons.apps_rounded, color: AppColors.goldPrimary, size: 22),
    );
  }
}

/// A grid card: a fixed-height photo/icon block on top, name below — never a
/// full-bleed photo with overlaid text (that's [CategoryCard]'s job on
/// Home). Unselected sits on the same quiet `surface` tone with no border;
/// selected gets a restrained gold tint + hairline border + a small check
/// badge on the image, never a heavy glow.
class _CategoryGridTile extends StatelessWidget {
  const _CategoryGridTile({required this.label, required this.selected, required this.image, required this.onTap});

  final String label;
  final bool selected;
  final Widget image;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.goldPrimary.withValues(alpha: 0.08) : AppColors.surface,
      borderRadius: BorderRadius.circular(AppRadius.md),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.md),
        child: Container(
          padding: const EdgeInsets.all(AppSpacing.sm),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AppRadius.md),
            border: Border.all(color: selected ? AppColors.goldPrimary : Colors.transparent, width: 1.3),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(AppRadius.sm),
                child: SizedBox(
                  width: double.infinity,
                  height: 64,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      image,
                      if (selected)
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            width: 20,
                            height: 20,
                            decoration: const BoxDecoration(color: AppColors.goldPrimary, shape: BoxShape.circle),
                            child: const Icon(Icons.check_rounded, size: 13, color: AppColors.onGold),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(color: selected ? AppColors.goldSoft : AppColors.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
