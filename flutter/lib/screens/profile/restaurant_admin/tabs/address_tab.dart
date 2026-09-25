import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/error_messages.dart';
import '../../../../models/listing.dart';
import '../../../../state/listing_management_actions.dart';
import '../../../../state/locale_provider.dart';

/// "Адрес" tab — `Listing.address/latitude/longitude/place_id`, the same
/// four location fields `RestaurantLocationCard` (public screen) already
/// reads. No map/geocoding picker exists anywhere in this app yet, so
/// latitude/longitude are plain numeric fields here — never a fabricated
/// map UI this stage didn't actually build.
class AddressTab extends ConsumerStatefulWidget {
  const AddressTab({super.key, required this.listing});

  final Listing listing;

  @override
  ConsumerState<AddressTab> createState() => _AddressTabState();
}

class _AddressTabState extends ConsumerState<AddressTab> {
  late final TextEditingController _address;
  late final TextEditingController _latitude;
  late final TextEditingController _longitude;
  late final TextEditingController _placeId;
  late final TextEditingController _capacity;
  bool _saving = false;
  String? _error;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    final l = widget.listing;
    _address = TextEditingController(text: l.address ?? '');
    _latitude = TextEditingController(text: l.latitude?.toString() ?? '');
    _longitude = TextEditingController(text: l.longitude?.toString() ?? '');
    _placeId = TextEditingController(text: l.placeId ?? '');
    _capacity = TextEditingController(text: '${l.capacity}');
  }

  @override
  void dispose() {
    _address.dispose();
    _latitude.dispose();
    _longitude.dispose();
    _placeId.dispose();
    _capacity.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _error = null;
      _saved = false;
    });
    try {
      await ref
          .read(listingManagementActionsProvider)
          .updateListing(
            widget.listing,
            address: _address.text.trim(),
            latitude: double.tryParse(_latitude.text.trim()),
            longitude: double.tryParse(_longitude.text.trim()),
            placeId: _placeId.text.trim().isEmpty ? null : _placeId.text.trim(),
            capacity:
                int.tryParse(_capacity.text.trim()) ?? widget.listing.capacity,
          );
      if (mounted) setState(() => _saved = true);
    } catch (err) {
      if (mounted) {
        setState(() => _error = apiErrorMessage(ref.read(localeProvider), err));
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    return Stack(
      children: [
        ListView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            96,
          ),
          children: [
            TextFormField(
              controller: _address,
              maxLines: 2,
              decoration: InputDecoration(
                labelText: t(locale, ru: 'Адрес', kz: 'Мекенжай'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _latitude,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Latitude'),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextFormField(
                    controller: _longitude,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                      signed: true,
                    ),
                    decoration: const InputDecoration(labelText: 'Longitude'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _placeId,
              decoration: const InputDecoration(labelText: 'Google Place ID'),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _capacity,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: t(
                  locale,
                  ru: 'Общая вместимость',
                  kz: 'Жалпы сыйымдылық',
                ),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                _error!,
                style: TextStyle(
                  color: context.mereytoiColors.error,
                  fontSize: 13,
                ),
              ),
            ],
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: context.mereytoiColors.surfaceElevated,
              border: Border(
                top: BorderSide(color: context.mereytoiColors.divider),
              ),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _saving ? null : _save,
                    icon: _saving
                        ? SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2.2,
                              color: context.mereytoiColors.onGold,
                            ),
                          )
                        : Icon(
                            _saved ? Icons.check_rounded : Icons.save_outlined,
                            size: 18,
                          ),
                    label: Text(
                      _saved
                          ? t(locale, ru: 'Сохранено', kz: 'Сақталды')
                          : t(locale, ru: 'Сохранить', kz: 'Сақтау'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
