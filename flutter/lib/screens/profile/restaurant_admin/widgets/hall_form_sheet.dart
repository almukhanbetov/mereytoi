import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/error_messages.dart';
import '../../../../models/listing_hall.dart';
import '../../../../state/listing_management_actions.dart';
import '../../../../state/locale_provider.dart';
import '../../../../state/provider_onboarding.dart';
import '../../../../state/providers.dart';
import '../../../../widgets/admin/form_sheet_scaffold.dart';
import '../../../../widgets/network_image_box.dart';
import '../../../../widgets/provider/picked_photos_sheet.dart';

/// Opens the add/edit-hall sheet — `existing == null` creates, otherwise
/// edits in place. Returns once saved (or dismissed); the caller doesn't
/// need the result — `ListingManagementActions` already invalidated
/// `listingHallsProvider` on success, so the halls tab (and the public
/// `RestaurantDetailScreen`, once reopened) just rebuild with fresh data.
Future<void> openHallFormSheet(
  BuildContext context, {
  required int listingId,
  ListingHall? existing,
  int nextSortOrder = 0,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => HallFormSheet(
      listingId: listingId,
      existing: existing,
      nextSortOrder: nextSortOrder,
    ),
  );
}

class HallFormSheet extends ConsumerStatefulWidget {
  const HallFormSheet({
    super.key,
    required this.listingId,
    this.existing,
    this.nextSortOrder = 0,
  });

  final int listingId;
  final ListingHall? existing;

  /// Where a new hall goes: the end of the list.
  final int nextSortOrder;

  @override
  ConsumerState<HallFormSheet> createState() => _HallFormSheetState();
}

class _HallFormSheetState extends ConsumerState<HallFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameRu;
  late final TextEditingController _nameKz;
  late final TextEditingController _descriptionRu;
  late final TextEditingController _descriptionKz;
  late final TextEditingController _capacity;
  late final TextEditingController _price;
  late bool _isActive;
  late List<String> _images;
  bool _uploading = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _nameRu = TextEditingController(text: e?.nameRu ?? '');
    _nameKz = TextEditingController(text: e?.nameKz ?? '');
    _descriptionRu = TextEditingController(text: e?.descriptionRu ?? '');
    _descriptionKz = TextEditingController(text: e?.descriptionKz ?? '');
    _capacity = TextEditingController(text: e != null ? '${e.capacity}' : '');
    _price = TextEditingController(text: e != null ? '${e.price}' : '');
    _isActive = e?.isActive ?? true;
    _images = [...?e?.imageUrls];
  }

  @override
  void dispose() {
    _nameRu.dispose();
    _nameKz.dispose();
    _descriptionRu.dispose();
    _descriptionKz.dispose();
    _capacity.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _addPhotos() async {
    final locale = ref.read(localeProvider);
    final List<String> paths;
    try {
      paths = await ref.read(onboardingPhotoPickerProvider)();
    } catch (_) {
      return; // picker cancelled or unavailable: nothing changes
    }
    if (paths.isEmpty || !mounted) return;
    final chosen = await confirmPickedPhotos(
      context,
      locale: locale,
      paths: paths,
    );
    if (chosen.isEmpty || !mounted) return;
    setState(() {
      _uploading = true;
      _error = null;
    });
    try {
      final urls = await ref.read(uploadServiceProvider).uploadImages(chosen);
      if (mounted) setState(() => _images = [..._images, ...urls]);
    } catch (err) {
      if (mounted) setState(() => _error = apiErrorMessage(locale, err));
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _save() async {
    if (_uploading) return;
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final actions = ref.read(listingManagementActionsProvider);
      if (widget.existing == null) {
        await actions.createHall(
          widget.listingId,
          nameRu: _nameRu.text.trim(),
          nameKz: _nameKz.text.trim(),
          descriptionRu: _descriptionRu.text.trim(),
          descriptionKz: _descriptionKz.text.trim(),
          capacity: int.tryParse(_capacity.text.trim()) ?? 0,
          price: int.tryParse(_price.text.trim()) ?? 0,
          imageUrls: _images,
          isActive: _isActive,
          sortOrder: widget.nextSortOrder,
        );
      } else {
        await actions.updateHall(
          widget.listingId,
          widget.existing!,
          nameRu: _nameRu.text.trim(),
          nameKz: _nameKz.text.trim(),
          descriptionRu: _descriptionRu.text.trim(),
          descriptionKz: _descriptionKz.text.trim(),
          capacity: int.tryParse(_capacity.text.trim()) ?? 0,
          price: int.tryParse(_price.text.trim()) ?? 0,
          imageUrls: _images,
          isActive: _isActive,
          sortOrder: widget.existing!.sortOrder,
        );
      }
      if (mounted) Navigator.of(context).pop();
    } catch (err) {
      if (mounted) {
        setState(() {
          _error = apiErrorMessage(ref.read(localeProvider), err);
          _saving = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final isEdit = widget.existing != null;
    return FormSheetScaffold(
      title: isEdit
          ? t(locale, ru: 'Редактировать зал', kz: 'Залды өңдеу')
          : t(locale, ru: 'Добавить зал', kz: 'Зал қосу'),
      formKey: _formKey,
      onSave: _save,
      saving: _saving,
      error: _error,
      saveLabel: t(locale, ru: 'Сохранить', kz: 'Сақтау'),
      children: [
        TextFormField(
          controller: _nameRu,
          decoration: InputDecoration(
            labelText: t(locale, ru: 'Название (RU)', kz: 'Атауы (RU)'),
          ),
          validator: (v) => (v == null || v.trim().isEmpty)
              ? t(locale, ru: 'Введите название', kz: 'Атауын енгізіңіз')
              : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: _nameKz,
          decoration: InputDecoration(
            labelText: t(locale, ru: 'Название (KZ)', kz: 'Атауы (KZ)'),
          ),
          validator: (v) => (v == null || v.trim().isEmpty)
              ? t(locale, ru: 'Введите название', kz: 'Атауын енгізіңіз')
              : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: _descriptionRu,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: t(
              locale,
              ru: 'Описание RU (необязательно)',
              kz: 'Сипаттама RU (міндетті емес)',
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: _descriptionKz,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: t(
              locale,
              ru: 'Описание KZ (необязательно)',
              kz: 'Сипаттама KZ (міндетті емес)',
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                key: const ValueKey('hall-capacity'),
                controller: _capacity,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: t(locale, ru: 'Вместимость', kz: 'Сыйымдылық'),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: TextFormField(
                key: const ValueKey('hall-price'),
                controller: _price,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: t(
                    locale,
                    ru: 'Цена, ₸',
                    kz: 'Баға, ₸',
                    en: 'Price, ₸',
                  ),
                  helperText: t(
                    locale,
                    ru: '0 — как у ресторана',
                    kz: '0 — мейрамхана бағасы',
                    en: '0: the restaurant\'s price',
                  ),
                  helperMaxLines: 2,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        _HallPhotos(
          locale: locale,
          images: _images,
          uploading: _uploading,
          onAdd: _uploading ? null : _addPhotos,
          onRemove: (url) => setState(
            () => _images = [
              for (final u in _images)
                if (u != url) u,
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(t(locale, ru: 'Активен', kz: 'Белсенді')),
          value: _isActive,
          onChanged: (v) => setState(() => _isActive = v),
        ),
      ],
    );
  }
}

/// The hall's photos, the first is its cover, as in the admin's hall form.
class _HallPhotos extends StatelessWidget {
  const _HallPhotos({
    required this.locale,
    required this.images,
    required this.uploading,
    required this.onAdd,
    required this.onRemove,
  });

  final AppLocale locale;
  final List<String> images;
  final bool uploading;
  final VoidCallback? onAdd;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    final textTheme = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          t(locale, ru: 'Фото зала', kz: 'Зал фотосы', en: 'Hall photos'),
          style: textTheme.labelLarge?.copyWith(color: colors.textSecondary),
        ),
        const SizedBox(height: AppSpacing.xs),
        Wrap(
          spacing: AppSpacing.xs,
          runSpacing: AppSpacing.xs,
          children: [
            for (var i = 0; i < images.length; i++)
              SizedBox(
                key: ValueKey('hall-photo-$i'),
                width: 88,
                height: 88,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: NetworkImageBox(
                        url: ApiConfig.mediaUrl(images[i]),
                        borderRadius: 0,
                      ),
                    ),
                    if (i == 0)
                      Positioned(
                        left: 4,
                        bottom: 4,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: colors.goldPrimary,
                            borderRadius: BorderRadius.circular(AppRadius.chip),
                          ),
                          child: Text(
                            t(locale, ru: 'Обложка', kz: 'Мұқаба', en: 'Cover'),
                            style: textTheme.labelSmall?.copyWith(
                              color: colors.onGold,
                            ),
                          ),
                        ),
                      ),
                    Positioned(
                      top: -4,
                      right: -4,
                      child: IconButton(
                        key: ValueKey('hall-photo-remove-$i'),
                        tooltip: t(
                          locale,
                          ru: 'Удалить',
                          kz: 'Жою',
                          en: 'Remove',
                        ),
                        onPressed: () => onRemove(images[i]),
                        icon: Container(
                          width: 26,
                          height: 26,
                          decoration: const BoxDecoration(
                            color: Color(0x99000000),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.close_rounded,
                            size: 16,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            SizedBox(
              width: 88,
              height: 88,
              child: OutlinedButton(
                key: const ValueKey('hall-add-photo'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(48, 48),
                  padding: EdgeInsets.zero,
                ),
                onPressed: onAdd,
                child: uploading
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.4),
                      )
                    : const Icon(Icons.add_photo_alternate_outlined),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
