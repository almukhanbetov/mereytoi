import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/error_messages.dart';
import '../../../../core/utils/format.dart';
import '../../../../models/listing_hall.dart';
import '../../../../models/listing_menu.dart';
import '../../../../state/listing_management_actions.dart';
import '../../../../state/locale_provider.dart';
import '../../../../widgets/admin/form_sheet_scaffold.dart';

Future<void> openMenuFormSheet(
  BuildContext context, {
  required int listingId,
  required List<ListingHall> halls,
  ListingMenu? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) =>
        MenuFormSheet(listingId: listingId, halls: halls, existing: existing),
  );
}

class MenuFormSheet extends ConsumerStatefulWidget {
  const MenuFormSheet({
    super.key,
    required this.listingId,
    required this.halls,
    this.existing,
  });

  final int listingId;
  final List<ListingHall> halls;
  final ListingMenu? existing;

  @override
  ConsumerState<MenuFormSheet> createState() => _MenuFormSheetState();
}

class _MenuFormSheetState extends ConsumerState<MenuFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameRu;
  late final TextEditingController _nameKz;
  late final TextEditingController _descriptionRu;
  late final TextEditingController _descriptionKz;
  late final TextEditingController _pricePerGuest;
  late final TextEditingController _minGuests;
  late final TextEditingController _maxGuests;
  int? _hallId;
  DateTime? _validFrom;
  DateTime? _validUntil;
  late bool _isActive;
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
    _pricePerGuest = TextEditingController(
      text: e != null ? '${e.pricePerGuest}' : '',
    );
    _minGuests = TextEditingController(text: e?.minGuests?.toString() ?? '');
    _maxGuests = TextEditingController(text: e?.maxGuests?.toString() ?? '');
    _hallId = e?.hallId;
    _validFrom = e?.validFrom;
    _validUntil = e?.validUntil;
    _isActive = e?.isActive ?? true;
  }

  @override
  void dispose() {
    _nameRu.dispose();
    _nameKz.dispose();
    _descriptionRu.dispose();
    _descriptionKz.dispose();
    _pricePerGuest.dispose();
    _minGuests.dispose();
    _maxGuests.dispose();
    super.dispose();
  }

  Future<void> _pickDate({required bool isFrom}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: (isFrom ? _validFrom : _validUntil) ?? now,
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (picked == null) return;
    setState(() {
      if (isFrom) {
        _validFrom = picked;
      } else {
        _validUntil = picked;
      }
    });
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final actions = ref.read(listingManagementActionsProvider);
      final minGuests = int.tryParse(_minGuests.text.trim());
      final maxGuests = int.tryParse(_maxGuests.text.trim());
      if (widget.existing == null) {
        await actions.createMenu(
          widget.listingId,
          hallId: _hallId,
          nameRu: _nameRu.text.trim(),
          nameKz: _nameKz.text.trim(),
          descriptionRu: _descriptionRu.text.trim(),
          descriptionKz: _descriptionKz.text.trim(),
          pricePerGuest: int.tryParse(_pricePerGuest.text.trim()) ?? 0,
          minGuests: minGuests,
          maxGuests: maxGuests,
          isActive: _isActive,
          validFrom: _validFrom,
          validUntil: _validUntil,
        );
      } else {
        await actions.updateMenu(
          widget.listingId,
          widget.existing!.id,
          hallId: _hallId,
          nameRu: _nameRu.text.trim(),
          nameKz: _nameKz.text.trim(),
          descriptionRu: _descriptionRu.text.trim(),
          descriptionKz: _descriptionKz.text.trim(),
          pricePerGuest: int.tryParse(_pricePerGuest.text.trim()) ?? 0,
          minGuests: minGuests,
          maxGuests: maxGuests,
          isActive: _isActive,
          sortOrder: widget.existing!.sortOrder,
          validFrom: _validFrom,
          validUntil: _validUntil,
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
          ? t(locale, ru: 'Редактировать меню', kz: 'Мәзірді өңдеу')
          : t(locale, ru: 'Добавить меню', kz: 'Мәзір қосу'),
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
          maxLines: 2,
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
          maxLines: 2,
          decoration: InputDecoration(
            labelText: t(
              locale,
              ru: 'Описание KZ (необязательно)',
              kz: 'Сипаттама KZ (міндетті емес)',
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<int?>(
          initialValue: _hallId,
          decoration: InputDecoration(
            labelText: t(
              locale,
              ru: 'Зал (необязательно)',
              kz: 'Зал (міндетті емес)',
            ),
          ),
          items: [
            DropdownMenuItem<int?>(
              value: null,
              child: Text(t(locale, ru: 'Любой зал', kz: 'Кез келген зал')),
            ),
            for (final hall in widget.halls)
              DropdownMenuItem<int?>(
                value: hall.id,
                child: Text(hall.name(locale), overflow: TextOverflow.ellipsis),
              ),
          ],
          onChanged: (v) => setState(() => _hallId = v),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: _pricePerGuest,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: t(
              locale,
              ru: 'Цена за гостя (₸)',
              kz: 'Қонақ басына баға (₸)',
            ),
          ),
          validator: (v) => (v == null || v.trim().isEmpty)
              ? t(locale, ru: 'Введите цену', kz: 'Бағаны енгізіңіз')
              : null,
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
                  labelText: t(locale, ru: 'Макс. гостей', kz: 'Макс. қонақ'),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: OutlinedButton(
                onPressed: () => _pickDate(isFrom: true),
                child: Text(
                  _validFrom != null
                      ? formatMenuDate(_validFrom!)
                      : t(locale, ru: 'Действует с', kz: 'Бастап'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: OutlinedButton(
                onPressed: () => _pickDate(isFrom: false),
                child: Text(
                  _validUntil != null
                      ? formatMenuDate(_validUntil!)
                      : t(locale, ru: 'Действует до', kz: 'Дейін'),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xs),
        SwitchListTile.adaptive(
          contentPadding: EdgeInsets.zero,
          title: Text(t(locale, ru: 'Активно', kz: 'Белсенді')),
          value: _isActive,
          onChanged: (v) => setState(() => _isActive = v),
        ),
      ],
    );
  }
}
