import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/theme/app_theme.dart';
import '../../domain/restaurant/restaurant_location.dart';
import '../../models/listing.dart';
import '../../state/locale_provider.dart';
import '../restaurant/venue_map.dart';

/// Where a restaurant candidate is: address, the embedded [VenueMap] when
/// the venue has saved coordinates, and «На карте» / «Маршрут» links that
/// open the device's map app (kept alongside the embedded map). Without a
/// known location it says so instead of linking to a map of the whole
/// city.
class CandidateLocationRow extends StatelessWidget {
  const CandidateLocationRow({
    super.key,
    required this.listing,
    required this.locale,
  });

  final Listing listing;
  final AppLocale locale;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    final textTheme = Theme.of(context).textTheme;
    final known = hasVenueLocation(listing);
    final address = listing.address ?? '';
    final place = address.isNotEmpty ? address : listing.city;

    final line = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(
          known ? Icons.place_outlined : Icons.location_off_outlined,
          size: 16,
          color: known ? colors.goldPrimary : colors.textSecondary,
        ),
        const SizedBox(width: AppSpacing.xxs),
        Expanded(
          child: Text(
            known
                ? place
                : [
                    if (listing.city.isNotEmpty) listing.city,
                    t(
                      locale,
                      ru: 'Местоположение пока не указано',
                      kz: 'Орналасқан жері әзірге көрсетілмеген',
                      en: 'Location not provided yet',
                    ),
                  ].join(' · '),
            style: textTheme.bodySmall?.copyWith(
              color: known ? colors.textPrimary : colors.textSecondary,
            ),
          ),
        ),
      ],
    );
    if (!known) {
      return KeyedSubtree(
        key: const ValueKey('candidate-location-unknown'),
        child: line,
      );
    }

    final mapUrl = restaurantMapUrl(listing)!;
    final routeUrl = restaurantDirectionsUrl(listing)!;
    final hasMap = listing.hasCoords;
    return Column(
      key: const ValueKey('candidate-location'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        line,
        if (hasMap) ...[
          const SizedBox(height: AppSpacing.xs),
          VenueMap(
            key: const ValueKey('candidate-venue-map'),
            latitude: listing.latitude,
            longitude: listing.longitude,
            venueName: listing.name(locale),
            address: listing.address,
          ),
          const SizedBox(height: AppSpacing.xxs),
        ],
        Wrap(
          spacing: AppSpacing.xs,
          children: [
            _LinkButton(
              key: const ValueKey('candidate-location-map'),
              icon: Icons.map_outlined,
              label: t(locale, ru: 'На карте', kz: 'Картада', en: 'On map'),
              url: mapUrl,
            ),
            _LinkButton(
              key: const ValueKey('candidate-location-route'),
              icon: Icons.directions_outlined,
              label: t(locale, ru: 'Маршрут', kz: 'Бағыт', en: 'Directions'),
              url: routeUrl,
            ),
          ],
        ),
      ],
    );
  }
}

class _LinkButton extends StatelessWidget {
  const _LinkButton({
    super.key,
    required this.icon,
    required this.label,
    required this.url,
  });

  final IconData icon;
  final String label;
  final String url;

  @override
  Widget build(BuildContext context) {
    return TextButton.icon(
      style: TextButton.styleFrom(
        foregroundColor: context.mereytoiColors.goldPrimary,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xxs),
        visualDensity: VisualDensity.compact,
      ),
      onPressed: () =>
          launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
      icon: Icon(icon, size: 16),
      label: Text(label),
    );
  }
}
