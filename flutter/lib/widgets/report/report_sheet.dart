import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/network/api_exception.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/error_messages.dart';
import '../../screens/auth/login_screen.dart';
import '../../screens/profile/my_reports_screen.dart';
import '../../state/auth_provider.dart';
import '../../state/locale_provider.dart';
import '../../state/report_providers.dart';
import 'report_labels.dart';

/// «Пожаловаться» — a small, quiet text button. A guest is asked to sign in.
class ReportButton extends ConsumerWidget {
  const ReportButton({
    super.key,
    required this.targetType,
    required this.targetId,
    required this.targetName,
  });

  final String targetType;
  final int targetId;
  final String targetName;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final colors = context.mereytoiColors;
    return TextButton.icon(
      key: ValueKey('report-$targetType-$targetId'),
      onPressed: () => showReportSheet(
        context,
        ref,
        targetType: targetType,
        targetId: targetId,
        targetName: targetName,
      ),
      style: TextButton.styleFrom(
        minimumSize: const Size(48, 48),
        foregroundColor: colors.textSecondary,
      ),
      icon: const Icon(Icons.outlined_flag_rounded, size: 18),
      label: Text(
        t(locale, ru: 'Пожаловаться', kz: 'Шағым жасау', en: 'Report'),
      ),
    );
  }
}

/// Opens the report flow: reason and details → confirmation → result.
/// Nothing is sent until «Отправить» on the confirmation step.
Future<void> showReportSheet(
  BuildContext context,
  WidgetRef ref, {
  required String targetType,
  required int targetId,
  required String targetName,
}) async {
  if (ref.read(authProvider) is! AuthAuthenticated) {
    final locale = ref.read(localeProvider);
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            t(
              locale,
              ru: 'Войдите, чтобы пожаловаться',
              kz: 'Шағым жасау үшін кіріңіз',
              en: 'Sign in to report',
            ),
          ),
        ),
      );
    await Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => const LoginScreen()));
    return;
  }
  await showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (_) => ReportSheet(
      targetType: targetType,
      targetId: targetId,
      targetName: targetName,
    ),
  );
}

enum _Step { form, confirm, sent, duplicate }

class ReportSheet extends ConsumerStatefulWidget {
  const ReportSheet({
    super.key,
    required this.targetType,
    required this.targetId,
    required this.targetName,
  });

  final String targetType;
  final int targetId;
  final String targetName;

  @override
  ConsumerState<ReportSheet> createState() => _ReportSheetState();
}

class _ReportSheetState extends ConsumerState<ReportSheet> {
  final _details = TextEditingController();
  String? _reason;
  _Step _step = _Step.form;
  bool _tried = false;
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _details.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _details.dispose();
    super.dispose();
  }

  bool get _detailsRequired => _reason == 'other';

  String? _detailsError(AppLocale l) {
    final n = _details.text.trim().runes.length;
    if (_detailsRequired && n < 5) {
      return reportErrorText(l, 'details_required');
    }
    if (n > 2000) {
      return t(
        l,
        ru: 'Не длиннее 2000 символов',
        kz: '2000 таңбадан аспауы керек',
        en: 'At most 2000 characters',
      );
    }
    return null;
  }

  void _next(AppLocale l) {
    setState(() => _tried = true);
    if (_reason == null || _detailsError(l) != null) return;
    setState(() {
      _step = _Step.confirm;
      _error = null;
    });
  }

  Future<void> _send(AppLocale l) async {
    if (_sending) return;
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await ref
          .read(reportServiceProvider)
          .create(
            targetType: widget.targetType,
            targetId: widget.targetId,
            reason: _reason!,
            details: _details.text.trim(),
          );
      ref.invalidate(myReportsProvider);
      if (mounted) setState(() => _step = _Step.sent);
    } catch (e) {
      if (!mounted) return;
      final code = e is ApiException ? e.debugMessage : null;
      if (code == 'duplicate_report') {
        setState(() => _step = _Step.duplicate);
      } else {
        setState(
          () => _error = reportErrorText(l, code) ?? apiErrorMessage(l, e),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _openMine() {
    final navigator = Navigator.of(context)..pop();
    navigator.push(MaterialPageRoute(builder: (_) => const MyReportsScreen()));
  }

  @override
  Widget build(BuildContext context) {
    final l = ref.watch(localeProvider);
    final textTheme = Theme.of(context).textTheme;
    final colors = context.mereytoiColors;
    final target =
        '${reportTargetLabel(l, widget.targetType)}: «${widget.targetName}»';

    Widget body;
    switch (_step) {
      case _Step.form:
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t(
                l,
                ru: 'Что не так?',
                kz: 'Не дұрыс емес?',
                en: "What's wrong?",
              ),
              style: textTheme.titleSmall,
            ),
            const SizedBox(height: AppSpacing.xs),
            RadioGroup<String>(
              groupValue: _reason,
              onChanged: (v) => setState(() => _reason = v),
              child: Column(
                children: [
                  for (final code in reportReasonCodes)
                    RadioListTile<String>(
                      key: ValueKey('report-reason-$code'),
                      value: code,
                      title: Text(reportReasonLabel(l, code)),
                      contentPadding: EdgeInsets.zero,
                      dense: true,
                    ),
                ],
              ),
            ),
            if (_tried && _reason == null)
              Text(
                t(
                  l,
                  ru: 'Выберите причину',
                  kz: 'Себепті таңдаңыз',
                  en: 'Choose a reason',
                ),
                key: const ValueKey('report-reason-error'),
                style: textTheme.bodySmall?.copyWith(color: colors.error),
              ),
            const SizedBox(height: AppSpacing.sm),
            TextField(
              key: const ValueKey('report-details'),
              controller: _details,
              minLines: 2,
              maxLines: 5,
              maxLength: 2000,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: _detailsRequired
                    ? t(
                        l,
                        ru: 'Опишите проблему (обязательно)',
                        kz: 'Мәселені сипаттаңыз (міндетті)',
                        en: 'Describe the problem (required)',
                      )
                    : t(
                        l,
                        ru: 'Подробности (необязательно)',
                        kz: 'Толығырақ (міндетті емес)',
                        en: 'Details (optional)',
                      ),
                errorText: _tried ? _detailsError(l) : null,
                errorMaxLines: 2,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            ElevatedButton(
              key: const ValueKey('report-next'),
              onPressed: () => _next(l),
              child: Text(t(l, ru: 'Далее', kz: 'Әрі қарай', en: 'Next')),
            ),
          ],
        );
      case _Step.confirm:
        final details = _details.text.trim();
        body = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              key: const ValueKey('report-summary'),
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: colors.surfaceSoft,
                borderRadius: BorderRadius.circular(AppRadius.md),
                border: Border.all(color: colors.border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(target, style: textTheme.bodyMedium),
                  const SizedBox(height: 4),
                  Text(
                    '${t(l, ru: 'Причина', kz: 'Себебі', en: 'Reason')}: '
                    '${reportReasonLabel(l, _reason!)}',
                    style: textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (details.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(details, style: textTheme.bodySmall),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              t(
                l,
                ru:
                    'Жалобу рассмотрит администратор. Тот, на кого вы '
                    'жалуетесь, не узнает, кто её отправил.',
                kz:
                    'Шағымды әкімші қарайды. Сіз шағымданған адам оны кім '
                    'жібергенін білмейді.',
                en:
                    "An administrator will review it. The person you're "
                    "reporting won't know who sent it.",
              ),
              style: textTheme.bodySmall,
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                _error!,
                key: const ValueKey('report-error'),
                style: textTheme.bodySmall?.copyWith(color: colors.error),
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            ElevatedButton(
              key: const ValueKey('report-send'),
              onPressed: _sending ? null : () => _send(l),
              child: _sending
                  ? const SizedBox.square(
                      dimension: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(t(l, ru: 'Отправить', kz: 'Жіберу', en: 'Send')),
            ),
            TextButton(
              key: const ValueKey('report-back'),
              onPressed: _sending
                  ? null
                  : () => setState(() => _step = _Step.form),
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(t(l, ru: 'Назад', kz: 'Артқа', en: 'Back')),
            ),
          ],
        );
      case _Step.sent:
      case _Step.duplicate:
        final sent = _step == _Step.sent;
        body = Column(
          key: ValueKey(sent ? 'report-sent' : 'report-duplicate'),
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              sent
                  ? Icons.check_circle_outline_rounded
                  : Icons.info_outline_rounded,
              size: 40,
              color: sent ? colors.success : colors.goldPrimary,
            ),
            const SizedBox(height: AppSpacing.sm),
            Text(
              sent
                  ? t(
                      l,
                      ru: 'Жалоба отправлена',
                      kz: 'Шағым жіберілді',
                      en: 'Report sent',
                    )
                  : t(
                      l,
                      ru: 'Жалоба уже отправлена',
                      kz: 'Шағым бұрын жіберілген',
                      en: 'Already reported',
                    ),
              textAlign: TextAlign.center,
              style: textTheme.titleMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              sent
                  ? t(
                      l,
                      ru: 'Статус можно посмотреть в разделе «Мои жалобы».',
                      kz: 'Мәртебесін «Менің шағымдарым» бөлімінен көруге болады.',
                      en: 'You can follow its status in «My reports».',
                    )
                  : reportErrorText(l, 'duplicate_report')!,
              textAlign: TextAlign.center,
              style: textTheme.bodyMedium,
            ),
            const SizedBox(height: AppSpacing.md),
            ElevatedButton(
              key: const ValueKey('report-done'),
              onPressed: () => Navigator.of(context).pop(),
              child: Text(t(l, ru: 'Готово', kz: 'Дайын', en: 'Done')),
            ),
            TextButton(
              key: const ValueKey('report-open-mine'),
              onPressed: _openMine,
              style: TextButton.styleFrom(
                minimumSize: const Size.fromHeight(48),
              ),
              child: Text(
                t(
                  l,
                  ru: 'Мои жалобы',
                  kz: 'Менің шағымдарым',
                  en: 'My reports',
                ),
              ),
            ),
          ],
        );
    }

    return PopScope(
      canPop: !_sending,
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(AppSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (_step == _Step.form || _step == _Step.confirm) ...[
                Text(
                  _step == _Step.form
                      ? t(
                          l,
                          ru: 'Пожаловаться',
                          kz: 'Шағым жасау',
                          en: 'Report',
                        )
                      : t(
                          l,
                          ru: 'Отправить жалобу?',
                          kz: 'Шағымды жіберу керек пе?',
                          en: 'Send the report?',
                        ),
                  style: textTheme.titleMedium,
                ),
                if (_step == _Step.form) ...[
                  const SizedBox(height: 4),
                  Text(
                    target,
                    style: textTheme.bodyMedium?.copyWith(
                      color: colors.textSecondary,
                    ),
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
              ],
              body,
            ],
          ),
        ),
      ),
    );
  }
}
