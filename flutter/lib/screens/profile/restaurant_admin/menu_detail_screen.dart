import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/format.dart';
import '../../../models/listing_menu.dart';
import '../../../models/listing_menu_extra.dart';
import '../../../models/listing_menu_section.dart';
import '../../../state/listing_management_actions.dart';
import '../../../state/listings_provider.dart';
import '../../../state/locale_provider.dart';
import '../../../widgets/admin/form_sheet_scaffold.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_error_view.dart';
import '../../../widgets/app_loader.dart';
import 'widgets/extra_form_sheet.dart';
import 'widgets/item_form_sheet.dart';
import 'widgets/section_form_sheet.dart';

/// One menu's own structure — "Menu → Sections → Items" plus "Extras",
/// exactly the nesting brief section asked for. Reads `listingMenusProvider`
/// (already unfiltered, sections/items/extras all nested per menu — see
/// `loadListingTree`) rather than a dedicated single-menu endpoint, since
/// none exists; finds this one menu by id out of the full list.
class MenuDetailScreen extends ConsumerWidget {
  const MenuDetailScreen({
    super.key,
    required this.listingId,
    required this.menuId,
  });

  final int listingId;
  final int menuId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final menusAsync = ref.watch(listingMenusProvider(listingId));

    return Scaffold(
      appBar: AppBar(
        title: Text(t(locale, ru: 'Состав меню', kz: 'Мәзір құрамы')),
      ),
      body: menusAsync.when(
        loading: () => const AppLoader(),
        error: (err, _) => Center(
          child: AppErrorView(
            message: apiErrorMessage(locale, err),
            locale: locale,
            onRetry: () => ref.invalidate(listingMenusProvider(listingId)),
          ),
        ),
        data: (menus) {
          ListingMenu? menu;
          for (final m in menus) {
            if (m.id == menuId) menu = m;
          }
          if (menu == null) {
            // The menu this screen was opened for was just deleted (e.g.
            // from another device/tab) — nothing meaningful left to show.
            return Center(
              child: Text(
                t(
                  locale,
                  ru: 'Меню больше не существует',
                  kz: 'Мәзір енді жоқ',
                ),
                style: Theme.of(context).textTheme.bodyLarge,
              ),
            );
          }
          return _MenuDetailBody(listingId: listingId, menu: menu);
        },
      ),
    );
  }
}

class _MenuDetailBody extends ConsumerWidget {
  const _MenuDetailBody({required this.listingId, required this.menu});

  final int listingId;
  final ListingMenu menu;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final sections = [...menu.sections]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));
    final extras = [...menu.extras]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.md,
        AppSpacing.lg,
        AppSpacing.xxl,
      ),
      children: [
        Text(menu.name(locale), style: Theme.of(context).textTheme.titleLarge),
        const SizedBox(height: AppSpacing.lg),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              t(locale, ru: 'Разделы', kz: 'Бөлімдер'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            TextButton.icon(
              onPressed: () => openSectionFormSheet(
                context,
                listingId: listingId,
                menuId: menu.id,
              ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(t(locale, ru: 'Раздел', kz: 'Бөлім')),
            ),
          ],
        ),
        if (sections.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(
              t(locale, ru: 'Разделов пока нет', kz: 'Бөлімдер әлі жоқ'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        for (final section in sections) ...[
          _SectionCard(listingId: listingId, menuId: menu.id, section: section),
          const SizedBox(height: AppSpacing.sm),
        ],
        const SizedBox(height: AppSpacing.md),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              t(locale, ru: 'Дополнительные услуги', kz: 'Қосымша қызметтер'),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            TextButton.icon(
              onPressed: () => openExtraFormSheet(
                context,
                listingId: listingId,
                menuId: menu.id,
              ),
              icon: const Icon(Icons.add_rounded, size: 18),
              label: Text(t(locale, ru: 'Опция', kz: 'Опция')),
            ),
          ],
        ),
        if (extras.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
            child: Text(
              t(locale, ru: 'Опций пока нет', kz: 'Опциялар әлі жоқ'),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          )
        else
          for (final extra in extras) ...[
            _ExtraCard(listingId: listingId, menuId: menu.id, extra: extra),
            const SizedBox(height: AppSpacing.xs),
          ],
      ],
    );
  }
}

class _SectionCard extends ConsumerWidget {
  const _SectionCard({
    required this.listingId,
    required this.menuId,
    required this.section,
  });

  final int listingId;
  final int menuId;
  final ListingMenuSection section;

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final locale = ref.read(localeProvider);
    final confirmed = await ConfirmDeleteSheet.show(
      context,
      title: t(
        locale,
        ru: 'Удалить раздел «${section.titleRu}» вместе со всеми позициями?',
        kz: '«${section.titleRu}» бөлімін барлық позициялармен жою керек пе?',
      ),
    );
    if (!confirmed) return;
    try {
      await ref
          .read(listingManagementActionsProvider)
          .deleteSection(listingId, menuId, section.id);
    } catch (err) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiErrorMessage(locale, err))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final colors = context.mereytoiColors;
    final items = [...section.items]
      ..sort((a, b) => a.sortOrder.compareTo(b.sortOrder));

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  section.title(locale),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
              IconButton(
                onPressed: () => openSectionFormSheet(
                  context,
                  listingId: listingId,
                  menuId: menuId,
                  existing: section,
                ),
                icon: Icon(
                  Icons.edit_outlined,
                  size: 17,
                  color: colors.textSecondary,
                ),
              ),
              IconButton(
                onPressed: () => _delete(context, ref),
                icon: Icon(
                  Icons.delete_outline_rounded,
                  size: 17,
                  color: colors.error,
                ),
              ),
            ],
          ),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.xs),
              child: Text(
                t(locale, ru: 'Позиций пока нет', kz: 'Позициялар әлі жоқ'),
                style: Theme.of(context).textTheme.bodySmall,
              ),
            )
          else
            for (final item in items)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        item.quantityText.isNotEmpty
                            ? '${item.name(locale)} · ${item.quantityText}'
                            : item.name(locale),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodyMedium,
                      ),
                    ),
                    InkWell(
                      onTap: () => openItemFormSheet(
                        context,
                        listingId: listingId,
                        menuId: menuId,
                        sectionId: section.id,
                        existing: item,
                      ),
                      child: Icon(
                        Icons.edit_outlined,
                        size: 15,
                        color: colors.textMuted,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    InkWell(
                      onTap: () async {
                        final confirmed = await ConfirmDeleteSheet.show(
                          context,
                          title: t(
                            locale,
                            ru: 'Удалить позицию «${item.nameRu}»?',
                            kz: '«${item.nameRu}» позициясын жою керек пе?',
                          ),
                        );
                        if (!confirmed) return;
                        try {
                          await ref
                              .read(listingManagementActionsProvider)
                              .deleteItem(
                                listingId,
                                menuId,
                                section.id,
                                item.id,
                              );
                        } catch (err) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              SnackBar(
                                content: Text(apiErrorMessage(locale, err)),
                              ),
                            );
                          }
                        }
                      },
                      child: Icon(
                        Icons.close_rounded,
                        size: 15,
                        color: colors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(
              onPressed: () => openItemFormSheet(
                context,
                listingId: listingId,
                menuId: menuId,
                sectionId: section.id,
              ),
              icon: const Icon(Icons.add_rounded, size: 16),
              label: Text(t(locale, ru: 'Позиция', kz: 'Позиция')),
            ),
          ),
        ],
      ),
    );
  }
}

class _ExtraCard extends ConsumerWidget {
  const _ExtraCard({
    required this.listingId,
    required this.menuId,
    required this.extra,
  });

  final int listingId;
  final int menuId;
  final ListingMenuExtra extra;

  String _priceLabel(AppLocale locale) {
    switch (extra.unit) {
      case 'percent':
        return '${extra.price}%';
      case 'per_guest':
        return '${formatPrice(extra.price)} / ${t(locale, ru: "гость", kz: "қонақ")}';
      case 'per_item':
        return '${formatPrice(extra.price)} / ${t(locale, ru: "шт.", kz: "дана")}';
      default:
        return formatPrice(extra.price);
    }
  }

  Future<void> _delete(BuildContext context, WidgetRef ref) async {
    final locale = ref.read(localeProvider);
    final confirmed = await ConfirmDeleteSheet.show(
      context,
      title: t(
        locale,
        ru: 'Удалить опцию «${extra.titleRu}»?',
        kz: '«${extra.titleRu}» опциясын жою керек пе?',
      ),
    );
    if (!confirmed) return;
    try {
      await ref
          .read(listingManagementActionsProvider)
          .deleteExtra(listingId, menuId, extra.id);
    } catch (err) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiErrorMessage(locale, err))));
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final colors = context.mereytoiColors;
    return AppCard(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  extra.title(locale),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodyLarge,
                ),
                Text(
                  _priceLabel(locale),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () => openExtraFormSheet(
              context,
              listingId: listingId,
              menuId: menuId,
              existing: extra,
            ),
            icon: Icon(
              Icons.edit_outlined,
              size: 17,
              color: colors.textSecondary,
            ),
          ),
          IconButton(
            onPressed: () => _delete(context, ref),
            icon: Icon(
              Icons.delete_outline_rounded,
              size: 17,
              color: colors.error,
            ),
          ),
        ],
      ),
    );
  }
}
