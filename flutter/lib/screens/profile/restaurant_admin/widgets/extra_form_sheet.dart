import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/error_messages.dart';
import '../../../../models/listing_menu_extra.dart';
import '../../../../state/listing_management_actions.dart';
import '../../../../state/locale_provider.dart';
import '../../../../widgets/admin/form_sheet_scaffold.dart';

/// Same preset lists `RestaurantMenuExtras.jsx` (web admin) already uses —
/// `type` stays a free-form string on the backend (no enum), these are
/// just suggestions; `unit` is the one the public calculator actually
/// special-cases ('percent'/'per_guest'; 'per_item' and '' both resolve to
/// a flat amount there).
const _typePresets = [
  ('kids_table', 'Детский стол'),
  ('artists_table', 'Стол артистов'),
  ('service_fee', 'Сервисный сбор'),
  ('rental', 'Аренда'),
  ('corkage', 'Пробковый сбор'),
  ('decor', 'Декор'),
  ('other', 'Другое условие'),
];

const _unitOptions = [
  ('', 'Фиксированная сумма'),
  ('per_guest', 'На каждого гостя'),
  ('per_item', 'За единицу'),
  ('percent', 'Процент от суммы заказа'),
];

Future<void> openExtraFormSheet(
  BuildContext context, {
  required int listingId,
  required int menuId,
  ListingMenuExtra? existing,
  int nextSortOrder = 0,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ExtraFormSheet(
      listingId: listingId,
      menuId: menuId,
      existing: existing,
      nextSortOrder: nextSortOrder,
    ),
  );
}

class ExtraFormSheet extends ConsumerStatefulWidget {
  const ExtraFormSheet({
    super.key,
    required this.listingId,
    required this.menuId,
    this.existing,
    this.nextSortOrder = 0,
  });

  final int listingId;
  final int menuId;
  final ListingMenuExtra? existing;

  /// Where a new option goes: the end of the list.
  final int nextSortOrder;

  @override
  ConsumerState<ExtraFormSheet> createState() => _ExtraFormSheetState();
}

class _ExtraFormSheetState extends ConsumerState<ExtraFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleRu;
  late final TextEditingController _titleKz;
  late final TextEditingController _price;
  late final TextEditingController _descriptionRu;
  late final TextEditingController _descriptionKz;
  late String _type;
  late String _unit;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _titleRu = TextEditingController(text: e?.titleRu ?? '');
    _titleKz = TextEditingController(text: e?.titleKz ?? '');
    _price = TextEditingController(text: e != null ? '${e.price}' : '');
    _descriptionRu = TextEditingController(text: e?.descriptionRu ?? '');
    _descriptionKz = TextEditingController(text: e?.descriptionKz ?? '');
    _type = e?.type ?? _typePresets.first.$1;
    _unit = e?.unit ?? '';
  }

  @override
  void dispose() {
    _titleRu.dispose();
    _titleKz.dispose();
    _price.dispose();
    _descriptionRu.dispose();
    _descriptionKz.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final actions = ref.read(listingManagementActionsProvider);
      if (widget.existing == null) {
        await actions.createExtra(
          widget.listingId,
          widget.menuId,
          type: _type,
          titleRu: _titleRu.text.trim(),
          titleKz: _titleKz.text.trim(),
          price: int.tryParse(_price.text.trim()) ?? 0,
          unit: _unit,
          descriptionRu: _descriptionRu.text.trim(),
          descriptionKz: _descriptionKz.text.trim(),
          sortOrder: widget.nextSortOrder,
        );
      } else {
        await actions.updateExtra(
          widget.listingId,
          widget.menuId,
          widget.existing!.id,
          type: _type,
          titleRu: _titleRu.text.trim(),
          titleKz: _titleKz.text.trim(),
          price: int.tryParse(_price.text.trim()) ?? 0,
          unit: _unit,
          descriptionRu: _descriptionRu.text.trim(),
          descriptionKz: _descriptionKz.text.trim(),
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
    final isPercent = _unit == 'percent';
    return FormSheetScaffold(
      title: isEdit
          ? t(locale, ru: 'Редактировать опцию', kz: 'Опцияны өңдеу')
          : t(locale, ru: 'Добавить опцию', kz: 'Опция қосу'),
      formKey: _formKey,
      onSave: _save,
      saving: _saving,
      error: _error,
      saveLabel: t(locale, ru: 'Сохранить', kz: 'Сақтау'),
      children: [
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _type,
          decoration: InputDecoration(
            labelText: t(locale, ru: 'Тип', kz: 'Түрі'),
          ),
          items: [
            for (final preset in _typePresets)
              DropdownMenuItem(
                value: preset.$1,
                child: Text(preset.$2, overflow: TextOverflow.ellipsis),
              ),
            // A value set elsewhere that isn't a preset stays selectable.
            if (!_typePresets.any((p) => p.$1 == _type))
              DropdownMenuItem(value: _type, child: Text(_type)),
          ],
          onChanged: (v) => setState(() => _type = v ?? _type),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: _titleRu,
          decoration: InputDecoration(
            labelText: t(locale, ru: 'Название (RU)', kz: 'Атауы (RU)'),
          ),
          validator: (v) => (v == null || v.trim().isEmpty)
              ? t(locale, ru: 'Введите название', kz: 'Атауын енгізіңіз')
              : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: _titleKz,
          decoration: InputDecoration(
            labelText: t(locale, ru: 'Название (KZ)', kz: 'Атауы (KZ)'),
          ),
          validator: (v) => (v == null || v.trim().isEmpty)
              ? t(locale, ru: 'Введите название', kz: 'Атауын енгізіңіз')
              : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        DropdownButtonFormField<String>(
          isExpanded: true,
          initialValue: _unit,
          decoration: InputDecoration(
            labelText: t(locale, ru: 'Как считается', kz: 'Қалай есептеледі'),
          ),
          items: [
            for (final option in _unitOptions)
              DropdownMenuItem(
                value: option.$1,
                child: Text(option.$2, overflow: TextOverflow.ellipsis),
              ),
            if (!_unitOptions.any((o) => o.$1 == _unit))
              DropdownMenuItem(value: _unit, child: Text(_unit)),
          ],
          onChanged: (v) => setState(() => _unit = v ?? _unit),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: _price,
          keyboardType: TextInputType.number,
          decoration: InputDecoration(
            labelText: isPercent
                ? t(locale, ru: 'Процент, %', kz: 'Пайыз, %')
                : t(locale, ru: 'Сумма, ₸', kz: 'Сома, ₸'),
          ),
          validator: (v) => (v == null || v.trim().isEmpty)
              ? t(locale, ru: 'Введите значение', kz: 'Мәнін енгізіңіз')
              : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          key: const ValueKey('extra-description-ru'),
          controller: _descriptionRu,
          maxLines: 2,
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
          key: const ValueKey('extra-description-kz'),
          controller: _descriptionKz,
          maxLines: 2,
          decoration: InputDecoration(
            labelText: t(
              locale,
              ru: 'Описание KZ (необязательно)',
              kz: 'Сипаттама KZ (міндетті емес)',
              en: 'Description KZ (optional)',
            ),
          ),
        ),
      ],
    );
  }
}
