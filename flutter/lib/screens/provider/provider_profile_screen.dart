import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/api_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../core/utils/listing_navigation.dart';
import '../../core/utils/whatsapp.dart';
import '../../models/provider_public_profile.dart';
import '../../state/categories_provider.dart';
import '../../state/locale_provider.dart';
import '../../state/public_provider_provider.dart';
import '../../widgets/app_error_view.dart';
import '../../widgets/app_icon_badge.dart';
import '../../widgets/app_loader.dart';
import '../../widgets/network_image_box.dart';
import '../../widgets/service_card.dart';
import '../provider_chat/provider_chat_screen.dart';

/// Публичный профиль услугодателя — Этап 11G brief section 1. Opened by
/// tapping the provider's name/avatar on a service card or the service
/// detail page (`_ProviderBlock` in listing_hero_header.dart). No auth
/// required to view (mirrors GET /api/providers/:id itself); "Написать
/// услугодателю" below gates on auth the same way ManagerChatScreen does.
class ProviderProfileScreen extends ConsumerWidget {
  const ProviderProfileScreen({super.key, required this.providerId});

  final int providerId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final profileAsync = ref.watch(publicProviderProfileProvider(providerId));

    return Scaffold(
      appBar: AppBar(
        title: Text(
          t(
            locale,
            ru: 'Профиль услугодателя',
            kz: 'Қызмет көрсетуші профилі',
            en: 'Provider profile',
          ),
        ),
      ),
      body: profileAsync.when(
        loading: () => const AppLoader(),
        error: (err, _) => Center(
          child: AppErrorView(
            message: apiErrorMessage(locale, err),
            locale: locale,
            onRetry: () =>
                ref.invalidate(publicProviderProfileProvider(providerId)),
          ),
        ),
        data: (profile) => _ProfileBody(profile: profile, locale: locale),
      ),
    );
  }
}

class _ProfileBody extends ConsumerWidget {
  const _ProfileBody({required this.profile, required this.locale});

  final ProviderPublicProfile profile;
  final AppLocale locale;

  Uri? get _contactUri {
    final waDigits = toWhatsAppDigits(profile.whatsapp);
    if (waDigits.isNotEmpty) return Uri.parse('https://wa.me/$waDigits');
    if (profile.telegram.isNotEmpty) {
      return Uri.parse('https://t.me/${profile.telegram.replaceFirst('@', '')}');
    }
    if (profile.phone.isNotEmpty) {
      return Uri.parse('tel:${profile.phone.replaceAll(' ', '')}');
    }
    return null;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = context.mereytoiColors;
    final categoriesAsync = ref.watch(categoriesProvider);
    final contactUri = _contactUri;

    return ListView(
      padding: const EdgeInsets.all(AppSpacing.lg),
      children: [
        Center(
          child: Column(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(48),
                child: SizedBox(
                  width: 96,
                  height: 96,
                  child: profile.avatarUrl.isEmpty
                      ? const AppIconBadge(
                          icon: Icons.storefront_outlined,
                          size: 96,
                          iconSize: 40,
                        )
                      : NetworkImageBox(
                          url: ApiConfig.mediaUrl(profile.avatarUrl),
                          borderRadius: 0,
                        ),
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              Text(
                profile.displayName,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              if (profile.city.isNotEmpty) ...[
                const SizedBox(height: 2),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.place_outlined, size: 15, color: colors.textMuted),
                    const SizedBox(width: 2),
                    Text(
                      profile.city,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: AppSpacing.xs),
              Text(
                t(
                  locale,
                  ru: '${profile.listingCount} услуг',
                  kz: '${profile.listingCount} қызмет',
                  en: '${profile.listingCount} services',
                ),
                style: Theme.of(
                  context,
                ).textTheme.bodySmall?.copyWith(color: colors.textMuted),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.lg),
        Row(
          children: [
            Expanded(
              child: ElevatedButton.icon(
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => ProviderChatScreen(
                      providerId: profile.id,
                      peerName: profile.displayName,
                      peerAvatarUrl: profile.avatarUrl.isEmpty
                          ? null
                          : profile.avatarUrl,
                    ),
                  ),
                ),
                icon: const Icon(Icons.chat_bubble_outline_rounded, size: 17),
                label: Text(
                  t(
                    locale,
                    ru: 'Написать услугодателю',
                    kz: 'Қызмет көрсетушіге жазу',
                    en: 'Message the provider',
                  ),
                ),
              ),
            ),
            if (contactUri != null) ...[
              const SizedBox(width: AppSpacing.xs),
              Material(
                color: colors.surfaceSoft,
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: InkWell(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  onTap: () =>
                      launchUrl(contactUri, mode: LaunchMode.externalApplication),
                  child: SizedBox(
                    width: 48,
                    height: 48,
                    child: Icon(
                      Icons.call_outlined,
                      size: 19,
                      color: colors.goldPrimary,
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        if (profile.description.isNotEmpty) ...[
          const SizedBox(height: AppSpacing.lg),
          Text(
            t(locale, ru: 'О себе', kz: 'Өзі туралы', en: 'About'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          Text(
            profile.description,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.5),
          ),
        ],
        const SizedBox(height: AppSpacing.lg),
        Text(
          t(locale, ru: 'Услуги', kz: 'Қызметтер', en: 'Services'),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: AppSpacing.sm),
        if (profile.listings.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.lg),
            child: Center(
              child: Text(
                t(
                  locale,
                  ru: 'Пока нет опубликованных услуг',
                  kz: 'Әзірге жарияланған қызмет жоқ',
                  en: 'No published services yet',
                ),
                style: Theme.of(
                  context,
                ).textTheme.bodyMedium?.copyWith(color: colors.textMuted),
              ),
            ),
          )
        else
          for (final listing in profile.listings) ...[
            ServiceListTile(
              listing: listing,
              locale: locale,
              categoryLabel: categoriesAsync.maybeWhen(
                data: (categories) {
                  for (final c in categories) {
                    if (c.id == listing.categoryId) return c.name(locale);
                  }
                  return null;
                },
                orElse: () => null,
              ),
              onTap: () => pushListingDetail(context, ref, listing),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
      ],
    );
  }
}
