import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/error_messages.dart';
import '../../../../models/listing_menu_section.dart';
import '../../../../state/listing_management_actions.dart';
import '../../../../state/locale_provider.dart';
import '../../../../widgets/admin/form_sheet_scaffold.dart';

/// `listingMenuSectionInput` on the backend only has title_ru/title_kz/
/// sort_order — no description, no is_active (verified directly against
/// `backend/internal/handlers/listing_menu_handler.go` and
/// `models/listing_menu.go`'s own `ListingMenuSection` struct before
/// writing this — neither field exists to invent here).
Future<void> openSectionFormSheet(
  BuildContext context, {
  required int listingId,
  required int menuId,
  ListingMenuSection? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => SectionFormSheet(
      listingId: listingId,
      menuId: menuId,
      existing: existing,
    ),
  );
}

class SectionFormSheet extends ConsumerStatefulWidget {
  const SectionFormSheet({
    super.key,
    required this.listingId,
    required this.menuId,
    this.existing,
  });

  final int listingId;
  final int menuId;
  final ListingMenuSection? existing;

  @override
  ConsumerState<SectionFormSheet> createState() => _SectionFormSheetState();
}

class _SectionFormSheetState extends ConsumerState<SectionFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _titleRu;
  late final TextEditingController _titleKz;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _titleRu = TextEditingController(text: widget.existing?.titleRu ?? '');
    _titleKz = TextEditingController(text: widget.existing?.titleKz ?? '');
  }

  @override
  void dispose() {
    _titleRu.dispose();
    _titleKz.dispose();
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
        await actions.createSection(
          widget.listingId,
          widget.menuId,
          titleRu: _titleRu.text.trim(),
          titleKz: _titleKz.text.trim(),
        );
      } else {
        await actions.updateSection(
          widget.listingId,
          widget.menuId,
          widget.existing!.id,
          titleRu: _titleRu.text.trim(),
          titleKz: _titleKz.text.trim(),
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
          ? t(locale, ru: 'Редактировать раздел', kz: 'Бөлімді өңдеу')
          : t(locale, ru: 'Добавить раздел', kz: 'Бөлім қосу'),
      formKey: _formKey,
      onSave: _save,
      saving: _saving,
      error: _error,
      saveLabel: t(locale, ru: 'Сохранить', kz: 'Сақтау'),
      children: [
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
      ],
    );
  }
}
