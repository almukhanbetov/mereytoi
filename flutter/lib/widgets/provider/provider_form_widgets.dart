import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../models/category.dart';
import '../../state/categories_provider.dart';
import '../../state/locale_provider.dart';
import '../services/services_category_grid.dart';

/// Shared building blocks of the provider forms (onboarding wizard and the
/// add/edit service form), so both read as one premium, light system.

/// Restaurants/venues have their own management flow (halls, menus) and
/// aren't listed in «Мои услуги», so provider forms never offer them.
const kExcludedProviderCategorySlugs = {'venues'};

const kProviderCardRadius = 20.0;

BoxDecoration providerCardDecoration(BuildContext context, {Color? border}) {
  final colors = context.mereytoiColors;
  return BoxDecoration(
    color: colors.surface,
    borderRadius: BorderRadius.circular(kProviderCardRadius),
    border: Border.all(color: border ?? colors.border),
    boxShadow: const [
      BoxShadow(color: Color(0x0F1A1611), blurRadius: 12, offset: Offset(0, 3)),
    ],
  );
}

/// A labelled input in the provider forms' clean card style, with its
/// error shown right under it.
class ProviderTextField extends StatelessWidget {
  const ProviderTextField({
    super.key,
    required this.label,
    required this.controller,
    required this.onChanged,
    this.hint,
    this.keyboardType,
    this.inputFormatters,
    this.maxLength,
    this.minLines = 1,
    this.maxLines = 1,
    this.errorText,
    this.suffixText,
    this.fieldKey,
  });

  final String label;
  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String? hint;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final int? maxLength;
  final int minLines;
  final int maxLines;
  final String? errorText;
  final String? suffixText;
  final Key? fieldKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(16),
      borderSide: BorderSide(color: colors.border),
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
              color: colors.textSecondary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          TextField(
            key: fieldKey,
            controller: controller,
            onChanged: onChanged,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            maxLength: maxLength,
            minLines: minLines,
            maxLines: maxLines,
            style: Theme.of(context).textTheme.bodyLarge,
            decoration: InputDecoration(
              hintText: hint,
              errorText: errorText,
              suffixText: suffixText,
              counterText: '',
              filled: true,
              fillColor: colors.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: 14,
              ),
              border: border,
              enabledBorder: border,
              focusedBorder: border.copyWith(
                borderSide: BorderSide(color: colors.goldPrimary, width: 1.4),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A tappable selection card — icon, current value (or a placeholder),
/// chevron — used for the city and category pickers. A selected value
/// gets a gold border; [errorText] shows under it in red.
class ProviderPickerCard extends StatelessWidget {
  const ProviderPickerCard({
    super.key,
    required this.icon,
    required this.placeholder,
    required this.onTap,
    this.value,
    this.errorText,
    this.semanticLabel,
    this.tapKey,
  });

  final IconData icon;
  final String placeholder;
  final String? value;
  final String? errorText;
  final String? semanticLabel;
  final VoidCallback onTap;
  final Key? tapKey;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    final textTheme = Theme.of(context).textTheme;
    final selected = value != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Semantics(
          button: true,
          label: semanticLabel,
          child: DecoratedBox(
            decoration: providerCardDecoration(
              context,
              border: errorText != null
                  ? colors.error
                  : selected
                  ? colors.goldPrimary
                  : null,
            ),
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                key: tapKey,
                borderRadius: BorderRadius.circular(kProviderCardRadius),
                onTap: onTap,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 72),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md,
                      vertical: AppSpacing.sm,
                    ),
                    child: Row(
                      children: [
                        Container(
                          width: 44,
                          height: 44,
                          decoration: BoxDecoration(
                            color: colors.goldPrimary.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(icon, color: colors.goldPrimary),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: Text(
                            value ?? placeholder,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: selected
                                  ? colors.textPrimary
                                  : colors.textSecondary,
                            ),
                          ),
                        ),
                        Icon(
                          Icons.keyboard_arrow_down_rounded,
                          color: colors.textSecondary,
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
        if (errorText != null)
          Padding(
            padding: const EdgeInsets.only(left: AppSpacing.sm, top: 6),
            child: Text(
              errorText!,
              style: textTheme.bodySmall?.copyWith(color: colors.error),
            ),
          ),
      ],
    );
  }
}

/// The provider-category grid in the same tiles/icons as the onboarding —
/// two columns, venues excluded, the selected one highlighted in gold.
class ProviderCategoryGrid extends StatelessWidget {
  const ProviderCategoryGrid({
    super.key,
    required this.categories,
    required this.selectedId,
    required this.locale,
    required this.onSelect,
  });

  final List<Category> categories;
  final int? selectedId;
  final AppLocale locale;
  final ValueChanged<Category> onSelect;

  @override
  Widget build(BuildContext context) {
    final items = categories
        .where((c) => !kExcludedProviderCategorySlugs.contains(c.slug))
        .toList();
    final textScaler = MediaQuery.textScalerOf(
      context,
    ).clamp(maxScaleFactor: kServicesTileMaxTextScale);
    final height = math.max(76.0, textScaler.scale(15) * 1.25 * 2 + 24);
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: EdgeInsets.zero,
      itemCount: items.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: height,
        mainAxisSpacing: AppSpacing.xs,
        crossAxisSpacing: AppSpacing.xs,
      ),
      itemBuilder: (context, i) {
        final c = items[i];
        return ServicesCategoryTile(
          label: c.name(locale),
          icon: servicesCategoryIcon(c.slug),
          selected: selectedId == c.id,
          onTap: () => onSelect(c),
        );
      },
    );
  }
}

/// Bottom sheet with [ProviderCategoryGrid]; returns the tapped category
/// (null when dismissed).
Future<Category?> showProviderCategoryPicker(
  BuildContext context, {
  int? selectedId,
}) {
  return showModalBottomSheet<Category>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _CategoryPickerSheet(selectedId: selectedId),
  );
}

class _CategoryPickerSheet extends ConsumerWidget {
  const _CategoryPickerSheet({this.selectedId});

  final int? selectedId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final colors = context.mereytoiColors;
    final categories = ref.watch(categoriesProvider);
    final mq = MediaQuery.of(context);
    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: mq.size.height * 0.85),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: colors.surfaceElevated,
          borderRadius: const BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
        ),
        child: ListView(
          shrinkWrap: true,
          padding: EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.xs,
            AppSpacing.md,
            mq.padding.bottom + AppSpacing.lg,
          ),
          children: [
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
            const SizedBox(height: AppSpacing.md),
            Text(
              t(
                locale,
                ru: 'Выберите категорию',
                kz: 'Санатты таңдаңыз',
                en: 'Select a category',
              ),
              style: Theme.of(context).textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.md),
            categories.when(
              loading: () => const Padding(
                padding: EdgeInsets.all(AppSpacing.xl),
                child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
              ),
              error: (_, _) => Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: OutlinedButton(
                  onPressed: () => ref.invalidate(categoriesProvider),
                  child: Text(
                    t(locale, ru: 'Повторить', kz: 'Қайталау', en: 'Retry'),
                  ),
                ),
              ),
              data: (list) => ProviderCategoryGrid(
                categories: list,
                selectedId: selectedId,
                locale: locale,
                onSelect: (c) => Navigator.of(context).pop(c),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
