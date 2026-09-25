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
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ExtraFormSheet(
      listingId: listingId,
      menuId: menuId,
      existing: existing,
    ),
  );
}

class ExtraFormSheet extends ConsumerStatefulWidget {
  const ExtraFormSheet({
    super.key,
    required this.listingId,
    required this.menuId,
    this.existing,
  });

  final int listingId;
  final int menuId;
  final ListingMenuExtra? existing;

  @override
  ConsumerState<ExtraFormSheet> createState() => _ExtraFormSheetState();
}

class _ExtraFormSheetState extends ConsumerState<ExtraFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleRu;
  late final TextEditingController _titleKz;
  late final TextEditingController _price;
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
    _type = e?.type ?? _typePresets.first.$1;
    _unit = e?.unit ?? '';
  }

  @override
  void dispose() {
    _titleRu.dispose();
    _titleKz.dispose();
    _price.dispose();
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
          initialValue: _type,
          decoration: InputDecoration(
            labelText: t(locale, ru: 'Тип', kz: 'Түрі'),
          ),
          items: [
            for (final preset in _typePresets)
              DropdownMenuItem(value: preset.$1, child: Text(preset.$2)),
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
          initialValue: _unit,
          decoration: InputDecoration(
            labelText: t(locale, ru: 'Как считается', kz: 'Қалай есептеледі'),
          ),
          items: [
            for (final option in _unitOptions)
              DropdownMenuItem(value: option.$1, child: Text(option.$2)),
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
      ],
    );
  }
}
