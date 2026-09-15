import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/config/api_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../core/utils/format.dart';
import '../../domain/checkout/checkout_validation.dart';
import '../../models/cart_item.dart';
import '../../state/auth_provider.dart';
import '../../state/booking_submit_provider.dart';
import '../../state/cart_provider.dart';
import '../../state/locale_provider.dart';
import '../../widgets/app_card.dart';
import '../../widgets/network_image_box.dart';
import 'booking_success_screen.dart';

String _blockReasonText(AppLocale locale, CheckoutBlockReason reason) {
  switch (reason) {
    case CheckoutBlockReason.emptyCart:
      return t(locale, ru: 'Корзина пуста', kz: 'Себет бос');
    case CheckoutBlockReason.missingEstimatedTotal:
      return t(
        locale,
        ru: 'Не удалось определить стоимость позиции. Удалите её и добавьте заново.',
        kz: 'Позицияның құнын анықтау мүмкін болмады. Оны жойып, қайта қосыңыз.',
      );
    case CheckoutBlockReason.invalidGuestCount:
      return t(
        locale,
        ru: 'Проверьте количество гостей в корзине.',
        kz: 'Себеттегі қонақтар санын тексеріңіз.',
      );
  }
}

/// The mobile-first checkout screen (Stage 6) — a full, readable review of
/// exactly what will be submitted (no technical IDs anywhere), a contact
/// form, and a single submit action. Replaces the inline form that used to
/// live directly in `CartScreen` (Stage 3): the cart screen's own
/// "Оформить заявку" button now validates via [validateCartForCheckout]
/// and pushes here instead.
class CheckoutScreen extends ConsumerStatefulWidget {
  const CheckoutScreen({super.key});

  @override
  ConsumerState<CheckoutScreen> createState() => _CheckoutScreenState();
}

class _CheckoutScreenState extends ConsumerState<CheckoutScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  final _messageController = TextEditingController();

  @override
  void initState() {
    super.initState();
    final authState = ref.read(authProvider);
    final user = authState is AuthAuthenticated ? authState.user : null;
    _nameController = TextEditingController(text: user?.name ?? '');
    _phoneController = TextEditingController(text: user?.phone ?? '');
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _messageController.dispose();
    super.dispose();
  }

  void _submit(List<CartItem> items) {
    final validation = validateCartForCheckout(items);
    if (!validation.isValid) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            _blockReasonText(ref.read(localeProvider), validation.reason!),
          ),
        ),
      );
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    ref
        .read(bookingSubmitProvider.notifier)
        .submit(
          name: _nameController.text.trim(),
          phone: _phoneController.text.trim(),
          message: _messageController.text.trim(),
        );
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final items = ref.watch(cartProvider);
    final total = ref.watch(cartTotalProvider);
    final submitState = ref.watch(bookingSubmitProvider);
    final submitting = submitState is AsyncLoading;
    final submitError = submitState.maybeWhen(
      error: (e, _) => e,
      orElse: () => null,
    );

    // Side-effect navigation, not a build-time branch — this fires exactly
    // once per successful submission (Riverpod only calls a `ref.listen`
    // callback on an actual state *change*, never again on a plain
    // rebuild), so it can't push the success screen twice no matter how
    // many times this widget rebuilds while state stays AsyncData.
    ref.listen(bookingSubmitProvider, (previous, next) {
      final result = next.maybeWhen(data: (r) => r, orElse: () => null);
      if (result != null) {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => BookingSuccessScreen(result: result),
          ),
        );
      }
    });

    return Scaffold(
      appBar: AppBar(
        title: Text(
          t(locale, ru: 'Оформление заявки', kz: 'Өтінімді рәсімдеу'),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.lg,
          AppSpacing.sm,
          AppSpacing.lg,
          AppSpacing.xl,
        ),
        children: [
          Text(
            t(locale, ru: 'Ваш заказ', kz: 'Сіздің тапсырысыңыз'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          for (final item in items) ...[
            _CheckoutItemCard(item: item, locale: locale),
            const SizedBox(height: AppSpacing.sm),
          ],
          const SizedBox(height: AppSpacing.sm),
          Text(
            t(locale, ru: 'Контактные данные', kz: 'Байланыс деректері'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextFormField(
                  controller: _nameController,
                  decoration: InputDecoration(
                    labelText: t(locale, ru: 'Ваше имя', kz: 'Атыңыз'),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? t(locale, ru: 'Введите имя', kz: 'Атыңызды енгізіңіз')
                      : null,
                ),
                const SizedBox(height: AppSpacing.xs),
                TextFormField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  decoration: InputDecoration(
                    labelText: t(locale, ru: 'Телефон', kz: 'Телефон'),
                    hintText: '+7 700 000 00 00',
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty)
                      ? t(
                          locale,
                          ru: 'Введите телефон',
                          kz: 'Телефоныңызды енгізіңіз',
                        )
                      : null,
                ),
                const SizedBox(height: AppSpacing.xs),
                TextFormField(
                  controller: _messageController,
                  maxLines: 3,
                  maxLength: 1000,
                  decoration: InputDecoration(
                    labelText: t(
                      locale,
                      ru: 'Комментарий (необязательно)',
                      kz: 'Түсініктеме (міндетті емес)',
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (submitError != null) ...[
            const SizedBox(height: AppSpacing.xxs),
            Text(
              apiErrorMessage(locale, submitError),
              style: TextStyle(
                color: context.mereytoiColors.error,
                fontSize: 13,
              ),
            ),
          ],
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: context.mereytoiColors.surfaceElevated,
          border: Border(
            top: BorderSide(color: context.mereytoiColors.divider),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.sm,
            ),
            child: Row(
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      t(locale, ru: 'Итого', kz: 'Барлығы'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                    Text(
                      formatPrice(total),
                      style: TextStyle(
                        color: context.mereytoiColors.goldSoft,
                        fontWeight: FontWeight.w800,
                        fontSize: 20,
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(0, 52),
                    ),
                    onPressed: submitting ? null : () => _submit(items),
                    icon: submitting
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: context.mereytoiColors.onGold,
                            ),
                          )
                        : const Icon(Icons.check_rounded, size: 18),
                    label: Text(
                      t(locale, ru: 'Отправить заявку', kz: 'Өтінімді жіберу'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// One item review row — the full frozen snapshot, deliberately never a
/// live re-look-up: hall/menu/guests/extras/price are read straight off
/// [CartItem], exactly what will be sent, with no technical id ever shown.
class _CheckoutItemCard extends StatelessWidget {
  const _CheckoutItemCard({required this.item, required this.locale});

  final CartItem item;
  final AppLocale locale;

  @override
  Widget build(BuildContext context) {
    final detailStyle = Theme.of(context).textTheme.bodySmall;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(AppRadius.sm),
            child: SizedBox(
              width: 48,
              height: 48,
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
                Text(item.name, style: Theme.of(context).textTheme.titleSmall),
                Text(item.category, style: detailStyle),
                if (item.isRestaurantVariant) ...[
                  if (item.hallName != null && item.hallName!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '${t(locale, ru: "Зал", kz: "Зал")}: ${item.hallName}',
                        style: detailStyle,
                      ),
                    ),
                  if (item.menuName != null && item.menuName!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '${t(locale, ru: "Меню", kz: "Меню")}: ${item.menuName}',
                        style: detailStyle,
                      ),
                    ),
                  if (item.guests > 0)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '${item.guests} ${t(locale, ru: "гостей", kz: "қонақ")} × ${formatPrice(item.menuPricePerGuest ?? item.unitPrice)}',
                        style: detailStyle,
                      ),
                    ),
                  if (item.selectedExtras.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(
                        '+ ${item.selectedExtras.map((e) => e.title).join(', ')}',
                        style: detailStyle,
                      ),
                    ),
                ] else if (item.guests > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      '${item.guests} ${t(locale, ru: "чел.", kz: "адам")} × ${formatPrice(item.unitPrice)}',
                      style: detailStyle,
                    ),
                  ),
                const SizedBox(height: 4),
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
        ],
      ),
    );
  }
}
