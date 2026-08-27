import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../state/categories_provider.dart';
import '../../state/locale_provider.dart';
import '../../widgets/app_back_button.dart';
import '../../widgets/app_error_view.dart';
import '../../widgets/app_skeleton.dart';
import '../../widgets/category_card.dart';
import '../../widgets/fade_slide_in.dart';
import '../services/services_screen.dart';

/// The full category grid — GET /api/categories, big premium tiles with a
/// gradient overlay. Reached from Home's "Все" link. Tapping a tile opens
/// the catalog pre-filtered to that category, same as tapping a category
/// card on the site's homepage.
class CategoriesScreen extends ConsumerWidget {
  const CategoriesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final categories = ref.watch(categoriesProvider);

    return Scaffold(
      // Only ever pushed on top of another screen (never a bottom-nav tab
      // root), but kept conditional on `canPop` anyway so this stays
      // correct if that ever changes — same rule the default back button
      // follows, just with the app's own back-button styling.
      appBar: AppBar(
        title: Text(t(locale, ru: 'Категории', kz: 'Санаттар')),
        leading: Navigator.canPop(context) ? const AppBackButton() : null,
      ),
      body: categories.when(
        loading: () => const AppGridSkeleton(itemCount: 6, aspectRatio: 0.92),
        error: (err, _) => AppErrorView(message: apiErrorMessage(locale, err), locale: locale, onRetry: () => ref.invalidate(categoriesProvider)),
        data: (list) {
          if (list.isEmpty) {
            return Center(child: Text(t(locale, ru: 'Категории скоро появятся', kz: 'Санаттар жақында қосылады'), style: Theme.of(context).textTheme.bodyMedium));
          }
          return GridView.builder(
            padding: const EdgeInsets.all(AppSpacing.lg),
            itemCount: list.length,
            gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              mainAxisSpacing: AppSpacing.md,
              crossAxisSpacing: AppSpacing.md,
              childAspectRatio: 0.92,
            ),
            itemBuilder: (context, i) {
              final category = list[i];
              return FadeSlideIn(
                index: i,
                child: CategoryCard(
                  category: category,
                  locale: locale,
                  onTap: () => Navigator.of(context).push(
                    MaterialPageRoute(builder: (_) => ServicesScreen(initialCategorySlug: category.slug)),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
