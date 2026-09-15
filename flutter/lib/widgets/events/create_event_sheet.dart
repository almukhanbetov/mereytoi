import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../domain/event/event_status.dart';
import '../../screens/events/event_workspace_screen.dart';
import '../../state/event_actions.dart';
import '../../state/locale_provider.dart';

/// Pushes the create-event bottom sheet, and — on a successful create —
/// replaces it with `EventWorkspaceScreen` for the new event (brief
/// section 6: "После создания открыть Event Workspace").
Future<void> openCreateEventSheet(BuildContext context) async {
  final createdId = await showModalBottomSheet<int>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const CreateEventSheet(),
  );
  if (createdId != null && context.mounted) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => EventWorkspaceScreen(eventId: createdId),
      ),
    );
  }
}

/// `eventInput` on the backend (event_handler.go) — the only required
/// field is `title`; everything else here is genuinely optional, matching
/// that contract exactly (no invented required field).
class CreateEventSheet extends ConsumerStatefulWidget {
  const CreateEventSheet({super.key});

  @override
  ConsumerState<CreateEventSheet> createState() => _CreateEventSheetState();
}

class _CreateEventSheetState extends ConsumerState<CreateEventSheet> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _cityController = TextEditingController();
  final _guestsController = TextEditingController();
  final _budgetController = TextEditingController();
  final _commentController = TextEditingController();

  String _type = eventTypeWedding;
  DateTime? _eventDate;
  bool _submitting = false;
  String? _error;

  static const _types = [
    eventTypeWedding,
    eventTypeToi,
    eventTypeAnniversary,
    eventTypeCorporate,
    eventTypeOther,
  ];

  @override
  void dispose() {
    _titleController.dispose();
    _cityController.dispose();
    _guestsController.dispose();
    _budgetController.dispose();
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: _eventDate ?? now.add(const Duration(days: 30)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365 * 3)),
    );
    if (picked != null) setState(() => _eventDate = picked);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final event = await ref
          .read(eventActionsProvider)
          .createEvent(
            title: _titleController.text.trim(),
            type: _type,
            eventDate: _eventDate,
            city: _cityController.text.trim(),
            guests: int.tryParse(_guestsController.text.trim()) ?? 0,
            budgetTotal: int.tryParse(_budgetController.text.trim()) ?? 0,
            comment: _commentController.text.trim(),
          );
      if (mounted) Navigator.of(context).pop(event.id);
    } catch (err) {
      if (mounted) {
        setState(() {
          _error = apiErrorMessage(ref.read(localeProvider), err);
          _submitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final locale = ref.watch(localeProvider);

    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: context.mereytoiColors.surfaceElevated,
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(AppRadius.lg),
          ),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.lg,
              AppSpacing.sm,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: SingleChildScrollView(
              child: Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Center(
                      child: Container(
                        width: 36,
                        height: 4,
                        margin: const EdgeInsets.only(bottom: AppSpacing.md),
                        decoration: BoxDecoration(
                          color: context.mereytoiColors.divider,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    Text(
                      t(locale, ru: 'Новое мероприятие', kz: 'Жаңа іс-шара'),
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: AppSpacing.md),
                    TextFormField(
                      controller: _titleController,
                      decoration: InputDecoration(
                        labelText: t(locale, ru: 'Название', kz: 'Атауы'),
                      ),
                      validator: (v) => (v == null || v.trim().isEmpty)
                          ? t(
                              locale,
                              ru: 'Введите название',
                              kz: 'Атауын енгізіңіз',
                            )
                          : null,
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Wrap(
                      spacing: AppSpacing.xxs,
                      runSpacing: AppSpacing.xxs,
                      children: _types
                          .map(
                            (type) => ChoiceChip(
                              label: Text(
                                '${eventTypeEmoji(type)} ${eventTypeLabel(locale, type)}',
                              ),
                              selected: _type == type,
                              onSelected: (_) => setState(() => _type = type),
                            ),
                          )
                          .toList(),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    InkWell(
                      onTap: _pickDate,
                      borderRadius: BorderRadius.circular(AppRadius.sm),
                      child: InputDecorator(
                        decoration: InputDecoration(
                          labelText: t(locale, ru: 'Дата', kz: 'Күні'),
                        ),
                        child: Text(
                          _eventDate == null
                              ? t(locale, ru: 'Не выбрана', kz: 'Таңдалмаған')
                              : '${_eventDate!.day.toString().padLeft(2, '0')}.${_eventDate!.month.toString().padLeft(2, '0')}.${_eventDate!.year}',
                        ),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextFormField(
                      controller: _cityController,
                      decoration: InputDecoration(
                        labelText: t(locale, ru: 'Город', kz: 'Қала'),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Expanded(
                          child: TextFormField(
                            controller: _guestsController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: t(
                                locale,
                                ru: 'Гостей',
                                kz: 'Қонақтар',
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm),
                        Expanded(
                          child: TextFormField(
                            controller: _budgetController,
                            keyboardType: TextInputType.number,
                            decoration: InputDecoration(
                              labelText: t(
                                locale,
                                ru: 'Бюджет, ₸',
                                kz: 'Бюджет, ₸',
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.sm),
                    TextFormField(
                      controller: _commentController,
                      maxLines: 2,
                      decoration: InputDecoration(
                        labelText: t(
                          locale,
                          ru: 'Комментарий (необязательно)',
                          kz: 'Пікір (міндетті емес)',
                        ),
                      ),
                    ),
                    if (_error != null) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        _error!,
                        style: TextStyle(
                          color: context.mereytoiColors.error,
                          fontSize: 13,
                        ),
                      ),
                    ],
                    const SizedBox(height: AppSpacing.md),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: _submitting ? null : _submit,
                        child: _submitting
                            ? SizedBox(
                                width: 18,
                                height: 18,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2.2,
                                  color: context.mereytoiColors.onGold,
                                ),
                              )
                            : Text(t(locale, ru: 'Создать', kz: 'Құру')),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
