import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/error_messages.dart';
import '../../../../models/listing_hall.dart';
import '../../../../state/listing_management_actions.dart';
import '../../../../state/locale_provider.dart';
import '../../../../widgets/admin/form_sheet_scaffold.dart';

/// Opens the add/edit-hall sheet — `existing == null` creates, otherwise
/// edits in place. Returns once saved (or dismissed); the caller doesn't
/// need the result — `ListingManagementActions` already invalidated
/// `listingHallsProvider` on success, so the halls tab (and the public
/// `RestaurantDetailScreen`, once reopened) just rebuild with fresh data.
Future<void> openHallFormSheet(
  BuildContext context, {
  required int listingId,
  ListingHall? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => HallFormSheet(listingId: listingId, existing: existing),
  );
}

class HallFormSheet extends ConsumerStatefulWidget {
  const HallFormSheet({super.key, required this.listingId, this.existing});

  final int listingId;
  final ListingHall? existing;

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

  Future<void> _save() async {
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
          isActive: _isActive,
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
                controller: _capacity,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: t(locale, ru: 'Вместимость', kz: 'Сыйымдылық'),
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: TextFormField(
                controller: _price,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  labelText: t(
                    locale,
                    ru: 'Цена (0 = как у ресторана)',
                    kz: 'Баға (0 = мейрамхана бағасы)',
                  ),
                ),
              ),
            ),
          ],
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
