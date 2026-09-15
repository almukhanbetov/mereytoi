import 'package:flutter/material.dart';

import '../../core/config/api_config.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/format.dart';
import '../../models/listing_hall.dart';
import '../../state/locale_provider.dart';
import '../network_image_box.dart';

/// Horizontal hall cards — brief section 2: photo/name/capacity/price,
/// gold-highlighted when selected, an inactive hall shown but disabled
/// (never tappable, never silently hidden — `GET /api/listings/:id/halls`
/// already only returns active halls today, but this stays defensive in
/// case that ever changes).
class HallSelector extends StatelessWidget {
  const HallSelector({
    super.key,
    required this.halls,
    required this.selectedHallId,
    required this.locale,
    required this.onSelect,
  });

  final List<ListingHall> halls;
  final int? selectedHallId;
  final AppLocale locale;
  final ValueChanged<ListingHall> onSelect;

  @override
  Widget build(BuildContext context) {
    if (halls.isEmpty) return const SizedBox.shrink();

    return SizedBox(
      height: 176,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        itemCount: halls.length,
        separatorBuilder: (_, _) => const SizedBox(width: AppSpacing.sm),
        itemBuilder: (context, i) {
          final hall = halls[i];
          final selected = hall.id == selectedHallId;
          return _HallCard(
            hall: hall,
            selected: selected,
            locale: locale,
            onTap: hall.isActive ? () => onSelect(hall) : null,
          );
        },
      ),
    );
  }
}

class _HallCard extends StatelessWidget {
  const _HallCard({
    required this.hall,
    required this.selected,
    required this.locale,
    required this.onTap,
  });

  final ListingHall hall;
  final bool selected;
  final AppLocale locale;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final disabled = onTap == null;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        curve: Curves.easeOut,
        width: 148,
        decoration: BoxDecoration(
          color: context.mereytoiColors.surface,
          borderRadius: BorderRadius.circular(AppRadius.lg),
          border: Border.all(
            color: selected
                ? context.mereytoiColors.goldPrimary
                : Colors.transparent,
            width: 2,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Opacity(
          opacity: disabled ? 0.45 : 1,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 88,
                width: double.infinity,
                child: NetworkImageBox(
                  url: ApiConfig.mediaUrl(hall.coverImage),
                  borderRadius: 0,
                  fallbackIcon: Icons.meeting_room_outlined,
                ),
              ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.xs),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      hall.name(locale),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleSmall,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        if (hall.capacity > 0) ...[
                          Icon(
                            Icons.groups_outlined,
                            size: 12,
                            color: context.mereytoiColors.textSecondary,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            '${hall.capacity}',
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ],
                        if (hall.price > 0) ...[
                          if (hall.capacity > 0)
                            const SizedBox(width: AppSpacing.xxs),
                          Expanded(
                            child: Text(
                              formatPrice(hall.price),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              textAlign: TextAlign.end,
                              style: TextStyle(
                                color: context.mereytoiColors.goldSoft,
                                fontSize: 11.5,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
