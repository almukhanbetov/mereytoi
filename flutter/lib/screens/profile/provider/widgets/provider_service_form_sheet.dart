import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/error_messages.dart';
import '../../../../models/category.dart';
import '../../../../models/listing.dart';
import '../../../../state/locale_provider.dart';
import '../../../../state/provider_provider.dart';
import '../../../../state/providers.dart';
import '../../../../widgets/admin/form_sheet_scaffold.dart';
import '../../../../widgets/network_image_box.dart';

const _priceTypes = [
  (value: 'fixed', ru: 'Фиксированная', kz: 'Тіркелген', en: 'Fixed'),
  (value: 'from', ru: 'От (минимальная)', kz: 'Бастап', en: 'From'),
  (value: 'per_hour', ru: 'За час', kz: 'Сағатына', en: 'Per hour'),
  (value: 'per_event', ru: 'За мероприятие', kz: 'Іс-шараға', en: 'Per event'),
  (
    value: 'negotiable',
    ru: 'Договорная',
    kz: 'Келісім бойынша',
    en: 'Negotiable',
  ),
];

/// "+ Добавить услугу" / "Изменить" — Этап 11 brief section 7, deliberately
/// compact: category, name, description, city, price + price type, plus,
/// since Этап 11F, a multi-photo picker (first photo = cover image).
Future<void> openProviderServiceFormSheet(
  BuildContext context, {
  required List<Category> categories,
  Listing? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ProviderServiceFormSheet(
      categories: categories,
      existing: existing,
    ),
  );
}

class ProviderServiceFormSheet extends ConsumerStatefulWidget {
  const ProviderServiceFormSheet({
    super.key,
    required this.categories,
    this.existing,
  });

  final List<Category> categories;
  final Listing? existing;

  @override
  ConsumerState<ProviderServiceFormSheet> createState() =>
      _ProviderServiceFormSheetState();
}

class _ProviderServiceFormSheetState
    extends ConsumerState<ProviderServiceFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameRu;
  late final TextEditingController _nameKz;
  late final TextEditingController _descriptionRu;
  late final TextEditingController _descriptionKz;
  late final TextEditingController _city;
  late final TextEditingController _price;
  int? _categoryId;
  late String _priceType;
  late List<String> _imageUrls;
  bool _uploadingPhotos = false;
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
    _city = TextEditingController(text: e?.city ?? '');
    _price = TextEditingController(text: e != null ? '${e.price}' : '');
    _categoryId = e?.categoryId ??
        (widget.categories.isNotEmpty ? widget.categories.first.id : null);
    _priceType = e?.priceType?.isNotEmpty == true ? e!.priceType! : 'fixed';
    _imageUrls = List<String>.from(e?.imageUrls ?? const []);
  }

  @override
  void dispose() {
    _nameRu.dispose();
    _nameKz.dispose();
    _descriptionRu.dispose();
    _descriptionKz.dispose();
    _city.dispose();
    _price.dispose();
    super.dispose();
  }

  Future<void> _pickPhotos() async {
    final List<XFile> picked;
    try {
      picked = await ImagePicker().pickMultiImage(imageQuality: 85);
    } catch (err) {
      // Same rationale as the avatar picker: a denied/unavailable picker
      // surfaces here rather than crashing the sheet, and every field the
      // user already filled in stays exactly as it was.
      if (mounted) {
        setState(
          () => _error = apiErrorMessage(ref.read(localeProvider), err),
        );
      }
      return;
    }
    if (picked.isEmpty) return; // user cancelled the picker

    setState(() {
      _uploadingPhotos = true;
      _error = null;
    });
    try {
      final urls = await ref
          .read(uploadServiceProvider)
          .uploadImages(picked.map((f) => f.path).toList());
      if (mounted) {
        setState(() => _imageUrls = [..._imageUrls, ...urls]);
      }
    } catch (err) {
      if (mounted) {
        setState(() => _error = apiErrorMessage(ref.read(localeProvider), err));
      }
    } finally {
      if (mounted) setState(() => _uploadingPhotos = false);
    }
  }

  void _removePhoto(int index) {
    setState(() => _imageUrls = [..._imageUrls]..removeAt(index));
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_categoryId == null) return;
    if (_uploadingPhotos) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final actions = ref.read(providerActionsProvider);
      if (widget.existing == null) {
        await actions.createListing(
          categoryId: _categoryId!,
          nameRu: _nameRu.text.trim(),
          nameKz: _nameKz.text.trim(),
          descriptionRu: _descriptionRu.text.trim(),
          descriptionKz: _descriptionKz.text.trim(),
          city: _city.text.trim(),
          price: int.tryParse(_price.text.trim()) ?? 0,
          priceType: _priceType,
          imageUrls: _imageUrls,
        );
      } else {
        await actions.updateListing(
          widget.existing!,
          nameRu: _nameRu.text.trim(),
          nameKz: _nameKz.text.trim(),
          descriptionRu: _descriptionRu.text.trim(),
          descriptionKz: _descriptionKz.text.trim(),
          city: _city.text.trim(),
          price: int.tryParse(_price.text.trim()) ?? 0,
          priceType: _priceType,
          imageUrls: _imageUrls,
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
          ? t(
              locale,
              ru: 'Изменить услугу',
              kz: 'Қызметті өзгерту',
              en: 'Edit service',
            )
          : t(
              locale,
              ru: 'Добавить услугу',
              kz: 'Қызмет қосу',
              en: 'Add service',
            ),
      formKey: _formKey,
      onSave: _save,
      saving: _saving,
      error: _error,
      saveLabel: t(locale, ru: 'Сохранить', kz: 'Сақтау', en: 'Save'),
      children: [
        Text(
          t(locale, ru: 'Фотографии', kz: 'Фотосуреттер', en: 'Photos'),
          style: Theme.of(context).textTheme.labelLarge,
        ),
        const SizedBox(height: AppSpacing.xs),
        SizedBox(
          height: 84,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              for (var i = 0; i < _imageUrls.length; i++)
                Padding(
                  padding: const EdgeInsets.only(right: AppSpacing.xs),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(AppRadius.md),
                        child: SizedBox(
                          width: 84,
                          height: 84,
                          child: NetworkImageBox(
                            url: ApiConfig.mediaUrl(_imageUrls[i]),
                            borderRadius: 0,
                          ),
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
                              color: Colors.black.withValues(alpha: 0.55),
                              borderRadius: BorderRadius.circular(AppRadius.sm),
                            ),
                            child: Text(
                              t(
                                locale,
                                ru: 'Главное',
                                kz: 'Басты',
                                en: 'Cover',
                              ),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 10,
                              ),
                            ),
                          ),
                        ),
                      Positioned(
                        right: 2,
                        top: 2,
                        child: GestureDetector(
                          onTap: () => _removePhoto(i),
                          child: Container(
                            padding: const EdgeInsets.all(2),
                            decoration: const BoxDecoration(
                              color: Colors.black54,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(
                              Icons.close,
                              color: Colors.white,
                              size: 14,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              InkWell(
                onTap: _uploadingPhotos ? null : _pickPhotos,
                borderRadius: BorderRadius.circular(AppRadius.md),
                child: Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppRadius.md),
                    border: Border.all(
                      color: context.mereytoiColors.border,
                    ),
                  ),
                  alignment: Alignment.center,
                  child: _uploadingPhotos
                      ? const SizedBox(
                          width: 24,
                          height: 24,
                          child: CircularProgressIndicator(strokeWidth: 2.4),
                        )
                      : Icon(
                          Icons.add_photo_alternate_outlined,
                          color: context.mereytoiColors.textSecondary,
                        ),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        TextButton(
          onPressed: _uploadingPhotos ? null : _pickPhotos,
          child: Text(
            t(locale, ru: 'Добавить фото', kz: 'Фото қосу', en: 'Add photo'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<int?>(
          initialValue: _categoryId,
          // Этап 11E QA finding: without isExpanded the dropdown sized
          // itself to its widest item's intrinsic width, overflowing the
          // sheet by ~39px for any long category name ("Мейрамханалар мен
          // локациялар") instead of shrinking/ellipsizing to fit.
          isExpanded: true,
          decoration: InputDecoration(
            labelText: t(locale, ru: 'Категория', kz: 'Санат', en: 'Category'),
          ),
          items: [
            for (final c in widget.categories)
              DropdownMenuItem<int?>(
                value: c.id,
                child: Text(c.name(locale), overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => setState(() => _categoryId = v),
          validator: (v) => v == null
              ? t(
                  locale,
                  ru: 'Выберите категорию',
                  kz: 'Санатты таңдаңыз',
                  en: 'Choose a category',
                )
              : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: _nameRu,
          decoration: InputDecoration(
            labelText: t(
              locale,
              ru: 'Название (RU)',
              kz: 'Атауы (RU)',
              en: 'Name (RU)',
            ),
          ),
          validator: (v) => (v == null || v.trim().isEmpty)
              ? t(
                  locale,
                  ru: 'Введите название',
                  kz: 'Атауын енгізіңіз',
                  en: 'Enter a name',
                )
              : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: _nameKz,
          decoration: InputDecoration(
            labelText: t(
              locale,
              ru: 'Название (KZ)',
              kz: 'Атауы (KZ)',
              en: 'Name (KZ)',
            ),
          ),
          validator: (v) => (v == null || v.trim().isEmpty)
              ? t(
                  locale,
                  ru: 'Введите название',
                  kz: 'Атауын енгізіңіз',
                  en: 'Enter a name',
                )
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
              en: 'Description RU (optional)',
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
              en: 'Description KZ (optional)',
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: _city,
          decoration: InputDecoration(
            labelText: t(locale, ru: 'Город', kz: 'Қала', en: 'City'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextFormField(
                controller: _price,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: t(
                    locale,
                    ru: 'Цена, ₸',
                    kz: 'Бағасы, ₸',
                    en: 'Price, ₸',
                  ),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _priceType,
                isExpanded: true,
                decoration: InputDecoration(
                  labelText: t(
                    locale,
                    ru: 'Тип цены',
                    kz: 'Баға түрі',
                    en: 'Price type',
                  ),
                ),
                items: [
                  for (final p in _priceTypes)
                    DropdownMenuItem<String>(
                      value: p.value,
                      child: Text(
                        t(locale, ru: p.ru, kz: p.kz, en: p.en),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) =>
                    setState(() => _priceType = v ?? 'fixed'),
              ),
            ),
          ],
        ),
      ],
    );
  }
}
