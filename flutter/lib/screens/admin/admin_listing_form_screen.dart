import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../core/config/api_config.dart';
import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../domain/admin/admin_listing_form.dart';
import '../../domain/restaurant/restaurant_category.dart';
import '../../models/category.dart';
import '../../models/listing.dart';
import '../../state/admin_providers.dart';
import '../../state/categories_provider.dart';
import '../../state/listing_management_actions.dart';
import '../../state/locale_provider.dart';
import '../../state/provider_onboarding.dart';
import '../../state/providers.dart';
import '../../widgets/network_image_box.dart';
import '../../widgets/provider/picked_photos_sheet.dart';
import '../../widgets/video_preview_card.dart';
import '../profile/restaurant_admin/restaurant_manage_screen.dart';
import 'admin_labels.dart';
import 'admin_widgets.dart';

/// Picks videos from the gallery (paths). A provider so tests can swap in
/// fixed files.
final adminVideoPickerProvider = Provider<Future<List<String>> Function()>(
  (ref) => () async {
    final picked = await ImagePicker().pickMultiVideo();
    return picked.map((f) => f.path).toList();
  },
);

/// «Новая услуга» from the mobile admin — the web admin's
/// /admin/services/new page. The category starts as [presetCategoryId]
/// (the restaurants one when opened from «Рестораны и локации»), like the
/// web's «+ Добавить услугу» on a category page. Created by an administrator
/// only: the server refuses POST /api/listings to anyone else.
///
/// After a restaurant is created its management screen opens — halls,
/// menus and address, the web's next step (its edit page tabs).
class AdminListingCreateScreen extends ConsumerWidget {
  const AdminListingCreateScreen({super.key, this.presetCategoryId});

  final int? presetCategoryId;

  static const title = 'Новая услуга';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return AdminGate(
      title: title,
      child: Scaffold(
        appBar: AppBar(title: const Text(title)),
        body: AdminListingForm(
          presetCategoryId: presetCategoryId,
          onCreated: (listing, category) {
            final nav = Navigator.of(context);
            if (category != null && isRestaurantCategory(category.slug)) {
              nav.pushReplacement(
                MaterialPageRoute(
                  builder: (_) => RestaurantManageScreen(listingId: listing.id),
                ),
              );
            } else {
              nav.pop();
              showAdminSnack(context, 'Услуга «${listing.nameRu}» создана');
            }
          },
          onCancel: () => Navigator.of(context).maybePop(),
        ),
      ),
    );
  }
}

/// ServiceForm.jsx on a phone: the same fields in the same order, one per
/// row instead of two. With [existing] it edits (the restaurant's «Основное»
/// tab for an administrator); without it, it creates.
class AdminListingForm extends ConsumerStatefulWidget {
  const AdminListingForm({
    super.key,
    this.existing,
    this.presetCategoryId,
    this.onCreated,
    this.onSaved,
    this.onCancel,
  });

  final Listing? existing;
  final int? presetCategoryId;
  final void Function(Listing listing, Category? category)? onCreated;
  final void Function(Listing listing, Category? category)? onSaved;
  final VoidCallback? onCancel;

  @override
  ConsumerState<AdminListingForm> createState() => _AdminListingFormState();
}

class _AdminListingFormState extends ConsumerState<AdminListingForm> {
  late final AdminListingValues _v;
  late final TextEditingController _nameRu;
  late final TextEditingController _nameKz;
  late final TextEditingController _descriptionRu;
  late final TextEditingController _descriptionKz;
  late final TextEditingController _city;
  late final TextEditingController _phone;
  late final TextEditingController _price;
  late final TextEditingController _rating;
  late final TextEditingController _minGuests;
  late final TextEditingController _maxGuests;
  late final TextEditingController _emoji;

  AdminListingErrors _errors = const AdminListingErrors();
  bool _submitting = false;
  bool _uploading = false;
  bool _uploadingVideo = false;
  bool _saved = false;
  String? _error;

  bool get _editing => widget.existing != null;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _v = e != null
        ? AdminListingValues.fromListing(e)
        : AdminListingValues(categoryId: widget.presetCategoryId);
    TextEditingController c(String text) => TextEditingController(text: text);
    _nameRu = c(_v.nameRu);
    _nameKz = c(_v.nameKz);
    _descriptionRu = c(_v.descriptionRu);
    _descriptionKz = c(_v.descriptionKz);
    _city = c(_v.city);
    _phone = c(_v.phone);
    _price = c(_v.price);
    _rating = c(_v.rating);
    _minGuests = c(_v.minGuests);
    _maxGuests = c(_v.maxGuests);
    _emoji = c(_v.emoji);
    // Any edit after a save means there's something to save again.
    for (final ctrl in [
      _nameRu,
      _nameKz,
      _descriptionRu,
      _descriptionKz,
      _city,
      _phone,
      _price,
      _rating,
      _minGuests,
      _maxGuests,
      _emoji,
    ]) {
      ctrl.addListener(_markDirty);
    }
  }

  void _markDirty() {
    if (_saved && mounted) setState(() => _saved = false);
  }

  @override
  void dispose() {
    for (final c in [
      _nameRu,
      _nameKz,
      _descriptionRu,
      _descriptionKz,
      _city,
      _phone,
      _price,
      _rating,
      _minGuests,
      _maxGuests,
      _emoji,
    ]) {
      c.dispose();
    }
    super.dispose();
  }

  void _readControllers() {
    _v
      ..nameRu = _nameRu.text
      ..nameKz = _nameKz.text
      ..descriptionRu = _descriptionRu.text
      ..descriptionKz = _descriptionKz.text
      ..city = _city.text
      ..phone = _phone.text
      ..price = _price.text
      ..rating = _rating.text
      ..minGuests = _minGuests.text
      ..maxGuests = _maxGuests.text
      ..emoji = _emoji.text;
  }

  String _uploadError(Object err, String fallback) {
    if (err is ApiException) {
      final m = err.debugMessage ?? '';
      if (m.startsWith('unsupported file type')) {
        return 'Этот формат файла не поддерживается';
      }
      if (m.contains('larger than 8MB')) return 'Фото больше 8 МБ';
      if (m.contains('larger than 200MB')) return 'Видео больше 200 МБ';
      if (m == 'failed to process video') {
        return 'Сервер не смог обработать видео';
      }
      final text = adminErrorText(err);
      if (!text.startsWith('Не удалось выполнить')) return text;
    }
    return fallback;
  }

  Future<void> _addPhotos() async {
    if (_uploading) return;
    final List<String> paths;
    try {
      paths = await ref.read(onboardingPhotoPickerProvider)();
    } catch (_) {
      return; // picker cancelled or unavailable: nothing changes
    }
    if (paths.isEmpty || !mounted) return;
    final chosen = await confirmPickedPhotos(
      context,
      locale: AppLocale.ru,
      paths: paths,
    );
    if (chosen.isEmpty || !mounted) return;
    setState(() {
      _error = null;
      _uploading = true;
      _saved = false;
    });
    try {
      final urls = await ref.read(uploadServiceProvider).uploadImages(chosen);
      if (mounted) setState(() => _v.imageUrls.addAll(urls));
    } catch (err) {
      if (handleAdminRightsLost(ref, err)) return;
      if (mounted) {
        setState(() => _error = _uploadError(err, 'Не удалось загрузить фото'));
      }
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  Future<void> _addVideos() async {
    if (_uploadingVideo) return;
    final List<String> paths;
    try {
      paths = await ref.read(adminVideoPickerProvider)();
    } catch (_) {
      return;
    }
    if (paths.isEmpty || !mounted) return;
    setState(() {
      _error = null;
      _uploadingVideo = true;
      _saved = false;
    });
    try {
      // One at a time, as on the web: each file is transcoded on the server.
      for (final path in paths) {
        final url = await ref.read(uploadServiceProvider).uploadVideo(path);
        if (!mounted) return;
        setState(() => _v.videoUrls.add(url));
      }
    } catch (err) {
      if (handleAdminRightsLost(ref, err)) return;
      if (mounted) {
        setState(
          () => _error = _uploadError(err, 'Не удалось загрузить видео'),
        );
      }
    } finally {
      if (mounted) setState(() => _uploadingVideo = false);
    }
  }

  Future<void> _pickColor(bool from) async {
    final current = from ? _v.colorFrom : _v.colorTo;
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => _ColorSheet(initial: current),
    );
    if (picked == null || !mounted) return;
    setState(() {
      if (from) {
        _v.colorFrom = picked;
      } else {
        _v.colorTo = picked;
      }
      _saved = false;
    });
  }

  Future<void> _submit(List<Category> categories) async {
    if (_submitting) return;
    FocusManager.instance.primaryFocus?.unfocus();
    if (_uploading || _uploadingVideo) {
      setState(
        () => _error = 'Дождитесь окончания загрузки файлов перед сохранением',
      );
      return;
    }
    _readControllers();
    final errors = validateAdminListing(_v);
    setState(() {
      _errors = errors;
      _error = errors.isEmpty ? null : 'Проверьте отмеченные поля';
      _saved = false;
    });
    if (!errors.isEmpty) return;

    setState(() => _submitting = true);
    final actions = ref.read(listingManagementActionsProvider);
    final payload = adminListingPayload(_v, existing: widget.existing);
    try {
      final listing = _editing
          ? await actions.saveListing(widget.existing!.id, payload)
          : await actions.createListing(payload);
      if (!mounted) return;
      final category = categories
          .where((c) => c.id == listing.categoryId)
          .firstOrNull;
      if (_editing) {
        setState(() => _saved = true);
        widget.onSaved?.call(listing, category);
      } else {
        widget.onCreated?.call(listing, category);
      }
    } catch (err) {
      if (handleAdminRightsLost(ref, err)) return;
      if (mounted) {
        setState(
          () => _error = err is ApiException && err.statusCode == 400
              ? (err.debugMessage == 'category not found'
                    ? 'Категория не найдена — обновите список'
                    : 'Сервер не принял данные: проверьте поля')
              : _uploadError(err, 'Не удалось сохранить услугу'),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final categoriesAsync = ref.watch(categoriesProvider);
    return categoriesAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => AdminErrorBody(
        error: e,
        onRetry: () => ref.invalidate(categoriesProvider),
      ),
      data: (categories) => _buildForm(context, categories),
    );
  }

  Widget _buildForm(BuildContext context, List<Category> categories) {
    final colors = context.mereytoiColors;
    final busy = _submitting || _uploading || _uploadingVideo;
    final categoryKnown = categories.any((c) => c.id == _v.categoryId);

    InputDecoration deco(String label, {String? error, String? hint}) =>
        InputDecoration(
          labelText: label,
          errorText: error,
          hintText: hint,
          errorMaxLines: 2,
        );

    const gap = SizedBox(height: AppSpacing.sm);

    return Stack(
      children: [
        ListView(
          key: const ValueKey('admin-listing-form'),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.lg,
            AppSpacing.lg,
            140,
          ),
          children: [
            TextField(
              key: const ValueKey('alf-name-ru'),
              controller: _nameRu,
              textCapitalization: TextCapitalization.sentences,
              decoration: deco('Название (рус) *', error: _errors.nameRu),
            ),
            gap,
            TextField(
              key: const ValueKey('alf-name-kz'),
              controller: _nameKz,
              textCapitalization: TextCapitalization.sentences,
              decoration: deco('Название (қаз) *', error: _errors.nameKz),
            ),
            gap,
            DropdownButtonFormField<int>(
              key: const ValueKey('alf-category'),
              initialValue: categoryKnown ? _v.categoryId : null,
              isExpanded: true,
              decoration: deco('Категория *', error: _errors.category),
              hint: const Text('Выберите категорию'),
              items: [
                for (final c in categories)
                  DropdownMenuItem(
                    value: c.id,
                    child: Text(c.nameRu, overflow: TextOverflow.ellipsis),
                  ),
              ],
              onChanged: busy
                  ? null
                  : (id) => setState(() {
                      _v.categoryId = id;
                      _saved = false;
                    }),
            ),
            gap,
            TextField(
              key: const ValueKey('alf-desc-ru'),
              controller: _descriptionRu,
              minLines: 3,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: deco('Описание (рус)'),
            ),
            gap,
            TextField(
              key: const ValueKey('alf-desc-kz'),
              controller: _descriptionKz,
              minLines: 3,
              maxLines: 8,
              textCapitalization: TextCapitalization.sentences,
              decoration: deco('Описание (қаз)'),
            ),
            gap,
            TextField(
              key: const ValueKey('alf-city'),
              controller: _city,
              textCapitalization: TextCapitalization.words,
              decoration: deco('Город'),
            ),
            gap,
            TextField(
              key: const ValueKey('alf-phone'),
              controller: _phone,
              keyboardType: TextInputType.phone,
              decoration: deco('Телефон', hint: '+7 700 000 00 00'),
            ),
            gap,
            TextField(
              key: const ValueKey('alf-price'),
              controller: _price,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: deco(
                'Цена, ₸ (0 — по запросу)',
                error: _errors.price,
              ),
            ),
            gap,
            TextField(
              key: const ValueKey('alf-rating'),
              controller: _rating,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              decoration: deco('Рейтинг (0–5)', error: _errors.rating),
            ),
            gap,
            TextField(
              key: const ValueKey('alf-min-guests'),
              controller: _minGuests,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: deco(
                'Мин. гостей (для ресторанов/локаций — цена за персону)',
                error: _errors.minGuests,
                hint: '0 — не применимо',
              ),
            ),
            gap,
            TextField(
              key: const ValueKey('alf-max-guests'),
              controller: _maxGuests,
              keyboardType: TextInputType.number,
              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
              decoration: deco(
                'Макс. гостей',
                error: _errors.maxGuests,
                hint: '0 — не применимо',
              ),
            ),
            gap,
            TextField(
              key: const ValueKey('alf-emoji'),
              controller: _emoji,
              decoration: deco(
                'Эмодзи-иконка (запасной вариант, если фото нет)',
                error: _errors.emoji,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            _Label('Градиент карточки (запасной вариант)'),
            const SizedBox(height: AppSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: _ColorButton(
                    key: const ValueKey('alf-color-from'),
                    label: 'Начало',
                    hex: _v.colorFrom,
                    error: _errors.colorFrom,
                    onTap: busy ? null : () => _pickColor(true),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: _ColorButton(
                    key: const ValueKey('alf-color-to'),
                    label: 'Конец',
                    hex: _v.colorTo,
                    error: _errors.colorTo,
                    onTap: busy ? null : () => _pickColor(false),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            _Label('Фото (одно или несколько — первое станет фоном карточки)'),
            const SizedBox(height: AppSpacing.xs),
            if (_v.imageUrls.isNotEmpty) ...[
              _PhotoGrid(
                urls: _v.imageUrls,
                onRemove: (url) => setState(() {
                  _v.imageUrls.remove(url);
                  _saved = false;
                }),
              ),
              const SizedBox(height: AppSpacing.xs),
            ],
            if (_uploading)
              const _UploadStatus('Загружаем фото…')
            else
              OutlinedButton.icon(
                key: const ValueKey('alf-add-photos'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _submitting ? null : _addPhotos,
                icon: const Icon(Icons.add_photo_alternate_outlined),
                label: const Text('Добавить фото'),
              ),
            const SizedBox(height: AppSpacing.lg),
            _Label(
              'Видео (одно или несколько — mp4, webm, mov, до 200MB каждое)',
            ),
            const SizedBox(height: AppSpacing.xs),
            for (final url in _v.videoUrls) ...[
              _VideoRow(
                url: url,
                onRemove: () => setState(() {
                  _v.videoUrls.remove(url);
                  _saved = false;
                }),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (_uploadingVideo)
              const _UploadStatus(
                'Загружаем видео… (может занять до пары минут на файл)',
              )
            else
              OutlinedButton.icon(
                key: const ValueKey('alf-add-videos'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: _submitting ? null : _addVideos,
                icon: const Icon(Icons.video_call_outlined),
                label: const Text('Добавить видео'),
              ),
            const SizedBox(height: AppSpacing.lg),
            _Label('Так будет выглядеть карточка'),
            const SizedBox(height: AppSpacing.xs),
            _CardPreview(values: _v, emoji: _emoji),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.md),
              Text(
                _error!,
                key: const ValueKey('alf-error'),
                style: TextStyle(color: colors.error, fontSize: 14),
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
              color: colors.surfaceElevated,
              border: Border(top: BorderSide(color: colors.divider)),
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
                child: Row(
                  children: [
                    if (widget.onCancel != null) ...[
                      Expanded(
                        flex: 2,
                        child: OutlinedButton(
                          key: const ValueKey('alf-cancel'),
                          style: OutlinedButton.styleFrom(
                            minimumSize: const Size.fromHeight(48),
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.sm,
                            ),
                          ),
                          onPressed: _submitting ? null : widget.onCancel,
                          // One line at any system text size: it shrinks
                          // rather than breaking «Отмена» in two.
                          child: const FittedBox(
                            fit: BoxFit.scaleDown,
                            child: Text('Отмена', maxLines: 1),
                          ),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                    ],
                    Expanded(
                      flex: 3,
                      child: ElevatedButton(
                        key: const ValueKey('alf-submit'),
                        style: ElevatedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.sm,
                          ),
                        ),
                        onPressed: busy ? null : () => _submit(categories),
                        child: FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text(
                            _submitting
                                ? 'Сохраняем…'
                                : _saved
                                ? 'Сохранено'
                                : _editing
                                ? 'Сохранить изменения'
                                : 'Создать услугу',
                            maxLines: 1,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: context.mereytoiColors.textSecondary,
      ),
    );
  }
}

class _UploadStatus extends StatelessWidget {
  const _UploadStatus(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 48),
      child: Row(
        children: [
          const SizedBox(
            width: 18,
            height: 18,
            child: CircularProgressIndicator(strokeWidth: 2.2),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyMedium),
          ),
        ],
      ),
    );
  }
}

Color? parseHexColor(String hex) {
  if (!RegExp(r'^#[0-9a-fA-F]{6}$').hasMatch(hex)) return null;
  return Color(int.parse('FF${hex.substring(1)}', radix: 16));
}

class _ColorButton extends StatelessWidget {
  const _ColorButton({
    super.key,
    required this.label,
    required this.hex,
    required this.onTap,
    this.error,
  });

  final String label;
  final String hex;
  final String? error;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    final swatch = parseHexColor(hex);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Material(
          color: colors.inputBackground,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppRadius.md),
            onTap: onTap,
            child: Container(
              constraints: const BoxConstraints(minHeight: 52),
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(
                  color: error != null ? colors.error : colors.border,
                ),
              ),
              child: Row(
                children: [
                  Container(
                    width: 28,
                    height: 28,
                    decoration: BoxDecoration(
                      color: swatch ?? Colors.transparent,
                      shape: BoxShape.circle,
                      border: Border.all(color: colors.border),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          label,
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        Text(
                          hex.isEmpty ? 'не задан' : hex,
                          style: Theme.of(context).textTheme.bodyMedium,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        if (error != null)
          Padding(
            padding: const EdgeInsets.only(top: 4, left: 4),
            child: Text(
              error!,
              style: TextStyle(color: colors.error, fontSize: 12),
            ),
          ),
      ],
    );
  }
}

/// The browser's colour input: a palette to tap, or any #RRGGBB typed in.
class _ColorSheet extends StatefulWidget {
  const _ColorSheet({required this.initial});

  final String initial;

  @override
  State<_ColorSheet> createState() => _ColorSheetState();
}

class _ColorSheetState extends State<_ColorSheet> {
  static const _palette = [
    '#3a1420',
    '#5c1a2e',
    '#7a1f3d',
    '#a8324a',
    '#d4566a',
    '#f2a0a8',
    '#2b1a10',
    '#5a3a1e',
    '#8a5a2b',
    '#b8863b',
    '#d4af6a',
    '#f3d9a4',
    '#0f2a24',
    '#1d4a3c',
    '#2f6d55',
    '#4f9a76',
    '#8cc7a1',
    '#d6efe0',
    '#0f1d33',
    '#1f3a5f',
    '#2f5b8f',
    '#4a83c0',
    '#8fb8e3',
    '#dceaf8',
    '#1a1424',
    '#3a2a55',
    '#5b4087',
    '#8466b8',
    '#b9a3dd',
    '#ece4f7',
    '#000000',
    '#2b2b2b',
    '#5a5a5a',
    '#8c8c8c',
    '#c8c8c8',
    '#ffffff',
  ];

  late final TextEditingController _hex;
  String? _error;

  @override
  void initState() {
    super.initState();
    _hex = TextEditingController(text: widget.initial);
  }

  @override
  void dispose() {
    _hex.dispose();
    super.dispose();
  }

  void _done() {
    var v = _hex.text.trim();
    if (!v.startsWith('#')) v = '#$v';
    if (parseHexColor(v) == null) {
      setState(() => _error = 'Цвет в формате #RRGGBB');
      return;
    }
    Navigator.of(context).pop(v.toLowerCase());
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    final current = parseHexColor(_hex.text.trim());
    return Padding(
      padding: EdgeInsets.only(
        left: AppSpacing.lg,
        right: AppSpacing.lg,
        top: AppSpacing.lg,
        bottom: MediaQuery.viewInsetsOf(context).bottom + AppSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Цвет', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.md),
            GridView.count(
              crossAxisCount: 6,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: AppSpacing.xs,
              crossAxisSpacing: AppSpacing.xs,
              children: [
                for (final hex in _palette)
                  Semantics(
                    button: true,
                    label: hex,
                    child: InkWell(
                      key: ValueKey('color-$hex'),
                      customBorder: const CircleBorder(),
                      onTap: () => setState(() {
                        _hex.text = hex;
                        _error = null;
                      }),
                      child: Container(
                        constraints: const BoxConstraints(
                          minWidth: 48,
                          minHeight: 48,
                        ),
                        decoration: BoxDecoration(
                          color: parseHexColor(hex),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: _hex.text.toLowerCase() == hex
                                ? colors.goldPrimary
                                : colors.border,
                            width: _hex.text.toLowerCase() == hex ? 3 : 1,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              children: [
                Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: current ?? Colors.transparent,
                    shape: BoxShape.circle,
                    border: Border.all(color: colors.border),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                Expanded(
                  child: TextField(
                    key: const ValueKey('color-hex'),
                    controller: _hex,
                    decoration: InputDecoration(
                      labelText: 'Свой цвет (#RRGGBB)',
                      errorText: _error,
                    ),
                    onChanged: (_) => setState(() => _error = null),
                    onSubmitted: (_) => _done(),
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton(
              key: const ValueKey('color-done'),
              style: ElevatedButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              onPressed: _done,
              child: const Text('Готово'),
            ),
          ],
        ),
      ),
    );
  }
}

class _PhotoGrid extends StatelessWidget {
  const _PhotoGrid({required this.urls, required this.onRemove});

  final List<String> urls;
  final ValueChanged<String> onRemove;

  @override
  Widget build(BuildContext context) {
    final colors = context.mereytoiColors;
    return GridView.count(
      crossAxisCount: 3,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      mainAxisSpacing: AppSpacing.xs,
      crossAxisSpacing: AppSpacing.xs,
      children: [
        for (var i = 0; i < urls.length; i++)
          Stack(
            key: ValueKey('alf-photo-$i'),
            fit: StackFit.expand,
            children: [
              NetworkImageBox(url: ApiConfig.mediaUrl(urls[i])),
              if (i == 0)
                Positioned(
                  left: 6,
                  bottom: 6,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: colors.goldPrimary,
                      borderRadius: BorderRadius.circular(AppRadius.chip),
                    ),
                    child: Text(
                      'Обложка',
                      style: TextStyle(
                        color: colors.onGold,
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              Positioned(
                right: 0,
                top: 0,
                child: IconButton(
                  key: ValueKey('alf-photo-remove-$i'),
                  tooltip: 'Удалить фото',
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black54,
                    foregroundColor: Colors.white,
                    minimumSize: const Size(40, 40),
                  ),
                  onPressed: () => onRemove(urls[i]),
                  icon: const Icon(Icons.close_rounded, size: 18),
                ),
              ),
            ],
          ),
      ],
    );
  }
}

class _VideoRow extends StatelessWidget {
  const _VideoRow({required this.url, required this.onRemove});

  final String url;
  final VoidCallback onRemove;

  @override
  Widget build(BuildContext context) {
    final poster = videoPosterPath(url);
    final full = ApiConfig.mediaUrl(url);
    void open() =>
        launchUrl(Uri.parse(full), mode: LaunchMode.externalApplication);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        VideoPreviewCard(
          videoUrl: full,
          posterUrl: poster == null ? null : ApiConfig.mediaUrl(poster),
          locale: AppLocale.ru,
          onOpen: open,
        ),
        Wrap(
          spacing: AppSpacing.xs,
          children: [
            TextButton(
              style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
              onPressed: open,
              child: const Text('Открыть видео'),
            ),
            TextButton(
              key: ValueKey('alf-video-remove-$url'),
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                foregroundColor: context.mereytoiColors.error,
              ),
              onPressed: onRemove,
              child: const Text('Удалить видео'),
            ),
          ],
        ),
      ],
    );
  }
}

/// ServiceForm's `.admin-preview`: the first photo as the background, or
/// the gradient with the emoji when there's no photo.
class _CardPreview extends StatelessWidget {
  const _CardPreview({required this.values, required this.emoji});

  final AdminListingValues values;
  final TextEditingController emoji;

  @override
  Widget build(BuildContext context) {
    final from = parseHexColor(values.colorFrom) ?? const Color(0xFF3A1420);
    final to = parseHexColor(values.colorTo) ?? const Color(0xFFD4AF6A);
    final hasImages = values.imageUrls.isNotEmpty;
    return ClipRRect(
      key: const ValueKey('alf-preview'),
      borderRadius: BorderRadius.circular(AppRadius.lg),
      child: SizedBox(
        height: 160,
        child: hasImages
            ? NetworkImageBox(
                url: ApiConfig.mediaUrl(values.imageUrls.first),
                borderRadius: 0,
              )
            : DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: const Alignment(-0.5, -1),
                    end: const Alignment(0.5, 1),
                    colors: [from, to],
                  ),
                ),
                child: Center(
                  child: ValueListenableBuilder(
                    valueListenable: emoji,
                    builder: (_, value, _) =>
                        Text(value.text, style: const TextStyle(fontSize: 56)),
                  ),
                ),
              ),
      ),
    );
  }
}
