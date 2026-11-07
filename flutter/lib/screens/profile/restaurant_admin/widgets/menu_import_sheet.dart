import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/error_messages.dart';
import '../../../../domain/restaurant/menu_text_import.dart';
import '../../../../state/listing_management_actions.dart';
import '../../../../state/locale_provider.dart';
import '../../../../widgets/admin/form_sheet_scaffold.dart';

Future<void> openMenuImportSheet(
  BuildContext context, {
  required int listingId,
  required int menuId,
  required int existingSectionCount,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => MenuImportSheet(
      listingId: listingId,
      menuId: menuId,
      existingSectionCount: existingSectionCount,
    ),
  );
}

/// Text → preview → an explicit confirm: nothing is written before it.
class MenuImportSheet extends ConsumerStatefulWidget {
  const MenuImportSheet({
    super.key,
    required this.listingId,
    required this.menuId,
    required this.existingSectionCount,
  });

  final int listingId;
  final int menuId;
  final int existingSectionCount;

  @override
  ConsumerState<MenuImportSheet> createState() => _MenuImportSheetState();
}

class _MenuImportSheetState extends ConsumerState<MenuImportSheet> {
  final _formKey = GlobalKey<FormState>();
  final _text = TextEditingController();
  List<MenuTextSection>? _preview;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _onPrimary() async {
    final preview = _preview;
    if (preview == null) {
      if (!_formKey.currentState!.validate()) return;
      setState(() {
        _preview = parseMenuText(_text.text);
        _error = null;
      });
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(listingManagementActionsProvider)
          .importMenuSections(
            widget.listingId,
            widget.menuId,
            preview,
            existingSectionCount: widget.existingSectionCount,
          );
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
    final textTheme = Theme.of(context).textTheme;
    final preview = _preview;
    final items = preview?.fold<int>(0, (n, s) => n + s.items.length) ?? 0;
    return FormSheetScaffold(
      title: t(
        locale,
        ru: 'Меню из текста',
        kz: 'Мәтіннен мәзір',
        en: 'Menu from text',
      ),
      formKey: _formKey,
      onSave: _onPrimary,
      saving: _saving,
      error: _error,
      saveLabel: preview == null
          ? t(
              locale,
              ru: 'Показать результат',
              kz: 'Нәтижені көрсету',
              en: 'Preview',
            )
          : t(
              locale,
              ru: 'Добавить в меню',
              kz: 'Мәзірге қосу',
              en: 'Add to the menu',
            ),
      children: [
        if (preview == null) ...[
          Text(
            t(
              locale,
              ru: 'Строка без «-» — новый раздел, строки с «-» — его позиции. После « — » можно указать порцию.',
              kz: '«-» белгісіз жол — жаңа бөлім, «-» белгісі барлары — оның позициялары. « — » кейін порцияны көрсетуге болады.',
              en: 'A line without «-» starts a section, lines with «-» are its items. A portion can follow « — ».',
            ),
            style: textTheme.bodySmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          TextFormField(
            key: const ValueKey('menu-import-text'),
            controller: _text,
            minLines: 6,
            maxLines: 12,
            decoration: const InputDecoration(
              hintText:
                  'Салаты\n- Цезарь — 250 г\n- Оливье\nГорячее\n- Бешбармак',
              alignLabelWithHint: true,
            ),
            validator: (v) => parseMenuText(v ?? '').isEmpty
                ? t(
                    locale,
                    ru: 'Введите текст меню',
                    kz: 'Мәзір мәтінін енгізіңіз',
                    en: 'Enter the menu text',
                  )
                : null,
          ),
        ] else ...[
          Text(
            t(
              locale,
              ru: 'Будет добавлено разделов: ${preview.length}, позиций: $items',
              kz: 'Қосылатын бөлімдер: ${preview.length}, позициялар: $items',
              en: 'To add: ${preview.length} sections, $items items',
            ),
            key: const ValueKey('menu-import-summary'),
            style: textTheme.titleSmall,
          ),
          const SizedBox(height: AppSpacing.sm),
          for (final section in preview) ...[
            Text(section.title, style: textTheme.titleSmall),
            for (final item in section.items)
              Padding(
                padding: const EdgeInsets.only(left: AppSpacing.sm, top: 2),
                child: Text(
                  item.quantityText.isEmpty
                      ? item.name
                      : '${item.name} · ${item.quantityText}',
                  style: textTheme.bodySmall,
                ),
              ),
            const SizedBox(height: AppSpacing.xs),
          ],
          TextButton(
            key: const ValueKey('menu-import-back'),
            style: TextButton.styleFrom(minimumSize: const Size(48, 48)),
            onPressed: _saving ? null : () => setState(() => _preview = null),
            child: Text(
              t(
                locale,
                ru: 'Изменить текст',
                kz: 'Мәтінді өзгерту',
                en: 'Edit the text',
              ),
            ),
          ),
        ],
      ],
    );
  }
}
