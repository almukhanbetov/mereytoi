import 'package:flutter/material.dart';

import '../core/theme/app_theme.dart';
import '../models/category.dart';
import '../state/locale_provider.dart';
import 'app_chip.dart';
import 'category_picker_sheet.dart';

/// True once the one-time "you can scroll this" nudge has played for the
/// current app run. A plain top-level flag (not per-widget state) so it
/// really only ever plays once per session, even if the Services screen is
/// left and reopened.
bool _categoryLaneNudgeShown = false;

/// The horizontally-scrolling category lane — "Все", every real category
/// from the API, and a trailing "Все категории" chip that opens the full
/// picker sheet. A `Wrap` was tried here and rejected: it read as less
/// current than a proper horizontal lane, and lost the "there's more, keep
/// scrolling" affordance a lane naturally has.
///
/// What makes *this* lane read as modern rather than "an old infinite chip
/// strip": edge fade masks and small chevron hints that track real scroll
/// position (weak/hidden once you can't scroll that way, live once you
/// can), plus a single gentle nudge-and-settle on first appearance so a
/// first-time visitor never has to guess it scrolls.
class CategoryFilterBar extends StatefulWidget {
  const CategoryFilterBar({super.key, required this.categories, required this.activeSlug, required this.locale, required this.onSelect});

  final List<Category> categories;
  final String? activeSlug;
  final AppLocale locale;
  final ValueChanged<String?> onSelect;

  @override
  State<CategoryFilterBar> createState() => _CategoryFilterBarState();
}

class _CategoryFilterBarState extends State<CategoryFilterBar> {
  final _scrollController = ScrollController();
  bool _canScrollLeft = false;
  bool _canScrollRight = false;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateEdges);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _updateEdges();
      _maybeNudge();
    });
  }

  @override
  void dispose() {
    _scrollController.removeListener(_updateEdges);
    _scrollController.dispose();
    super.dispose();
  }

  void _updateEdges() {
    if (!_scrollController.hasClients) return;
    final position = _scrollController.position;
    final canLeft = position.pixels > 4;
    final canRight = position.maxScrollExtent - position.pixels > 4;
    if (canLeft != _canScrollLeft || canRight != _canScrollRight) {
      setState(() {
        _canScrollLeft = canLeft;
        _canScrollRight = canRight;
      });
    }
  }

  /// A short, single nudge-right-and-settle-back — plays once per session,
  /// and only if the lane is actually scrollable (a short category list on
  /// a wide screen has nothing to hint at). Deliberately restrained: one
  /// short trip, no bounce, no repeat.
  Future<void> _maybeNudge() async {
    if (_categoryLaneNudgeShown) return;
    if (!_scrollController.hasClients || _scrollController.position.maxScrollExtent <= 0) return;
    _categoryLaneNudgeShown = true;
    await Future.delayed(const Duration(milliseconds: 350));
    if (!mounted || !_scrollController.hasClients) return;
    await _scrollController.animateTo(26, duration: const Duration(milliseconds: 420), curve: Curves.easeOut);
    if (!mounted || !_scrollController.hasClients) return;
    await _scrollController.animateTo(0, duration: const Duration(milliseconds: 420), curve: Curves.easeInOut);
  }

  @override
  Widget build(BuildContext context) {
    final categories = widget.categories;

    return SizedBox(
      height: 44,
      child: Stack(
        children: [
          ListView.separated(
            controller: _scrollController,
            scrollDirection: Axis.horizontal,
            // Trailing padding widened to clear the (now more visible) right
            // edge hint so it never sits on top of the last chip's tap area.
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.xxl, 0),
            itemCount: categories.length + 2,
            separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.xs),
            itemBuilder: (context, i) {
              if (i == 0) {
                return AppChip(label: t(widget.locale, ru: 'Все', kz: 'Барлығы'), selected: widget.activeSlug == null, onTap: () => widget.onSelect(null));
              }
              if (i == categories.length + 1) {
                return _AllCategoriesChip(
                  locale: widget.locale,
                  onTap: () => showCategoryPickerSheet(context, categories: categories, activeSlug: widget.activeSlug, locale: widget.locale, onSelect: widget.onSelect),
                );
              }
              final category = categories[i - 1];
              return ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 150),
                child: AppChip(label: category.name(widget.locale), selected: widget.activeSlug == category.slug, onTap: () => widget.onSelect(category.slug)),
              );
            },
          ),
          _EdgeHint(alignment: Alignment.centerLeft, visible: _canScrollLeft),
          _EdgeHint(alignment: Alignment.centerRight, visible: _canScrollRight),
        ],
      ),
    );
  }
}

/// A purely decorative "there's more this way" cue: a fade mask into the
/// page background plus a small, semi-transparent chevron. Not a button —
/// it never intercepts a tap or a drag, so the actual scroll gesture
/// underneath is completely unaffected.
class _EdgeHint extends StatelessWidget {
  const _EdgeHint({required this.alignment, required this.visible});

  final Alignment alignment;
  final bool visible;

  bool get _isLeft => alignment == Alignment.centerLeft;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: _isLeft ? 0 : null,
      right: _isLeft ? null : 0,
      top: 0,
      bottom: 0,
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: visible ? 1 : 0,
          duration: const Duration(milliseconds: 180),
          child: Container(
            width: 40,
            // A touch stronger than before so the fade actually reads as a
            // "there's more here" cue rather than disappearing into the
            // page background — still a soft blend, not a hard dark block.
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: _isLeft ? Alignment.centerLeft : Alignment.centerRight,
                end: _isLeft ? Alignment.centerRight : Alignment.centerLeft,
                colors: [
                  AppColors.backgroundPrimary,
                  AppColors.backgroundPrimary.withValues(alpha: 0.6),
                  AppColors.backgroundPrimary.withValues(alpha: 0),
                ],
                stops: const [0, 0.5, 1],
              ),
            ),
            alignment: alignment,
            padding: EdgeInsets.only(left: _isLeft ? 0 : 6, right: _isLeft ? 6 : 0),
            // The chevron itself sits on a small, soft champagne-gold disc —
            // warm and on-brand instead of the previous neutral grey, and
            // visible against the fade without reading as a hard button.
            child: Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(shape: BoxShape.circle, color: AppColors.goldPrimary.withValues(alpha: 0.16)),
              alignment: Alignment.center,
              child: Icon(
                _isLeft ? Icons.chevron_left_rounded : Icons.chevron_right_rounded,
                size: 20,
                color: AppColors.goldPrimary.withValues(alpha: 0.92),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The one chip visually distinct from the category pills — an outlined
/// pill with an icon, always at the end of the lane. Its label never
/// changes; the active-but-not-visible-yet category is simply scrolled to
/// by the user (the lane holds every category, nothing is hidden behind
/// this control the way it would be behind a short "quick filters" row).
class _AllCategoriesChip extends StatelessWidget {
  const _AllCategoriesChip({required this.locale, required this.onTap});

  final AppLocale locale;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.chip), side: const BorderSide(color: AppColors.divider)),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AppRadius.chip),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xxs),
          alignment: Alignment.center,
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.apps_rounded, size: 15, color: AppColors.textSecondary),
              const SizedBox(width: AppSpacing.xxs),
              Text(
                t(locale, ru: 'Все категории', kz: 'Барлық санаттар'),
                style: Theme.of(context).textTheme.labelMedium?.copyWith(color: AppColors.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
