import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/error_messages.dart';
import '../../../../models/category.dart';
import '../../../../models/city.dart';
import '../../../../models/listing.dart';
import '../../../../state/categories_provider.dart';
import '../../../../state/city_provider.dart';
import '../../../../state/listings_provider.dart';
import '../../../../state/locale_provider.dart';
import '../../../../state/provider_onboarding.dart';
import '../../../../state/provider_provider.dart';
import '../../../../state/providers.dart';
import '../../../../widgets/city_selector.dart';
import '../../../../widgets/network_image_box.dart';
import '../../../../widgets/provider/provider_form_widgets.dart';
import '../../../../widgets/services/services_category_grid.dart';

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

/// Photos per service, same cap as the onboarding.
const _maxPhotos = kMaxOnboardingPhotos;

/// «Добавить услугу» / «Изменить услугу» — opens the full-screen service
/// form. Pass [existing] to edit. Resolves to true once saved.
Future<bool?> openProviderServiceForm(
  BuildContext context, {
  Listing? existing,
}) {
  return Navigator.of(context).push<bool>(
    MaterialPageRoute(
      fullscreenDialog: true,
      builder: (_) => ProviderServiceFormScreen(existing: existing),
    ),
  );
}

/// The provider's own add/edit service form, in the onboarding's premium
/// style: Основное, Стоимость, Категория, Город, Фотографии, Дополнительно.
/// The city comes only from the directory (canonical name saved), the
/// category from the same tiles as the onboarding, and photos upload as
/// they're picked (preview, delete, reorder, retry). The service is always
/// created for the signed-in user's own provider profile — the backend
/// binds it to the JWT, there's nothing to choose.
class ProviderServiceFormScreen extends ConsumerStatefulWidget {
  const ProviderServiceFormScreen({super.key, this.existing});

  final Listing? existing;

  @override
  ConsumerState<ProviderServiceFormScreen> createState() =>
      _ProviderServiceFormScreenState();
}

/// A photo in the form: an already-uploaded URL, or a local file being or
/// failing to be uploaded.
class _FormPhoto {
  const _FormPhoto({this.url, this.path, this.failed = false});

  final String? url;
  final String? path;
  final bool failed;

  bool get uploading => url == null && !failed;
}

class _ProviderServiceFormScreenState
    extends ConsumerState<ProviderServiceFormScreen> {
  late final TextEditingController _name;
  late final TextEditingController _description;
  late final TextEditingController _price;
  late final TextEditingController _nameKz;
  late final TextEditingController _descriptionKz;
  Category? _category;
  City? _city;
  late String _priceType;
  late List<_FormPhoto> _photos;
  bool _submitted = false;
  bool _saving = false;
  String? _error;

  bool get _isEdit => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _name = TextEditingController(text: e?.nameRu ?? '');
    _description = TextEditingController(text: e?.descriptionRu ?? '');
    _price = TextEditingController(text: e != null ? '${e.price}' : '');
    // Kazakh variants are optional extras: shown only when they actually
    // differ from the Russian text (the onboarding saves the same text in
    // both), and an empty one falls back to the Russian text on save.
    _nameKz = TextEditingController(
      text: e != null && e.nameKz != e.nameRu ? e.nameKz : '',
    );
    _descriptionKz = TextEditingController(
      text: e != null && e.descriptionKz != e.descriptionRu
          ? e.descriptionKz
          : '',
    );
    _priceType = e?.priceType?.isNotEmpty == true ? e!.priceType! : 'fixed';
    _photos = [
      for (final u in e?.imageUrls ?? const <String>[]) _FormPhoto(url: u),
    ];
    _prefillSelections();
  }

  /// Category: the service's own, or (new service) the provider's latest
  /// one. City: the service's own, or the provider profile's, matched to
  /// the directory so the canonical name is saved.
  Future<void> _prefillSelections() async {
    final e = widget.existing;
    try {
      final categories = await ref.read(categoriesProvider.future);
      int? categoryId = e?.categoryId;
      if (categoryId == null) {
        final mine = ref.read(myListingsProvider).valueOrNull ?? const [];
        final candidates = mine.where(
          (l) => !categories.any(
            (c) =>
                c.id == l.categoryId &&
                kExcludedProviderCategorySlugs.contains(c.slug),
          ),
        );
        if (candidates.isNotEmpty) categoryId = candidates.last.categoryId;
      }
      final category = categories
          .where(
            (c) =>
                c.id == categoryId &&
                !kExcludedProviderCategorySlugs.contains(c.slug),
          )
          .firstOrNull;
      if (mounted && _category == null && category != null) {
        setState(() => _category = category);
      }
    } catch (_) {}
    try {
      final cities = await ref.read(citiesProvider.future);
      var wanted = e?.city ?? '';
      if (wanted.trim().isEmpty) {
        wanted = (await ref.read(providerProfileProvider.future))?.city ?? '';
      }
      final key = wanted.trim().toLowerCase();
      if (key.isEmpty) return;
      final city = cities
          .where(
            (c) => [
              c.nameRu,
              c.nameKz,
              c.nameEn,
            ].any((n) => n.trim().toLowerCase() == key),
          )
          .firstOrNull;
      if (mounted && _city == null && city != null) {
        setState(() => _city = city);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    for (final c in [_name, _description, _price, _nameKz, _descriptionKz]) {
      c.dispose();
    }
    super.dispose();
  }

  // ---- validation ----

  String? get _nameError => _name.text.trim().isEmpty
      ? t(
          _locale,
          ru: 'Укажите название',
          kz: 'Атауын көрсетіңіз',
          en: 'Enter a name',
        )
      : null;

  String? get _priceError {
    final v = int.tryParse(_price.text.trim());
    return v == null || v < 0
        ? t(
            _locale,
            ru: 'Укажите цену числом',
            kz: 'Бағаны санмен көрсетіңіз',
            en: 'Enter the price as a number',
          )
        : null;
  }

  String? get _categoryError => _category == null
      ? t(
          _locale,
          ru: 'Выберите категорию',
          kz: 'Санатты таңдаңыз',
          en: 'Select a category',
        )
      : null;

  String? get _cityError => _city == null
      ? t(
          _locale,
          ru: 'Выберите город',
          kz: 'Қаланы таңдаңыз',
          en: 'Select a city',
        )
      : null;

  bool get _photosBusy => _photos.any((p) => p.uploading);
  bool get _photosFailed => _photos.any((p) => p.failed);

  AppLocale get _locale => ref.read(localeProvider);

  bool get _valid =>
      _nameError == null &&
      _priceError == null &&
      _categoryError == null &&
      _cityError == null;

  // ---- photos ----

  Future<void> _addPhotos() async {
    final List<String> paths;
    try {
      paths = await ref.read(onboardingPhotoPickerProvider)();
    } catch (_) {
      return; // picker cancelled/unavailable — nothing changes
    }
    final room = _maxPhotos - _photos.length;
    if (paths.isEmpty || room <= 0) return;
    final added = [for (final p in paths.take(room)) _FormPhoto(path: p)];
    setState(() => _photos = [..._photos, ...added]);
    await _upload(added.map((p) => p.path!).toList());
  }

  Future<void> _upload(List<String> paths) async {
    try {
      final urls = await ref.read(uploadServiceProvider).uploadImages(paths);
      if (!mounted) return;
      setState(() {
        _photos = [
          for (final p in _photos)
            if (p.path != null && paths.contains(p.path) && p.url == null)
              _FormPhoto(path: p.path, url: urls[paths.indexOf(p.path!)])
            else
              p,
        ];
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _photos = [
          for (final p in _photos)
            if (p.path != null && paths.contains(p.path) && p.url == null)
              _FormPhoto(path: p.path, failed: true)
            else
              p,
        ];
      });
    }
  }

  void _retryPhoto(int index) {
    final path = _photos[index].path;
    if (path == null) return;
    setState(() => _photos[index] = _FormPhoto(path: path));
    _upload([path]);
  }

  void _removePhoto(int index) =>
      setState(() => _photos = [..._photos]..removeAt(index));

  void _movePhoto(int from, int to) {
    if (from == to) return;
    setState(() {
      final photos = [..._photos];
      photos.insert(to, photos.removeAt(from));
      _photos = photos;
    });
  }

  // ---- save ----

  Future<void> _save() async {
    if (_saving) return; // a second tap while saving does nothing
    FocusScope.of(context).unfocus();
    setState(() {
      _submitted = true;
      _error = null;
    });
    if (!_valid || _photosBusy || _photosFailed) return;

    final locale = _locale;
    final messenger = ScaffoldMessenger.of(context);
    final navigator = Navigator.of(context);
    setState(() => _saving = true);

    final name = _name.text.trim();
    final description = _description.text.trim();
    final nameKz = _nameKz.text.trim().isEmpty ? name : _nameKz.text.trim();
    final descriptionKz = _descriptionKz.text.trim().isEmpty
        ? description
        : _descriptionKz.text.trim();
    final price = int.parse(_price.text.trim());
    final imageUrls = [for (final p in _photos) p.url!];

    try {
      final actions = ref.read(providerActionsProvider);
      if (_isEdit) {
        await actions.updateListing(
          widget.existing!,
          categoryId: _category!.id,
          nameRu: name,
          nameKz: nameKz,
          descriptionRu: description,
          descriptionKz: descriptionKz,
          city: _city!.nameRu,
          price: price,
          priceType: _priceType,
          imageUrls: imageUrls,
        );
      } else {
        await actions.createListing(
          categoryId: _category!.id,
          nameRu: name,
          nameKz: nameKz,
          descriptionRu: description,
          descriptionKz: descriptionKz,
          city: _city!.nameRu,
          price: price,
          priceType: _priceType,
          imageUrls: imageUrls,
        );
      }
      if (!mounted) return;
      navigator.pop(true);
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(
            _isEdit
                ? t(
                    locale,
                    ru: 'Изменения сохранены',
                    kz: 'Өзгерістер сақталды',
                    en: 'Changes saved',
                  )
                : t(
                    locale,
                    ru: 'Услуга опубликована',
                    kz: 'Қызмет жарияланды',
                    en: 'Service published',
                  ),
          ),
        ),
      );
    } catch (err) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = apiErrorMessage(locale, err);
      });
    }
  }

  // ---- UI ----

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);
    final colors = context.mereytoiColors;
    final show = _submitted;

    return Scaffold(
      backgroundColor: colors.backgroundPrimary,
      appBar: AppBar(
        backgroundColor: colors.backgroundPrimary,
        leading: IconButton(
          tooltip: t(locale, ru: 'Закрыть', kz: 'Жабу', en: 'Close'),
          icon: const Icon(Icons.close_rounded),
          onPressed: _saving ? null : () => Navigator.of(context).pop(),
        ),
        title: Text(
          _isEdit
              ? t(
                  locale,
                  ru: 'Изменить услугу',
                  kz: 'Қызметті өзгерту',
                  en: 'Edit service',
                )
              : t(
                  locale,
                  ru: 'Новая услуга',
                  kz: 'Жаңа қызмет',
                  en: 'New service',
                ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.xs,
                AppSpacing.md,
                AppSpacing.xl,
              ),
              children: [
                _Section(
                  title: t(locale, ru: 'Основное', kz: 'Негізгі', en: 'Basics'),
                  child: Column(
                    children: [
                      ProviderTextField(
                        fieldKey: const ValueKey('service-name'),
                        label: t(
                          locale,
                          ru: 'Название',
                          kz: 'Атауы',
                          en: 'Name',
                        ),
                        hint: t(
                          locale,
                          ru: 'Например, Проведение тоя',
                          kz: 'Мысалы, Той жүргізу',
                          en: 'e.g. Wedding hosting',
                        ),
                        controller: _name,
                        maxLength: 200,
                        errorText: show ? _nameError : null,
                        onChanged: (_) => setState(() {}),
                      ),
                      ProviderTextField(
                        fieldKey: const ValueKey('service-description'),
                        label: t(
                          locale,
                          ru: 'Описание',
                          kz: 'Сипаттама',
                          en: 'Description',
                        ),
                        hint: t(
                          locale,
                          ru: 'Что входит, длительность, особенности',
                          kz: 'Не кіреді, ұзақтығы, ерекшеліктері',
                          en: 'What\'s included, duration, highlights',
                        ),
                        controller: _description,
                        maxLength: 2000,
                        minLines: 3,
                        maxLines: 6,
                        onChanged: (_) {},
                      ),
                    ],
                  ),
                ),
                _Section(
                  title: t(locale, ru: 'Стоимость', kz: 'Құны', en: 'Price'),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ProviderTextField(
                        fieldKey: const ValueKey('service-price'),
                        label: t(locale, ru: 'Цена', kz: 'Бағасы', en: 'Price'),
                        hint: '50 000',
                        suffixText: '₸',
                        controller: _price,
                        keyboardType: TextInputType.number,
                        inputFormatters: [
                          FilteringTextInputFormatter.digitsOnly,
                        ],
                        maxLength: 9,
                        errorText: show ? _priceError : null,
                        onChanged: (_) => setState(() {}),
                      ),
                      Wrap(
                        spacing: AppSpacing.xs,
                        runSpacing: AppSpacing.xs,
                        children: [
                          for (final pt in _priceTypes)
                            _Pill(
                              key: ValueKey('price-type-${pt.value}'),
                              label: t(locale, ru: pt.ru, kz: pt.kz, en: pt.en),
                              selected: _priceType == pt.value,
                              onTap: () =>
                                  setState(() => _priceType = pt.value),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                _Section(
                  title: t(
                    locale,
                    ru: 'Категория',
                    kz: 'Санат',
                    en: 'Category',
                  ),
                  plain: true,
                  child: ProviderPickerCard(
                    tapKey: const ValueKey('service-category'),
                    icon: _category == null
                        ? Icons.category_outlined
                        : servicesCategoryIcon(_category!.slug),
                    value: _category?.name(locale),
                    placeholder: t(
                      locale,
                      ru: 'Выберите категорию',
                      kz: 'Санатты таңдаңыз',
                      en: 'Select a category',
                    ),
                    errorText: show ? _categoryError : null,
                    onTap: () async {
                      final picked = await showProviderCategoryPicker(
                        context,
                        selectedId: _category?.id,
                      );
                      if (picked != null) setState(() => _category = picked);
                    },
                  ),
                ),
                _Section(
                  title: t(locale, ru: 'Город', kz: 'Қала', en: 'City'),
                  plain: true,
                  child: ProviderPickerCard(
                    tapKey: const ValueKey('service-city'),
                    icon: Icons.location_on_rounded,
                    value: _city?.name(locale),
                    placeholder: t(
                      locale,
                      ru: 'Выберите город',
                      kz: 'Қаланы таңдаңыз',
                      en: 'Select a city',
                    ),
                    errorText: show ? _cityError : null,
                    onTap: () async {
                      final picked = await showCityPicker(
                        context,
                        selectedId: _city?.id,
                      );
                      if (picked != null) setState(() => _city = picked);
                    },
                  ),
                ),
                _Section(
                  title: t(
                    locale,
                    ru: 'Фотографии',
                    kz: 'Фотосуреттер',
                    en: 'Photos',
                  ),
                  child: _PhotoGrid(
                    photos: _photos,
                    locale: locale,
                    onAdd: _photos.length < _maxPhotos ? _addPhotos : null,
                    onRemove: _removePhoto,
                    onRetry: _retryPhoto,
                    onMove: _movePhoto,
                  ),
                ),
                _Section(
                  title: t(
                    locale,
                    ru: 'Дополнительно',
                    kz: 'Қосымша',
                    en: 'Additional',
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Padding(
                        padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                        child: Text(
                          t(
                            locale,
                            ru: 'Текст на казахском. Если не заполнить — покажем русский вариант.',
                            kz: 'Қазақша мәтін. Толтырмасаңыз — орысша нұсқасы көрсетіледі.',
                            en: 'Kazakh text. If left empty, the Russian text is shown.',
                          ),
                          style: Theme.of(context).textTheme.bodySmall
                              ?.copyWith(color: colors.textSecondary),
                        ),
                      ),
                      ProviderTextField(
                        fieldKey: const ValueKey('service-name-kz'),
                        label: t(
                          locale,
                          ru: 'Название на казахском',
                          kz: 'Атауы қазақша',
                          en: 'Name in Kazakh',
                        ),
                        controller: _nameKz,
                        maxLength: 200,
                        onChanged: (_) {},
                      ),
                      ProviderTextField(
                        fieldKey: const ValueKey('service-description-kz'),
                        label: t(
                          locale,
                          ru: 'Описание на казахском',
                          kz: 'Сипаттамасы қазақша',
                          en: 'Description in Kazakh',
                        ),
                        controller: _descriptionKz,
                        maxLength: 2000,
                        minLines: 2,
                        maxLines: 5,
                        onChanged: (_) {},
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          _BottomBar(
            locale: locale,
            isEdit: _isEdit,
            saving: _saving,
            photosBusy: _photosBusy,
            photosFailed: _photosFailed,
            error: _error,
            onSave: _save,
          ),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({
    required this.title,
    required this.child,
    this.plain = false,
  });

  final String title;
  final Widget child;

  /// The child is already a card (pickers) — no extra card around it.
  final bool plain;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(left: 4, bottom: AppSpacing.xs),
            child: Text(
              title,
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: colors.goldMuted,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          if (plain)
            child
          else
            // Full width even when the content is narrow (e.g. no photos
            // yet — just the add tile).
            SizedBox(
              width: double.infinity,
              child: DecoratedBox(
                decoration: providerCardDecoration(context),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.md,
                    AppSpacing.xs,
                  ),
                  child: child,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    return Semantics(
      button: true,
      selected: selected,
      child: Material(
        color: selected
            ? colors.goldPrimary.withValues(alpha: 0.12)
            : colors.surfaceSoft.withValues(alpha: 0.6),
        shape: StadiumBorder(
          side: BorderSide(
            color: selected ? colors.goldPrimary : Colors.transparent,
            width: 1.4,
          ),
        ),
        child: InkWell(
          customBorder: const StadiumBorder(),
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 44),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
              child: Center(
                widthFactor: 1,
                child: Text(
                  label,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: colors.textPrimary,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Three-column photo grid: cover badge on the first, delete on each,
/// long-press drag to reorder, spinner while uploading, tap-to-retry on a
/// failed upload, and an «Добавить фото» tile while there's room.
class _PhotoGrid extends StatelessWidget {
  const _PhotoGrid({
    required this.photos,
    required this.locale,
    required this.onAdd,
    required this.onRemove,
    required this.onRetry,
    required this.onMove,
  });

  final List<_FormPhoto> photos;
  final AppLocale locale;
  final VoidCallback? onAdd;
  final ValueChanged<int> onRemove;
  final ValueChanged<int> onRetry;
  final void Function(int from, int to) onMove;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              const gap = AppSpacing.xs;
              final size = (constraints.maxWidth - gap * 2) / 3;
              return Wrap(
                spacing: gap,
                runSpacing: gap,
                children: [
                  for (var i = 0; i < photos.length; i++)
                    _draggable(context, i, size),
                  if (onAdd != null) _addTile(context, size),
                ],
              );
            },
          ),
          if (photos.length > 1) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              t(
                locale,
                ru: 'Первое фото — обложка. Удерживайте фото, чтобы изменить порядок.',
                kz: 'Бірінші фото — мұқаба. Ретін өзгерту үшін фотоны басып тұрыңыз.',
                en: 'The first photo is the cover. Long-press a photo to reorder.',
              ),
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colors.textSecondary),
            ),
          ],
        ],
      ),
    );
  }

  Widget _draggable(BuildContext context, int i, double size) {
    final tile = _thumb(context, i, size);
    return LongPressDraggable<int>(
      key: ValueKey('service-photo-$i'),
      data: i,
      feedback: Material(
        color: Colors.transparent,
        child: Opacity(opacity: 0.9, child: _thumb(context, i, size)),
      ),
      childWhenDragging: Opacity(opacity: 0.3, child: tile),
      child: DragTarget<int>(
        onWillAcceptWithDetails: (d) => d.data != i,
        onAcceptWithDetails: (d) => onMove(d.data, i),
        builder: (context, candidate, _) => AnimatedScale(
          scale: candidate.isEmpty ? 1 : 0.94,
          duration: const Duration(milliseconds: 120),
          child: tile,
        ),
      ),
    );
  }

  Widget _thumb(BuildContext context, int i, double size) {
    final colors = context.mereytoiColors;
    final p = photos[i];
    final image = p.path != null
        ? Image.file(
            File(p.path!),
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => ColoredBox(color: colors.surfaceSoft),
          )
        : NetworkImageBox(url: ApiConfig.mediaUrl(p.url), borderRadius: 0);
    return SizedBox(
      width: size,
      height: size,
      child: Stack(
        children: [
          Positioned.fill(
            child: Container(
              foregroundDecoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: i == 0 ? colors.goldPrimary : colors.border,
                  width: i == 0 ? 1.5 : 1,
                ),
              ),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(16),
                child: image,
              ),
            ),
          ),
          if (p.uploading)
            Positioned.fill(
              child: DecoratedBox(
                key: ValueKey('service-photo-uploading-$i'),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.4,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
            ),
          if (p.failed)
            Positioned.fill(
              child: Material(
                color: Colors.black.withValues(alpha: 0.5),
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  key: ValueKey('service-photo-retry-$i'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => onRetry(i),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.refresh_rounded, color: Colors.white),
                        Text(
                          t(
                            locale,
                            ru: 'Повторить',
                            kz: 'Қайталау',
                            en: 'Retry',
                          ),
                          style: Theme.of(
                            context,
                          ).textTheme.labelSmall?.copyWith(color: Colors.white),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          if (i == 0 && !p.failed)
            Positioned(
              left: 6,
              bottom: 6,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colors.goldPrimary,
                  borderRadius: BorderRadius.circular(AppRadius.chip),
                ),
                child: Text(
                  t(locale, ru: 'Обложка', kz: 'Мұқаба', en: 'Cover'),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.onGold,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          Positioned(
            top: 0,
            right: 0,
            child: SizedBox(
              width: 44,
              height: 44,
              child: IconButton(
                key: ValueKey('service-photo-remove-$i'),
                tooltip: t(locale, ru: 'Удалить', kz: 'Жою', en: 'Remove'),
                onPressed: () => onRemove(i),
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
          ),
        ],
      ),
    );
  }

  Widget _addTile(BuildContext context, double size) {
    final colors = context.mereytoiColors;
    return SizedBox(
      width: size,
      height: size,
      child: Material(
        color: colors.goldPrimary.withValues(alpha: 0.06),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: colors.goldPrimary.withValues(alpha: 0.5)),
        ),
        child: InkWell(
          key: const ValueKey('service-add-photo'),
          borderRadius: BorderRadius.circular(16),
          onTap: onAdd,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xs),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.add_photo_alternate_outlined,
                  color: colors.goldPrimary,
                  size: 28,
                ),
                const SizedBox(height: 4),
                Text(
                  t(
                    locale,
                    ru: 'Добавить фото',
                    kz: 'Фото қосу',
                    en: 'Add photo',
                  ),
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: colors.goldMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({
    required this.locale,
    required this.isEdit,
    required this.saving,
    required this.photosBusy,
    required this.photosFailed,
    required this.error,
    required this.onSave,
  });

  final AppLocale locale;
  final bool isEdit;
  final bool saving;
  final bool photosBusy;
  final bool photosFailed;
  final String? error;
  final VoidCallback onSave;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    final note =
        error ??
        (photosBusy
            ? t(
                locale,
                ru: 'Дождитесь загрузки фото',
                kz: 'Фото жүктелуін күтіңіз',
                en: 'Wait for the photos to upload',
              )
            : photosFailed
            ? t(
                locale,
                ru: 'Некоторые фото не загрузились — повторите или удалите их',
                kz: 'Кейбір фотолар жүктелмеді — қайталаңыз немесе жойыңыз',
                en: 'Some photos failed — retry or remove them',
              )
            : null);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: colors.backgroundPrimary,
        border: Border(top: BorderSide(color: colors.border)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (note != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                  child: Text(
                    note,
                    key: const ValueKey('service-form-note'),
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: error != null || photosFailed
                          ? colors.error
                          : colors.textSecondary,
                    ),
                  ),
                ),
              SizedBox(
                height: 52,
                child: ElevatedButton(
                  key: const ValueKey('service-submit'),
                  onPressed: saving || photosBusy ? null : onSave,
                  child: saving
                      ? SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: colors.onGold,
                          ),
                        )
                      : Text(
                          isEdit
                              ? t(
                                  locale,
                                  ru: 'Сохранить изменения',
                                  kz: 'Өзгерістерді сақтау',
                                  en: 'Save changes',
                                )
                              : t(
                                  locale,
                                  ru: 'Опубликовать услугу',
                                  kz: 'Қызметті жариялау',
                                  en: 'Publish service',
                                ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
