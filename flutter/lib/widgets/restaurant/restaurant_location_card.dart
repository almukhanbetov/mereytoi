import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/restaurant/restaurant_location.dart';
import '../../models/listing.dart';
import '../../state/locale_provider.dart';
import '../app_card.dart';

/// Brief section 9 — address text + a "Построить маршрут" button that opens
/// the device's own map app via `url_launcher`. No Google Maps SDK, no
/// embedded map preview (that's a key-less `<iframe>` on the web, which
/// has no mobile equivalent worth adding here) — same constraint the brief
/// states explicitly. Renders nothing at all when the listing has neither
/// an address/city nor coordinates, matching `RestaurantLocation.jsx`.
class RestaurantLocationCard extends StatelessWidget {
  const RestaurantLocationCard({
    super.key,
    required this.listing,
    required this.locale,
  });

  final Listing listing;
  final AppLocale locale;

  @override
  Widget build(BuildContext context) {
    final url = restaurantDirectionsUrl(listing);
    if (url == null) return const SizedBox.shrink();

    final addressText = (listing.address != null && listing.address!.isNotEmpty)
        ? listing.address!
        : listing.city;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t(locale, ru: 'Расположение', kz: 'Орналасуы'),
            style: Theme.of(context).textTheme.titleMedium,
          ),
          if (addressText.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Icon(
                  Icons.place_outlined,
                  size: 16,
                  color: context.mereytoiColors.goldPrimary,
                ),
                const SizedBox(width: AppSpacing.xxs),
                Expanded(
                  child: Text(
                    addressText,
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: AppSpacing.sm),
          OutlinedButton.icon(
            onPressed: () =>
                launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
            icon: const Icon(Icons.directions_outlined, size: 18),
            label: Text(t(locale, ru: 'Построить маршрут', kz: 'Бағыт салу')),
          ),
        ],
      ),
    );
  }
}
