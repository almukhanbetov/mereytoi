import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/error_messages.dart';
import '../../../core/utils/format.dart';
import '../../../models/provider_booking.dart';
import '../../../state/locale_provider.dart';
import '../../../state/provider_provider.dart';
import '../../../widgets/app_error_view.dart';
import 'business_text.dart';

/// «Заявки» — booking requests that include the provider's services
/// (GET /api/provider/me/bookings): client contact, the provider's own
/// items and subtotal, event date when the booking came from an event.
class ProviderBookingsScreen extends ConsumerWidget {
  const ProviderBookingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final bookings = ref.watch(providerBookingsProvider);

    return Scaffold(
      appBar: AppBar(
        title: Text(t(locale, ru: 'Заявки', kz: 'Өтінімдер', en: 'Requests')),
      ),
      body: RefreshIndicator(
        color: context.mereytoiColors.goldPrimary,
        onRefresh: () => ref.refresh(providerBookingsProvider.future),
        child: bookings.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => ListView(
            children: [
              SizedBox(
                height: 420,
                child: AppErrorView(
                  message: apiErrorMessage(locale, err),
                  locale: locale,
                  onRetry: () => ref.invalidate(providerBookingsProvider),
                ),
              ),
            ],
          ),
          data: (list) => list.isEmpty
              ? ListView(
                  children: [
                    SizedBox(height: 420, child: _Empty(locale: locale)),
                  ],
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.xs,
                    AppSpacing.md,
                    AppSpacing.xl,
                  ),
                  itemCount: list.length,
                  separatorBuilder: (_, _) =>
                      const SizedBox(height: AppSpacing.sm),
                  itemBuilder: (_, i) =>
                      _BookingCard(locale: locale, booking: list[i]),
                ),
        ),
      ),
    );
  }
}

class _BookingCard extends StatelessWidget {
  const _BookingCard({required this.locale, required this.booking});

  final AppLocale locale;
  final ProviderBooking booking;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    final textTheme = Theme.of(context).textTheme;
    final b = booking;
    final phone = b.clientPhone.trim();

    return DecoratedBox(
      key: ValueKey('booking-${b.id}'),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(AppRadius.lg),
        border: Border.all(color: colors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    formatShortDateTime(b.createdAt),
                    style: textTheme.bodySmall?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xs,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: colors.goldPrimary.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(AppRadius.chip),
                  ),
                  child: Text(
                    bookingStatusLabel(locale, b.status),
                    style: textTheme.labelSmall?.copyWith(
                      color: colors.goldMuted,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              b.clientName.isEmpty ? '—' : b.clientName,
              style: textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
            ),
            if (phone.isNotEmpty)
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    minimumSize: const Size(0, 44),
                    padding: EdgeInsets.zero,
                  ),
                  onPressed: () => launchUrl(Uri(scheme: 'tel', path: phone)),
                  icon: const Icon(Icons.phone_rounded, size: 18),
                  label: Text(phone),
                ),
              ),
            if (b.eventDate != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                child: Text(
                  '${t(locale, ru: 'Дата мероприятия', kz: 'Іс-шара күні', en: 'Event date')}: ${formatShortDate(b.eventDate!)}',
                  style: textTheme.bodyMedium,
                ),
              ),
            for (final item in b.items)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(item.title, style: textTheme.bodyMedium),
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      formatPrice(item.totalPrice),
                      style: textTheme.bodyMedium,
                    ),
                  ],
                ),
              ),
            if (b.message.trim().isNotEmpty) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                b.message.trim(),
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
                style: textTheme.bodySmall?.copyWith(
                  color: colors.textSecondary,
                ),
              ),
            ],
            const Divider(height: AppSpacing.lg),
            Row(
              children: [
                Expanded(
                  child: Text(
                    t(locale, ru: 'Итого', kz: 'Барлығы', en: 'Total'),
                    style: textTheme.labelLarge?.copyWith(
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                Text(
                  formatPrice(b.total),
                  key: ValueKey('booking-${b.id}-total'),
                  style: textTheme.titleMedium?.copyWith(
                    color: colors.goldSoft,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty({required this.locale});

  final AppLocale locale;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined, size: 48, color: colors.goldPrimary),
            const SizedBox(height: AppSpacing.md),
            Text(
              t(
                locale,
                ru: 'Пока нет заявок',
                kz: 'Әзірге өтінім жоқ',
                en: 'No requests yet',
              ),
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xxs),
            Text(
              t(
                locale,
                ru: 'Здесь появятся заявки клиентов на ваши услуги',
                kz: 'Мұнда қызметтеріңізге клиенттердің өтінімдері шығады',
                en: 'Client requests for your services will appear here',
              ),
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}
