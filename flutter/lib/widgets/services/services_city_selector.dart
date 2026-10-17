import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../state/locale_provider.dart';
import '../city_selector.dart';
import 'services_style.dart';

/// The services catalog's city filter — one compact row,
/// "📍 Город · Алматы ⌄", in the same card language as the search field
/// and category tiles. Same global city and the same [CitySheet] as Home's
/// pill.
class ServicesCitySelector extends ConsumerWidget {
  const ServicesCitySelector({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    listenForCityValidation(ref);

    final locale = ref.watch(localeProvider);
    final label = watchCityLabel(ref, locale);
    final colors = context.mereytoiColors;
    final textTheme = Theme.of(context).textTheme;
    final caption = t(locale, ru: 'Город', kz: 'Қала', en: 'City');

    return Semantics(
      button: true,
      excludeSemantics: true,
      label: t(
        locale,
        ru: 'Город: $label. Изменить',
        kz: 'Қала: $label. Өзгерту',
        en: 'City: $label. Change',
      ),
      child: DecoratedBox(
        decoration: servicesCardDecoration(context),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(kServicesRadius),
            onTap: () => showCitySheet(context),
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 52),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.sm,
                  vertical: AppSpacing.xs,
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.location_on_rounded,
                      size: 22,
                      color: colors.goldPrimary,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Expanded(
                      child: Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: '$caption  ',
                              style: textTheme.bodyMedium?.copyWith(
                                color: colors.textSecondary,
                              ),
                            ),
                            TextSpan(
                              text: label,
                              style: textTheme.bodyLarge?.copyWith(
                                color: colors.textPrimary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Icon(
                      Icons.keyboard_arrow_down_rounded,
                      size: 22,
                      color: colors.textSecondary,
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
