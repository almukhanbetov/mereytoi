import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/api_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../core/utils/whatsapp.dart';
import '../../domain/checkout/checkout_validation.dart';
import '../../models/cart_item.dart';
import '../../state/cart_provider.dart';
import '../../state/locale_provider.dart';
import '../../widgets/animated_price_text.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_icon_badge.dart';
import '../../widgets/network_image_box.dart';
import '../checkout/checkout_screen.dart';
import '../root_shell.dart';

String _blockReasonText(AppLocale locale, CheckoutBlockReason reason) {
  switch (reason) {
    case CheckoutBlockReason.emptyCart:
      return t(
        locale,
        ru: 'Корзина пуста',
        kz: 'Себет бос',
        en: 'Cart is empty',
      );
    case CheckoutBlockReason.missingEstimatedTotal:
      return t(
        locale,
        ru: 'Не удалось определить стоимость позиции. Удалите её и добавьте заново.',
        kz: 'Позицияның құнын анықтау мүмкін болмады. Оны жойып, қайта қосыңыз.',
        en: 'Couldn\'t determine this item\'s price. Remove it and add it again.',
      );
    case CheckoutBlockReason.invalidGuestCount:
      return t(
        locale,
        ru: 'Проверьте количество гостей в корзине.',
        kz: 'Себеттегі қонақтар санын тексеріңіз.',
        en: 'Check the number of guests in your cart.',
      );
  }
}

/// The mobile counterpart of frontend/src/components/CartDrawer.jsx: cart
/// items with subtotal/total, a WhatsApp action, and "Оформить заявку" —
/// which now (Stage 6) validates the cart via [validateCartForCheckout]
/// and pushes the dedicated [CheckoutScreen] instead of submitting from
/// here directly; all local, in-memory cart state (see
/// state/cart_provider.dart).
class CartScreen extends ConsumerWidget {
  const CartScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final items = ref.watch(cartProvider);
    final total = ref.watch(cartTotalProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(t(locale, ru: 'Корзина', kz: 'Себет', en: 'Cart')),
      ),
      body: items.isEmpty
          ? _EmptyCart(locale: locale)
          : _CartBody(items: items, total: total, locale: locale),
    );
  }
}

class _EmptyCart extends ConsumerWidget {
  const _EmptyCart({required this.locale});

  final AppLocale locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppIconBadge(icon: Icons.shopping_bag_outlined),
            const SizedBox(height: AppSpacing.md),
            Text(
              t(
                locale,
                ru: 'Корзина пока пуста',
                kz: 'Себет әлі бос',
                en: 'Your cart is empty',
              ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              t(
                locale,
                ru: 'Добавьте услуги из каталога',
                kz: 'Каталогтан қызметтерді қосыңыз',
                en: 'Add services from the catalog',
              ),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton(
              onPressed: () => ref.read(selectedTabProvider.notifier).state = 1,
              child: Text(
                t(
                  locale,
                  ru: 'Выбрать услуги',
                  kz: 'Қызметтерді таңдау',
                  en: 'Choose services',
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CartBody extends ConsumerWidget {
  const _CartBody({
    required this.items,
    required this.total,
    required this.locale,
  });

  final List<CartItem> items;
  final int total;
  final AppLocale locale;

  void _goToCheckout(BuildContext context, WidgetRef ref) {
    final validation = validateCartForCheckout(items);
    if (!validation.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_blockReasonText(locale, validation.reason!))),
      );
      return;
    }
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const CheckoutScreen()));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.lg,
        AppSpacing.sm,
        AppSpacing.lg,
        AppSpacing.xl,
      ),
      children: [
        for (final item in items) ...[
          _CartItemCard(item: item, locale: locale),
          const SizedBox(height: AppSpacing.sm),
        ],
        const SizedBox(height: AppSpacing.sm),
        // A plain hairline-divided row instead of another boxed card — the
        // list above already reads as a group, so the total just needs a
        // clear line under it, not a second dark container stacked on top.
        DecoratedBox(
          decoration: BoxDecoration(
            border: Border(
              top: BorderSide(color: context.mereytoiColors.divider),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: _TotalsRow(
              label: t(locale, ru: 'Итого', kz: 'Барлығы', en: 'Total'),
              value: formatPrice(total),
              emphasize: true,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: () => _goToCheckout(context, ref),
            icon: const Icon(Icons.arrow_forward_rounded, size: 17),
            label: Text(
              t(
                locale,
                ru: 'Оформить заявку',
                kz: 'Өтінім жасау',
                en: 'Submit request',
              ),
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              foregroundColor: context.mereytoiColors.textSecondary,
              textStyle: Theme.of(context).textTheme.labelMedium,
            ),
            onPressed: () async {
              final link = buildWhatsAppLink(
                items: items,
                total: total,
                phone: '',
                locale: locale,
              );
              await openWhatsApp(link);
            },
            icon: Icon(
              Icons.chat_bubble_outline_rounded,
              size: 17,
              color: context.mereytoiColors.whatsapp,
            ),
            label: Text(
              t(
                locale,
                ru: 'Написать в WhatsApp',
                kz: 'WhatsApp-қа жазу',
                en: 'Message on WhatsApp',
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CartItemCard extends ConsumerWidget {
  const _CartItemCard({required this.item, required this.locale});

  final CartItem item;
  final AppLocale locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: SizedBox(
              width: 60,
              height: 60,
              child: NetworkImageBox(
                url: ApiConfig.mediaUrl(item.image),
                fallbackIcon: Icons.celebration_outlined,
              ),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.name,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.titleSmall,
                ),
                if (item.isRestaurantVariant)
                  ..._RestaurantVariantDetails(
                    item: item,
                    locale: locale,
                  ).lines(context)
                else if (item.guests > 0) ...[
                  const SizedBox(height: 1),
                  Text(
                    '${item.guests} ${t(locale, ru: "чел.", kz: "адам", en: "guests")} × ${formatPrice(item.unitPrice)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 2),
                Text(
                  formatPrice(item.totalPrice),
                  style: TextStyle(
                    color: context.mereytoiColors.goldSoft,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            // Tap target stays the theme's 44x44 minimum; the *visible* dot
            // is the small icon-on-soft-fill below — "neater", not smaller
            // to tap.
            onPressed: () =>
                ref.read(cartProvider.notifier).removeItem(item.key),
            icon: Icon(
              Icons.close_rounded,
              size: 15,
              color: context.mereytoiColors.textSecondary,
            ),
            iconSize: 15,
            style: IconButton.styleFrom(
              backgroundColor: context.mereytoiColors.surfaceSoft,
              padding: const EdgeInsets.all(AppSpacing.xxs),
            ),
          ),
        ],
      ),
    );
  }
}

/// The restaurant-only detail lines under a cart card's title — hall,
/// guests × price/guest, and a short "+ extra, extra" summary. Every line
/// is genuinely optional (brief section 7 — "не показывать null/пустые
/// строки"): a hall-less menu just skips its line, no extras means no
/// extras line at all.
class _RestaurantVariantDetails {
  const _RestaurantVariantDetails({required this.item, required this.locale});

  final CartItem item;
  final AppLocale locale;

  List<Widget> lines(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall;
    return [
      if (item.hallName != null && item.hallName!.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Text(
            '${t(locale, ru: "Зал", kz: "Зал", en: "Hall")}: ${item.hallName}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      if (item.guests > 0)
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Text(
            '${item.guests} ${t(locale, ru: "гостей", kz: "қонақ", en: "guests")} × ${formatPrice(item.menuPricePerGuest ?? item.unitPrice)}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
      if (item.selectedExtras.isNotEmpty)
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Text(
            '+ ${item.selectedExtras.map((e) => e.title).join(', ')}',
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        ),
    ];
  }
}

class _TotalsRow extends StatelessWidget {
  const _TotalsRow({
    required this.label,
    required this.value,
    this.emphasize = false,
  });

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    final valueStyle = emphasize
        ? Theme.of(context).textTheme.titleLarge?.copyWith(
            color: context.mereytoiColors.goldSoft,
            fontSize: 22,
          )
        : Theme.of(context).textTheme.bodyLarge;
    // Этап 10Б-1А: same shape as PriceSummaryCard's own "Итого" row, same
    // fix — a plain Row here overflows at a large system text scale
    // (label + a genuinely large 22px total, neither flexible). Wrap
    // reflows to its own line instead when it doesn't fit.
    return Wrap(
      alignment: WrapAlignment.spaceBetween,
      crossAxisAlignment: WrapCrossAlignment.center,
      runSpacing: AppSpacing.xxs,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyLarge),
        emphasize
            ? AnimatedPriceText(text: value, style: valueStyle)
            : Text(value, style: valueStyle),
      ],
    );
  }
}
