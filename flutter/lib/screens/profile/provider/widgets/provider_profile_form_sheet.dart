import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../../core/config/api_config.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/error_messages.dart';
import '../../../../models/provider_profile.dart';
import '../../../../state/locale_provider.dart';
import '../../../../state/provider_provider.dart';
import '../../../../state/providers.dart';
import '../../../../widgets/admin/form_sheet_scaffold.dart';
import '../../../../widgets/network_image_box.dart';

/// "Стать услугодателем" (existing == null) / "Профиль услугодателя"
/// (edit) — Этап 11 brief section 4: deliberately compact, same field set
/// as the web form (imя/название, город, краткое описание, телефон,
/// WhatsApp, Telegram) plus, since Этап 11F, an avatar picker.
Future<void> openProviderProfileFormSheet(
  BuildContext context, {
  ProviderProfile? existing,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => ProviderProfileFormSheet(existing: existing),
  );
}

class ProviderProfileFormSheet extends ConsumerStatefulWidget {
  const ProviderProfileFormSheet({super.key, this.existing});

  final ProviderProfile? existing;

  @override
  ConsumerState<ProviderProfileFormSheet> createState() =>
      _ProviderProfileFormSheetState();
}

class _ProviderProfileFormSheetState
    extends ConsumerState<ProviderProfileFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _displayName;
  late final TextEditingController _city;
  late final TextEditingController _description;
  late final TextEditingController _phone;
  late final TextEditingController _whatsapp;
  late final TextEditingController _telegram;
  late String _avatarUrl;
  bool _avatarUploading = false;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _displayName = TextEditingController(text: e?.displayName ?? '');
    _city = TextEditingController(text: e?.city ?? '');
    _description = TextEditingController(text: e?.description ?? '');
    _phone = TextEditingController(text: e?.phone ?? '');
    _whatsapp = TextEditingController(text: e?.whatsapp ?? '');
    _telegram = TextEditingController(text: e?.telegram ?? '');
    _avatarUrl = e?.avatarUrl ?? '';
  }

  Future<void> _pickAvatar() async {
    final XFile? picked;
    try {
      picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 85,
      );
    } catch (err) {
      // A denied/unavailable picker (permissions, no gallery app, etc.)
      // surfaces here rather than crashing the sheet — the rest of the
      // form the user already filled in stays exactly as it was.
      if (mounted) {
        setState(
          () => _error = apiErrorMessage(ref.read(localeProvider), err),
        );
      }
      return;
    }
    if (picked == null) return; // user cancelled the picker

    setState(() {
      _avatarUploading = true;
      _error = null;
    });
    try {
      final urls = await ref
          .read(uploadServiceProvider)
          .uploadImages([picked.path]);
      if (mounted && urls.isNotEmpty) {
        setState(() => _avatarUrl = urls.first);
      }
    } catch (err) {
      if (mounted) {
        setState(() => _error = apiErrorMessage(ref.read(localeProvider), err));
      }
    } finally {
      if (mounted) setState(() => _avatarUploading = false);
    }
  }

  @override
  void dispose() {
    _displayName.dispose();
    _city.dispose();
    _description.dispose();
    _phone.dispose();
    _whatsapp.dispose();
    _telegram.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    if (_avatarUploading) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final actions = ref.read(providerActionsProvider);
      if (widget.existing == null) {
        await actions.become(
          displayName: _displayName.text.trim(),
          city: _city.text.trim(),
          description: _description.text.trim(),
          phone: _phone.text.trim(),
          whatsapp: _whatsapp.text.trim(),
          telegram: _telegram.text.trim(),
          avatarUrl: _avatarUrl,
        );
      } else {
        await actions.updateProfile(
          displayName: _displayName.text.trim(),
          city: _city.text.trim(),
          description: _description.text.trim(),
          phone: _phone.text.trim(),
          whatsapp: _whatsapp.text.trim(),
          telegram: _telegram.text.trim(),
          avatarUrl: _avatarUrl,
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
              ru: 'Профиль услугодателя',
              kz: 'Қызмет көрсетуші профилі',
              en: 'Provider profile',
            )
          : t(
              locale,
              ru: 'Стать услугодателем',
              kz: 'Қызмет көрсетуші болу',
              en: 'Become a provider',
            ),
      formKey: _formKey,
      onSave: _save,
      saving: _saving,
      error: _error,
      saveLabel: t(locale, ru: 'Сохранить', kz: 'Сақтау', en: 'Save'),
      children: [
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  ClipOval(
                    child: SizedBox(
                      width: 84,
                      height: 84,
                      child: _avatarUrl.isEmpty
                          ? const _AvatarPlaceholder()
                          : NetworkImageBox(
                              url: ApiConfig.mediaUrl(_avatarUrl),
                              borderRadius: 0,
                            ),
                    ),
                  ),
                  if (_avatarUploading)
                    const SizedBox(
                      width: 84,
                      height: 84,
                      child: CircularProgressIndicator(strokeWidth: 2.4),
                    ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TextButton(
                    onPressed: _avatarUploading ? null : _pickAvatar,
                    child: Text(
                      _avatarUrl.isEmpty
                          ? t(
                              locale,
                              ru: 'Добавить фото',
                              kz: 'Фото қосу',
                              en: 'Add photo',
                            )
                          : t(
                              locale,
                              ru: 'Изменить фото',
                              kz: 'Фотоны өзгерту',
                              en: 'Change photo',
                            ),
                    ),
                  ),
                  if (_avatarUrl.isNotEmpty && !_avatarUploading)
                    TextButton(
                      onPressed: () => setState(() => _avatarUrl = ''),
                      child: Text(
                        t(locale, ru: 'Удалить', kz: 'Жою', en: 'Remove'),
                        style: TextStyle(color: context.mereytoiColors.error),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: _displayName,
          decoration: InputDecoration(
            labelText: t(
              locale,
              ru: 'Имя / название',
              kz: 'Аты / атауы',
              en: 'Name / business name',
            ),
          ),
          validator: (v) => (v == null || v.trim().isEmpty)
              ? t(
                  locale,
                  ru: 'Введите имя или название',
                  kz: 'Атыңызды енгізіңіз',
                  en: 'Enter a name',
                )
              : null,
        ),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: _city,
          decoration: InputDecoration(
            labelText: t(locale, ru: 'Город', kz: 'Қала', en: 'City'),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: _description,
          maxLines: 3,
          decoration: InputDecoration(
            labelText: t(
              locale,
              ru: 'Краткое описание (необязательно)',
              kz: 'Қысқаша сипаттама (міндетті емес)',
              en: 'Short description (optional)',
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        TextFormField(
          controller: _phone,
          keyboardType: TextInputType.phone,
          decoration: InputDecoration(
            labelText: t(locale, ru: 'Телефон', kz: 'Телефон', en: 'Phone'),
            hintText: '+7 700 000 00 00',
          ),
        ),
        const SizedBox(height: AppSpacing.sm),
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: _whatsapp,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(
                  labelText: 'WhatsApp',
                  hintText: '+7 700 000 00 00',
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: TextFormField(
                controller: _telegram,
                decoration: const InputDecoration(
                  labelText: 'Telegram',
                  hintText: '@username',
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _AvatarPlaceholder extends StatelessWidget {
  const _AvatarPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Container(
      color: context.mereytoiColors.surfaceSoft,
      child: Icon(
        Icons.person_outline,
        color: context.mereytoiColors.textSecondary,
        size: 36,
      ),
    );
  }
}
