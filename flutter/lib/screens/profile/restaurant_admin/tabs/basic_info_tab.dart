import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/error_messages.dart';
import '../../../../models/listing.dart';
import '../../../../state/listing_management_actions.dart';
import '../../../../state/locale_provider.dart';

/// "Основное" tab — the listing's own core fields, via the same
/// full-replace `PUT /api/listings/:id` the "Адрес" tab also writes
/// through (see `ListingManagementService.updateListing`'s own doc
/// comment: every field not touched here is carried over unchanged from
/// [listing], never blanked).
class BasicInfoTab extends ConsumerStatefulWidget {
  const BasicInfoTab({super.key, required this.listing});

  final Listing listing;

  @override
  ConsumerState<BasicInfoTab> createState() => _BasicInfoTabState();
}

class _BasicInfoTabState extends ConsumerState<BasicInfoTab> {
  late final TextEditingController _nameRu;
  late final TextEditingController _nameKz;
  late final TextEditingController _descriptionRu;
  late final TextEditingController _descriptionKz;
  late final TextEditingController _city;
  late final TextEditingController _phone;
  late final TextEditingController _price;
  late final TextEditingController _minGuests;
  late final TextEditingController _maxGuests;
  bool _saving = false;
  String? _error;
  bool _saved = false;

  @override
  void initState() {
    super.initState();
    final l = widget.listing;
    _nameRu = TextEditingController(text: l.nameRu);
    _nameKz = TextEditingController(text: l.nameKz);
    _descriptionRu = TextEditingController(text: l.descriptionRu);
    _descriptionKz = TextEditingController(text: l.descriptionKz);
    _city = TextEditingController(text: l.city);
    _phone = TextEditingController(text: l.phone);
    _price = TextEditingController(text: '${l.price}');
    _minGuests = TextEditingController(text: '${l.minGuests}');
    _maxGuests = TextEditingController(text: '${l.maxGuests}');
  }

  @override
  void dispose() {
    _nameRu.dispose();
    _nameKz.dispose();
    _descriptionRu.dispose();
    _descriptionKz.dispose();
    _city.dispose();
    _phone.dispose();
    _price.dispose();
    _minGuests.dispose();
    _maxGuests.dispose();
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
            nameRu: _nameRu.text.trim(),
            nameKz: _nameKz.text.trim(),
            descriptionRu: _descriptionRu.text.trim(),
            descriptionKz: _descriptionKz.text.trim(),
            city: _city.text.trim(),
            phone: _phone.text.trim(),
            price: int.tryParse(_price.text.trim()) ?? widget.listing.price,
            minGuests:
                int.tryParse(_minGuests.text.trim()) ??
                widget.listing.minGuests,
            maxGuests:
                int.tryParse(_maxGuests.text.trim()) ??
                widget.listing.maxGuests,
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
              controller: _nameRu,
              decoration: InputDecoration(
                labelText: t(locale, ru: 'Название (RU)', kz: 'Атауы (RU)'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _nameKz,
              decoration: InputDecoration(
                labelText: t(locale, ru: 'Название (KZ)', kz: 'Атауы (KZ)'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _descriptionRu,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: t(locale, ru: 'Описание (RU)', kz: 'Сипаттама (RU)'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _descriptionKz,
              maxLines: 4,
              decoration: InputDecoration(
                labelText: t(locale, ru: 'Описание (KZ)', kz: 'Сипаттама (KZ)'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _city,
              decoration: InputDecoration(
                labelText: t(locale, ru: 'Город', kz: 'Қала'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: InputDecoration(
                labelText: t(locale, ru: 'Телефон', kz: 'Телефон'),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            TextFormField(
              controller: _price,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                labelText: t(
                  locale,
                  ru: 'Базовая цена (если применимо)',
                  kz: 'Негізгі баға (қажет болса)',
                ),
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              children: [
                Expanded(
                  child: TextFormField(
                    controller: _minGuests,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: t(locale, ru: 'Мин. гостей', kz: 'Мин. қонақ'),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextFormField(
                    controller: _maxGuests,
                    keyboardType: TextInputType.number,
                    decoration: InputDecoration(
                      labelText: t(
                        locale,
                        ru: 'Макс. гостей',
                        kz: 'Макс. қонақ',
                      ),
                    ),
                  ),
                ),
              ],
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
        // Sticky save CTA — mobile-first per the brief, not a plain inline
        // button buried at the bottom of a long scroll.
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
