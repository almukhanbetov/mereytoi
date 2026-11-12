import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:in_app_purchase/in_app_purchase.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/format.dart';
import '../../../models/listing.dart';
import '../../../models/promotion.dart';
import '../../../services/store_purchase_service.dart';
import '../../../state/locale_provider.dart';
import '../../../state/promotion_provider.dart';
import '../../../widgets/app_back_button.dart';
import '../../../widgets/app_card.dart';
import '../../../widgets/app_error_view.dart';
import '../../../widgets/app_skeleton.dart';

/// «Продвигать» — the owner's promotion of one listing: terms and price
/// before paying, the store purchase, the running period with its end date
/// and the ad statistics.
class PromotionScreen extends ConsumerStatefulWidget {
  const PromotionScreen({super.key, required this.listing});

  final Listing listing;

  @override
  ConsumerState<PromotionScreen> createState() => _PromotionScreenState();
}

class _PromotionScreenState extends ConsumerState<PromotionScreen> {
  ProductDetails? _product;
  bool _productLoaded = false;
  String? _productFor;
  bool _buying = false;

  @override
  void initState() {
    super.initState();
    // Picks up a purchase the store re-delivers (the app closed mid-way).
    ref.read(storePurchaseProvider).start();
  }

  Future<void> _loadProduct(String productId) async {
    if (_productFor == productId) return;
    _productFor = productId;
    ProductDetails? product;
    try {
      product = await ref.read(storePurchaseProvider).product(productId);
    } catch (_) {}
    if (mounted) {
      setState(() {
        _product = product;
        _productLoaded = true;
      });
    }
  }

  Future<void> _buy(AppLocale locale) async {
    final product = _product;
    if (product == null || _buying) return;
    setState(() => _buying = true);
    PromotionPurchaseResult result;
    try {
      result = await ref
          .read(storePurchaseProvider)
          .buy(listingId: widget.listing.id, product: product);
    } catch (err) {
      result = PromotionPurchaseResult.failed;
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(apiErrorMessage(locale, err))));
      }
    }
    if (!mounted) return;
    setState(() => _buying = false);
    ref.invalidate(promotionStatusProvider(widget.listing.id));
    final message = switch (result) {
      PromotionPurchaseResult.activated => t(
        locale,
        ru: 'Оплата подтверждена, продвижение включено',
        kz: 'Төлем расталды, жарнама қосылды',
        en: 'Payment confirmed, promotion is on',
      ),
      PromotionPurchaseResult.pending => t(
        locale,
        ru:
            'Оплата ещё не подтверждена магазином. Продвижение включится '
            'автоматически после подтверждения.',
        kz:
            'Төлемді дүкен әлі растаған жоқ. Расталғаннан кейін жарнама '
            'өздігінен қосылады.',
        en:
            'The store hasn’t confirmed the payment yet. The promotion turns '
            'on by itself once it does.',
      ),
      PromotionPurchaseResult.cancelled => null,
      PromotionPurchaseResult.failed => t(
        locale,
        ru: 'Не удалось завершить оплату. Деньги не списаны или вернутся.',
        kz: 'Төлем аяқталмады. Ақша алынбады немесе қайтарылады.',
        en: 'The payment didn’t go through. You weren’t charged or will be refunded.',
      ),
      PromotionPurchaseResult.unavailable => _unavailableText(locale),
    };
    if (message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  static String _unavailableText(AppLocale locale) => t(
    locale,
    ru:
        'Оплата в приложении пока не подключена. Покупка станет доступна '
        'после настройки магазина.',
    kz:
        'Қосымшадағы төлем әлі қосылмаған. Дүкен бапталғаннан кейін сатып '
        'алуға болады.',
    en:
        'In-app payment isn’t set up yet. Buying becomes available once the '
        'store is configured.',
  );

  static String _blockedText(AppLocale locale, String reason) {
    switch (reason) {
      case 'not_owner':
        return t(
          locale,
          ru: 'Оплатить продвижение может только владелец карточки.',
          kz: 'Жарнаманы тек карточка иесі төлей алады.',
          en: 'Only the listing’s owner can pay for a promotion.',
        );
      case 'listing_hidden':
        return t(
          locale,
          ru: 'Карточка скрыта. Опубликуйте её, чтобы продвигать.',
          kz: 'Карточка жасырын. Жарнамалау үшін оны жариялаңыз.',
          en: 'This listing is hidden. Publish it to promote it.',
        );
      case 'provider_not_active':
      case 'no_owner':
        return t(
          locale,
          ru: 'Профиль услугодателя не активен, продвижение недоступно.',
          kz: 'Қызмет көрсетуші профилі белсенді емес, жарнама қолжетімсіз.',
          en: 'The provider profile isn’t active, promotion is unavailable.',
        );
      default:
        return t(
          locale,
          ru: 'Продвижение пока недоступно.',
          kz: 'Жарнама әзірге қолжетімсіз.',
          en: 'Promotion isn’t available yet.',
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final status = ref.watch(promotionStatusProvider(widget.listing.id));
    final channel = ref.watch(storeChannelProvider);

    return Scaffold(
      appBar: AppBar(
        leading: const AppBackButton(),
        title: Text(
          t(locale, ru: 'Продвижение', kz: 'Жарнама', en: 'Promotion'),
        ),
      ),
      body: status.when(
        loading: () => ListView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: const [
            AppSkeleton(height: 140, borderRadius: 16),
            SizedBox(height: AppSpacing.md),
            AppSkeleton(height: 220, borderRadius: 16),
          ],
        ),
        error: (err, _) => AppErrorView(
          message: apiErrorMessage(locale, err),
          error: err,
          locale: locale,
          onRetry: () =>
              ref.invalidate(promotionStatusProvider(widget.listing.id)),
        ),
        data: (s) {
          final storeOption = channel == null ? null : s.channel(channel);
          if (storeOption != null &&
              storeOption.available &&
              storeOption.productId != null) {
            _loadProduct(storeOption.productId!);
          }
          return RefreshIndicator(
            onRefresh: () =>
                ref.refresh(promotionStatusProvider(widget.listing.id).future),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.lg,
                AppSpacing.md,
                AppSpacing.lg,
                AppSpacing.xl,
              ),
              children: [
                Text(
                  widget.listing.name(locale),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: AppSpacing.md),
                if (s.running != null) ...[
                  _RunningCard(period: s.running!, locale: locale),
                  const SizedBox(height: AppSpacing.md),
                ],
                _TermsCard(status: s, product: _product, locale: locale),
                const SizedBox(height: AppSpacing.md),
                if (s.running == null)
                  _buyArea(context, locale, s, channel, storeOption),
                if (s.history.where((p) => !p.running).isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.lg),
                  Text(
                    t(locale, ru: 'История', kz: 'Тарих', en: 'History'),
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  for (final p in s.history.where((p) => !p.running)) ...[
                    _PeriodCard(period: p, locale: locale),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buyArea(
    BuildContext context,
    AppLocale locale,
    PromotionStatus s,
    String? channel,
    PromotionChannel? storeOption,
  ) {
    String? note;
    var enabled = false;
    if (!s.canPurchase) {
      note = _blockedText(locale, s.blockedReason);
    } else if (channel == null) {
      note = t(
        locale,
        ru: 'Купить продвижение можно в приложении MEREYTOI для Android или iPhone.',
        kz: 'Жарнаманы Android немесе iPhone-ға арналған MEREYTOI қосымшасында сатып алуға болады.',
        en: 'Promotion can be bought in the MEREYTOI app for Android or iPhone.',
      );
    } else if (storeOption == null || !storeOption.available) {
      note = _unavailableText(locale);
    } else if (!_productLoaded) {
      note = null;
    } else if (_product == null) {
      note = _unavailableText(locale);
    } else {
      enabled = true;
    }
    final price = _product?.price;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ElevatedButton.icon(
          key: const ValueKey('promotion-buy'),
          style: ElevatedButton.styleFrom(minimumSize: const Size(0, 52)),
          onPressed: enabled && !_buying ? () => _buy(locale) : null,
          icon: _buying
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.trending_up_rounded),
          label: Text(
            price == null
                ? t(locale, ru: 'Продвигать', kz: 'Жарнамалау', en: 'Promote')
                : t(
                    locale,
                    ru: 'Продвигать за $price',
                    kz: '$price — жарнамалау',
                    en: 'Promote for $price',
                  ),
            textAlign: TextAlign.center,
          ),
        ),
        if (note != null) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            note,
            key: const ValueKey('promotion-note'),
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ],
    );
  }
}

String _date(DateTime d) =>
    '${d.day.toString().padLeft(2, '0')}.${d.month.toString().padLeft(2, '0')}.${d.year}';

class _TermsCard extends StatelessWidget {
  const _TermsCard({
    required this.status,
    required this.product,
    required this.locale,
  });

  final PromotionStatus status;
  final ProductDetails? product;
  final AppLocale locale;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    // Only the store product's own price, in its own currency, is shown:
    // that is what Google Play / the App Store charges. The admin price
    // never stands in for it.
    final price = product?.price;
    Widget line(IconData icon, String text) => Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 18, color: context.mereytoiColors.goldPrimary),
          const SizedBox(width: AppSpacing.xs),
          Expanded(child: Text(text, style: textTheme.bodyMedium)),
        ],
      ),
    );
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t(
              locale,
              ru: 'Пакет «${status.durationDays} дней»',
              kz: '«${status.durationDays} күн» пакеті',
              en: '${status.durationDays}-day package',
            ),
            style: textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.xxs),
          if (price != null)
            Text(
              price,
              key: const ValueKey('promotion-price'),
              style: textTheme.headlineSmall,
            )
          else
            Text(
              t(
                locale,
                ru: 'Цена и валюта появятся, когда магазин подтвердит товар',
                kz: 'Бағасы мен валютасы дүкен тауарды растағанда көрсетіледі',
                en: 'Price and currency appear once the store confirms the product',
              ),
              key: const ValueKey('promotion-price-pending'),
              style: textTheme.bodySmall,
            ),
          const SizedBox(height: AppSpacing.sm),
          line(
            Icons.event_outlined,
            t(
              locale,
              ru: '${status.durationDays} дней с момента подтверждения оплаты',
              kz: 'Төлем расталған сәттен бастап ${status.durationDays} күн',
              en: '${status.durationDays} days from when the payment is confirmed',
            ),
          ),
          line(
            Icons.sync_disabled_rounded,
            t(
              locale,
              ru: 'Без автопродления',
              kz: 'Автоматты ұзартусыз',
              en: 'No auto-renewal',
            ),
          ),
          line(
            Icons.campaign_outlined,
            t(
              locale,
              ru:
                  'Карточка показывается с пометкой «Реклама» только тем, '
                  'кто ищет в её городе и категории',
              kz:
                  'Карточка «Жарнама» белгісімен тек оның қаласы мен '
                  'санатында іздегендерге көрсетіледі',
              en:
                  'The listing is shown marked “Ad”, only to people searching '
                  'in its city and category',
            ),
          ),
          line(
            Icons.star_outline_rounded,
            t(
              locale,
              ru: 'Рейтинг, отзывы и значки не меняются',
              kz: 'Рейтинг, пікірлер мен белгілер өзгермейді',
              en: 'Rating, reviews and badges don’t change',
            ),
          ),
          line(
            Icons.visibility_off_outlined,
            t(
              locale,
              ru: 'Скрытая или заблокированная карточка сразу снимается с рекламы',
              kz: 'Жасырылған немесе бұғатталған карточка жарнамадан бірден алынады',
              en: 'A hidden or blocked listing leaves ads at once',
            ),
          ),
        ],
      ),
    );
  }
}

class _RunningCard extends StatelessWidget {
  const _RunningCard({required this.period, required this.locale});

  final PromotionPeriod period;
  final AppLocale locale;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.trending_up_rounded, color: colors.success),
              const SizedBox(width: AppSpacing.xs),
              Expanded(
                child: Text(
                  t(
                    locale,
                    ru: 'Продвигается до ${_date(period.endsAt)}',
                    kz: '${_date(period.endsAt)} дейін жарнамалануда',
                    en: 'Promoted until ${_date(period.endsAt)}',
                  ),
                  key: const ValueKey('promotion-running'),
                  style: Theme.of(context).textTheme.titleSmall,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          _StatsGrid(stats: period.stats, locale: locale),
        ],
      ),
    );
  }
}

class _PeriodCard extends StatelessWidget {
  const _PeriodCard({required this.period, required this.locale});

  final PromotionPeriod period;
  final AppLocale locale;

  @override
  Widget build(BuildContext context) {
    final state = period.refunded
        ? t(
            locale,
            ru: 'Возврат оплаты',
            kz: 'Төлем қайтарылды',
            en: 'Refunded',
          )
        : t(locale, ru: 'Завершено', kz: 'Аяқталды', en: 'Ended');
    return AppCard(
      padding: const EdgeInsets.all(AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_date(period.startsAt)} — ${_date(period.endsAt)} · $state',
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          _StatsGrid(stats: period.stats, locale: locale),
        ],
      ),
    );
  }
}

class _StatsGrid extends StatelessWidget {
  const _StatsGrid({required this.stats, required this.locale});

  final PromotionStats stats;
  final AppLocale locale;

  @override
  Widget build(BuildContext context) {
    final items = [
      (
        t(locale, ru: 'Показы', kz: 'Көрсетілім', en: 'Impressions'),
        stats.impressions,
      ),
      (t(locale, ru: 'Переходы', kz: 'Өтулер', en: 'Opens'), stats.clicks),
      (t(locale, ru: 'Чаты', kz: 'Чаттар', en: 'Chats'), stats.chats),
      (t(locale, ru: 'Звонки', kz: 'Қоңыраулар', en: 'Calls'), stats.calls),
      ('WhatsApp', stats.whatsapp),
    ];
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: AppSpacing.md,
          runSpacing: AppSpacing.sm,
          children: [
            for (final (label, value) in items)
              SizedBox(
                width: 96,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(formatCount(value), style: textTheme.titleMedium),
                    Text(
                      label,
                      style: textTheme.bodySmall,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Text(
          t(
            locale,
            ru:
                'Чаты, звонки и WhatsApp — это нажатия из рекламы, а не '
                'подтверждённые заказы.',
            kz:
                'Чаттар, қоңыраулар мен WhatsApp — жарнамадан жасалған '
                'басулар, расталған тапсырыстар емес.',
            en:
                'Chats, calls and WhatsApp are taps from the ad, not '
                'confirmed orders.',
          ),
          style: textTheme.bodySmall,
        ),
      ],
    );
  }
}
