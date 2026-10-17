import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import '../core/utils/error_messages.dart';
import '../models/city.dart';
import '../state/city_provider.dart';
import '../state/locale_provider.dart';

String allCitiesLabel(AppLocale locale) =>
    t(locale, ru: 'Все города', kz: 'Барлық қалалар', en: 'All cities');

/// "📍 Алматы ▾" — the compact, rounded city pill shown on Home (under the
/// app bar) and the services catalog. Tapping it opens [CitySheet].
///
/// It is also where a saved city ID gets checked against the backend's
/// directory once the list arrives ([SelectedCityNotifier.retainOnly]):
/// this pill is on the first screen, so it's mounted whenever the city
/// list loads.
class CitySelectorButton extends ConsumerWidget {
  const CitySelectorButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.listen<AsyncValue<List<City>>>(citiesProvider, (_, next) {
      final cities = next.valueOrNull;
      if (cities != null) {
        ref.read(selectedCityIdProvider.notifier).retainOnly(cities);
      }
    });

    final locale = ref.watch(localeProvider);
    final selectedId = ref.watch(selectedCityIdProvider);
    final city = ref.watch(selectedCityProvider);
    final colors = context.mereytoiColors;

    final label = selectedId == null
        ? allCitiesLabel(locale)
        // A saved ID whose list hasn't loaded yet — never show a stale or
        // wrong name, just the generic "Город".
        : city?.name(locale) ?? t(locale, ru: 'Город', kz: 'Қала', en: 'City');

    return Semantics(
      button: true,
      excludeSemantics: true,
      label: t(
        locale,
        ru: 'Город: $label. Изменить',
        kz: 'Қала: $label. Өзгерту',
        en: 'City: $label. Change',
      ),
      child: Material(
        color: colors.surface,
        shape: StadiumBorder(side: BorderSide(color: colors.border)),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: () => showCitySheet(context),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.location_on_rounded,
                    size: 18,
                    color: colors.goldPrimary,
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Flexible(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: colors.textPrimary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xxs),
                  Icon(
                    Icons.keyboard_arrow_down_rounded,
                    size: 20,
                    color: colors.textSecondary,
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

Future<void> showCitySheet(BuildContext context) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const CitySheet(),
  );
}

/// "Выберите город": drag handle, title, local search, "Все города" first,
/// then the backend's cities. Search filters the already-loaded list
/// (RU/KZ/EN names) — no request per keystroke. Picking a row saves it and
/// closes the sheet.
class CitySheet extends ConsumerStatefulWidget {
  const CitySheet({super.key});

  @override
  ConsumerState<CitySheet> createState() => _CitySheetState();
}

class _CitySheetState extends ConsumerState<CitySheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _select(int? cityId) {
    ref.read(selectedCityIdProvider.notifier).selectCity(cityId);
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final selectedId = ref.watch(selectedCityIdProvider);
    final cities = ref.watch(citiesProvider);
    final colors = context.mereytoiColors;
    final mq = MediaQuery.of(context);

    // A fixed height (not content-sized) so the sheet doesn't jump while
    // the list shrinks under search; with the keyboard up it shrinks to
    // the space above it, so results are never hidden behind the keyboard.
    final keyboard = mq.viewInsets.bottom;
    final height = math.min(
      mq.size.height * 0.75,
      (mq.size.height - keyboard - mq.padding.top) * 0.95,
    );

    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: SizedBox(
        height: height,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: colors.surfaceElevated,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(AppRadius.lg),
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: AppSpacing.xs),
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colors.divider,
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.lg,
                  AppSpacing.md,
                  AppSpacing.lg,
                  AppSpacing.sm,
                ),
                child: Text(
                  t(
                    locale,
                    ru: 'Выберите город',
                    kz: 'Қаланы таңдаңыз',
                    en: 'Select city',
                  ),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
                child: SizedBox(
                  height: 44,
                  child: TextField(
                    controller: _searchController,
                    onChanged: (v) => setState(() => _query = v),
                    textInputAction: TextInputAction.search,
                    style: Theme.of(context).textTheme.bodyLarge,
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      isDense: true,
                      hintText: t(
                        locale,
                        ru: 'Поиск города',
                        kz: 'Қаланы іздеу',
                        en: 'Search city',
                      ),
                      prefixIcon: Icon(
                        Icons.search_rounded,
                        color: colors.textSecondary,
                        size: 18,
                      ),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.md,
                        vertical: 0,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Expanded(
                child: _buildList(
                  context,
                  locale: locale,
                  selectedId: selectedId,
                  cities: cities,
                  bottomPadding: mq.padding.bottom + AppSpacing.md,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildList(
    BuildContext context, {
    required AppLocale locale,
    required int? selectedId,
    required AsyncValue<List<City>> cities,
    required double bottomPadding,
  }) {
    final searching = _query.trim().isNotEmpty;
    final matches = (cities.valueOrNull ?? const <City>[])
        .where((c) => c.matches(_query))
        .toList();

    final children = <Widget>[
      // "Все города" is a reset, not a search result — shown only while
      // the search box is empty.
      if (!searching)
        _CityTile(
          label: allCitiesLabel(locale),
          icon: Icons.public_rounded,
          selected: selectedId == null,
          onTap: () => _select(null),
        ),
      ...cities.when(
        loading: () => [
          const Padding(
            padding: EdgeInsets.all(AppSpacing.xl),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
        ],
        error: (err, _) => [
          _SheetMessage(
            text: apiErrorMessage(locale, err),
            actionLabel: t(
              locale,
              ru: 'Повторить',
              kz: 'Қайталау',
              en: 'Retry',
            ),
            onAction: () => ref.invalidate(citiesProvider),
          ),
        ],
        data: (_) => [
          if (matches.isEmpty && searching)
            _SheetMessage(
              text: t(
                locale,
                ru: 'Ничего не найдено',
                kz: 'Ештеңе табылмады',
                en: 'Nothing found',
              ),
            ),
          for (final city in matches)
            _CityTile(
              label: city.name(locale),
              icon: Icons.location_on_outlined,
              selected: city.id == selectedId,
              onTap: () => _select(city.id),
            ),
        ],
      ),
    ];

    return ListView(
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: EdgeInsets.fromLTRB(
        AppSpacing.sm,
        0,
        AppSpacing.sm,
        bottomPadding,
      ),
      children: children,
    );
  }
}

class _CityTile extends StatelessWidget {
  const _CityTile({
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
    return Semantics(
      selected: selected,
      button: true,
      child: Material(
        color: selected
            ? colors.goldPrimary.withValues(alpha: 0.12)
            : Colors.transparent,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              child: Row(
                children: [
                  Icon(
                    icon,
                    size: 20,
                    color: selected ? colors.goldPrimary : colors.textSecondary,
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: selected
                            ? colors.goldPrimary
                            : colors.textPrimary,
                        fontWeight: selected
                            ? FontWeight.w700
                            : FontWeight.w500,
                      ),
                    ),
                  ),
                  if (selected) ...[
                    const SizedBox(width: AppSpacing.xs),
                    Icon(
                      Icons.check_rounded,
                      key: const ValueKey('city-selected-check'),
                      size: 20,
                      color: colors.goldPrimary,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _SheetMessage extends StatelessWidget {
  const _SheetMessage({required this.text, this.actionLabel, this.onAction});

  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xl,
      ),
      child: Column(
        children: [
          Text(
            text,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: context.mereytoiColors.textSecondary,
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(onPressed: onAction, child: Text(actionLabel!)),
          ],
        ],
      ),
    );
  }
}
