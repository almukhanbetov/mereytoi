import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/api_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../core/utils/format.dart';
import '../../core/utils/whatsapp.dart';
import '../../models/cart_item.dart';
import '../../state/booking_submit_provider.dart';
import '../../state/cart_provider.dart';
import '../../state/locale_provider.dart';
import '../../widgets/app_card.dart';
import '../../widgets/network_image_box.dart';

/// The mobile counterpart of frontend/src/components/CartDrawer.jsx: cart
/// items with subtotal/total, a name/phone/message form, submit via the
/// existing POST /api/bookings, a success screen, and a WhatsApp action —
/// all local, in-memory cart state (see state/cart_provider.dart).
class CartScreen extends ConsumerStatefulWidget {
  const CartScreen({super.key});

  @override
  ConsumerState<CartScreen> createState() => _CartScreenState();
}

class _CartScreenState extends ConsumerState<CartScreen> {
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _messageController = TextEditingController();
  final _formKey = GlobalKey<FormState>();

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final items = ref.watch(cartProvider);
    final total = ref.watch(cartTotalProvider);
    final submitState = ref.watch(bookingSubmitProvider);

    return Scaffold(
      appBar: AppBar(title: Text(t(locale, ru: 'Корзина', kz: 'Себет'))),
      body: submitState.maybeWhen(
        data: (booking) => booking != null
            ? _SuccessView(locale: locale)
            : _CartBody(
                items: items,
                total: total,
                locale: locale,
                formKey: _formKey,
                nameController: _nameController,
                phoneController: _phoneController,
                messageController: _messageController,
                submitting: false,
              ),
        loading: () => _CartBody(
          items: items,
          total: total,
          locale: locale,
          formKey: _formKey,
          nameController: _nameController,
          phoneController: _phoneController,
          messageController: _messageController,
          submitting: true,
        ),
        orElse: () => _CartBody(
          items: items,
          total: total,
          locale: locale,
          formKey: _formKey,
          nameController: _nameController,
          phoneController: _phoneController,
          messageController: _messageController,
          submitting: false,
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
    required this.formKey,
    required this.nameController,
    required this.phoneController,
    required this.messageController,
    required this.submitting,
  });

  final List<CartItem> items;
  final int total;
  final AppLocale locale;
  final GlobalKey<FormState> formKey;
  final TextEditingController nameController;
  final TextEditingController phoneController;
  final TextEditingController messageController;
  final bool submitting;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (items.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 64,
                height: 64,
                decoration: const BoxDecoration(color: AppColors.surface, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: const Icon(Icons.shopping_bag_outlined, size: 28, color: AppColors.textSecondary),
              ),
              const SizedBox(height: AppSpacing.md),
              Text(t(locale, ru: 'Корзина пуста', kz: 'Себет бос'), style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Text(
                t(locale, ru: 'Добавьте услуги из каталога', kz: 'Каталогтан қызметтерді қосыңыз'),
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ),
        ),
      );
    }

    final submitError = ref.watch(bookingSubmitProvider).maybeWhen(error: (e, _) => e, orElse: () => null);

    return ListView(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.xl),
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
          decoration: const BoxDecoration(border: Border(top: BorderSide(color: AppColors.divider))),
          child: Padding(
            padding: const EdgeInsets.only(top: AppSpacing.sm),
            child: _TotalsRow(label: t(locale, ru: 'Итого', kz: 'Барлығы'), value: formatPrice(total), emphasize: true),
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Text(t(locale, ru: 'Оформление заявки', kz: 'Өтінім рәсімдеу'), style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.xs),
        Form(
          key: formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: nameController,
                decoration: InputDecoration(labelText: t(locale, ru: 'Ваше имя', kz: 'Атыңыз')),
                validator: (v) => (v == null || v.trim().isEmpty) ? t(locale, ru: 'Введите имя', kz: 'Атыңызды енгізіңіз') : null,
              ),
              const SizedBox(height: AppSpacing.xs),
              TextFormField(
                controller: phoneController,
                keyboardType: TextInputType.phone,
                decoration: InputDecoration(labelText: t(locale, ru: 'Телефон', kz: 'Телефон'), hintText: '+7 700 000 00 00'),
                validator: (v) => (v == null || v.trim().isEmpty) ? t(locale, ru: 'Введите телефон', kz: 'Телефоныңызды енгізіңіз') : null,
              ),
              const SizedBox(height: AppSpacing.xs),
              TextFormField(
                controller: messageController,
                maxLines: 3,
                maxLength: 1000,
                decoration: InputDecoration(labelText: t(locale, ru: 'Сообщение (необязательно)', kz: 'Хабарлама (міндетті емес)')),
              ),
            ],
          ),
        ),
        if (submitError != null) ...[
          const SizedBox(height: AppSpacing.xxs),
          Text(apiErrorMessage(locale, submitError), style: const TextStyle(color: AppColors.error, fontSize: 13)),
        ],
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            onPressed: submitting
                ? null
                : () {
                    if (!formKey.currentState!.validate()) return;
                    ref.read(bookingSubmitProvider.notifier).submit(
                          name: nameController.text.trim(),
                          phone: phoneController.text.trim(),
                          message: messageController.text.trim(),
                        );
                  },
            icon: submitting
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2.2, color: AppColors.onGold))
                : const Icon(Icons.arrow_forward_rounded, size: 17),
            label: Text(t(locale, ru: 'Оформить заявку', kz: 'Өтінім жасау')),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          width: double.infinity,
          child: OutlinedButton.icon(
            style: OutlinedButton.styleFrom(
              minimumSize: const Size.fromHeight(44),
              foregroundColor: AppColors.textSecondary,
              textStyle: Theme.of(context).textTheme.labelMedium,
            ),
            onPressed: () async {
              final phone = phoneController.text.trim();
              final link = buildWhatsAppLink(items: items, total: total, phone: phone, locale: locale);
              await openWhatsApp(link);
            },
            icon: const Icon(Icons.chat_bubble_outline_rounded, size: 17, color: AppColors.whatsapp),
            label: Text(t(locale, ru: 'Написать в WhatsApp', kz: 'WhatsApp-қа жазу')),
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
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: SizedBox(
              width: 44,
              height: 44,
              child: NetworkImageBox(url: ApiConfig.mediaUrl(item.image), fallbackIcon: Icons.celebration_outlined),
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
                if (item.guests > 0) ...[
                  const SizedBox(height: 1),
                  Text(
                    '${item.guests} ${t(locale, ru: "чел.", kz: "адам")} × ${formatPrice(item.unitPrice)}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
                const SizedBox(height: 1),
                Text(formatPrice(item.totalPrice), style: const TextStyle(color: AppColors.goldSoft, fontWeight: FontWeight.w800, fontSize: 14)),
              ],
            ),
          ),
          IconButton(
            // Tap target stays the theme's 44x44 minimum; the *visible* dot
            // is the small icon-on-soft-fill below — "neater", not smaller
            // to tap.
            onPressed: () => ref.read(cartProvider.notifier).removeItem(item.listingId),
            icon: const Icon(Icons.close_rounded, size: 15, color: AppColors.textSecondary),
            iconSize: 15,
            style: IconButton.styleFrom(backgroundColor: AppColors.surfaceSoft, padding: const EdgeInsets.all(AppSpacing.xxs)),
          ),
        ],
      ),
    );
  }
}

class _TotalsRow extends StatelessWidget {
  const _TotalsRow({required this.label, required this.value, this.emphasize = false});

  final String label;
  final String value;
  final bool emphasize;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label, style: Theme.of(context).textTheme.bodyLarge),
        Text(
          value,
          style: emphasize
              ? Theme.of(context).textTheme.titleLarge?.copyWith(color: AppColors.goldSoft, fontSize: 22)
              : Theme.of(context).textTheme.bodyLarge,
        ),
      ],
    );
  }
}

class _SuccessView extends ConsumerWidget {
  const _SuccessView({required this.locale});

  final AppLocale locale;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(color: AppColors.surfaceSoft, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: const Icon(Icons.check_rounded, color: AppColors.goldPrimary, size: 34),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(t(locale, ru: 'Спасибо!', kz: 'Рахмет!'), style: Theme.of(context).textTheme.displayMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              t(locale, ru: 'Мы свяжемся с вами в ближайшее время.', kz: 'Жақын арада сізбен байланысамыз.'),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.xl),
            OutlinedButton(
              onPressed: () => ref.read(bookingSubmitProvider.notifier).reset(),
              child: Text(t(locale, ru: 'Продолжить', kz: 'Жалғастыру')),
            ),
          ],
        ),
      ),
    );
  }
}
