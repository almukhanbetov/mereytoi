import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/error_messages.dart';
import '../../../../models/listing_menu_item.dart';
import '../../../../state/listing_management_actions.dart';
import '../../../../state/locale_provider.dart';
import '../../../../widgets/admin/form_sheet_scaffold.dart';

/// `listingMenuItemInput` on the backend has no `is_active` field either —
/// see `section_form_sheet.dart`'s own doc comment on the same constraint.
Future<void> openItemFormSheet(
  BuildContext context, {
  required int listingId,
  required int menuId,
  required int sectionId,
  ListingMenuItem? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ItemFormSheet(
      listingId: listingId,
      menuId: menuId,
      sectionId: sectionId,
      existing: existing,
    ),
  );
}

class ItemFormSheet extends ConsumerStatefulWidget {
  const ItemFormSheet({
    super.key,
    required this.listingId,
    required this.menuId,
    required this.sectionId,
    this.existing,
  });

  final int listingId;
  final int menuId;
  final int sectionId;
  final ListingMenuItem? existing;

  @override
  ConsumerState<ItemFormSheet> createState() => _ItemFormSheetState();
}

class _ItemFormSheetState extends ConsumerState<ItemFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameRu;
  late final TextEditingController _nameKz;
  late final TextEditingController _descriptionRu;
  late final TextEditingController _descriptionKz;
  late final TextEditingController _quantityText;
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
    _quantityText = TextEditingController(text: e?.quantityText ?? '');
  }

  @override
  void dispose() {
    _nameRu.dispose();
    _nameKz.dispose();
    _descriptionRu.dispose();
    _descriptionKz.dispose();
    _quantityText.dispose();
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
        await actions.createItem(
          widget.listingId,
          widget.menuId,
          widget.sectionId,
          nameRu: _nameRu.text.trim(),
          nameKz: _nameKz.text.trim(),
          descriptionRu: _descriptionRu.text.trim(),
          descriptionKz: _descriptionKz.text.trim(),
          quantityText: _quantityText.text.trim(),
        );
      } else {
        await actions.updateItem(
          widget.listingId,
          widget.menuId,
          widget.sectionId,
          widget.existing!.id,
          nameRu: _nameRu.text.trim(),
          nameKz: _nameKz.text.trim(),
          descriptionRu: _descriptionRu.text.trim(),
          descriptionKz: _descriptionKz.text.trim(),
          quantityText: _quantityText.text.trim(),
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
          ? t(locale, ru: 'Редактировать позицию', kz: 'Позицияны өңдеу')
          : t(locale, ru: 'Добавить позицию', kz: 'Позиция қосу'),
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
        TextFormField(
          controller: _quantityText,
          decoration: InputDecoration(
            labelText: t(
              locale,
              ru: 'Объём/порция (например «250 г»)',
              kz: 'Мөлшер (мысалы «250 г»)',
            ),
          ),
        ),
      ],
    );
  }
}
