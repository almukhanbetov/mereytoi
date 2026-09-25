import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../screens/claim/claim_screen.dart';
import '../../state/locale_provider.dart';

/// Extracts a claim token from either a bare token or a full claim URL
/// (`.../claim/<token>` — with or without a trailing slash/query string).
/// Real OS-level interception of `https://mereytoi.kz/claim/:token` links
/// (Android App Links / iOS Universal Links) needs a verification file
/// hosted on that domain — web infra this stage explicitly may not touch —
/// so this manual paste-the-link flow is the actual, fully-working entry
/// point into the real `/api/auth/claim/:token` contract; see the stage
/// report for the full explanation.
String? extractClaimToken(String input) {
  final trimmed = input.trim();
  if (trimmed.isEmpty) return null;

  final match = RegExp(r'claim/([A-Za-z0-9]+)').firstMatch(trimmed);
  if (match != null) return match.group(1);

  // A bare token: hex-ish characters, no slashes/spaces.
  if (RegExp(r'^[A-Za-z0-9]{8,}$').hasMatch(trimmed)) return trimmed;
  return null;
}

/// Opens the bottom sheet for pasting a claim link/token, pushing
/// [ClaimScreen] once a token is recognized in the input.
Future<void> openClaimEntrySheet(BuildContext context) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ClaimEntrySheet(),
  );
}

class _ClaimEntrySheet extends ConsumerStatefulWidget {
  const _ClaimEntrySheet();

  @override
  ConsumerState<_ClaimEntrySheet> createState() => _ClaimEntrySheetState();
}

class _ClaimEntrySheetState extends ConsumerState<_ClaimEntrySheet> {
  final _controller = TextEditingController();
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final token = extractClaimToken(_controller.text);
    if (token == null) {
      setState(
        () => _error = t(
          ref.read(localeProvider),
          ru: 'Не удалось распознать ссылку',
          kz: 'Сілтемені тану мүмкін болмады',
          en: 'Couldn\'t recognize the link',
        ),
      );
      return;
    }
    Navigator.of(context).pop();
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => ClaimScreen(token: token)));
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
              AppSpacing.md,
              AppSpacing.lg,
              AppSpacing.lg,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  t(
                    locale,
                    ru: 'Ссылка-приглашение',
                    kz: 'Шақыру сілтемесі',
                    en: 'Invite link',
                  ),
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  t(
                    locale,
                    ru: 'Вставьте ссылку или код, который вам прислали',
                    kz: 'Сізге жіберілген сілтемені немесе кодты қойыңыз',
                    en: 'Paste the link or code you were sent',
                  ),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
                const SizedBox(height: AppSpacing.sm),
                TextField(
                  controller: _controller,
                  autofocus: true,
                  decoration: InputDecoration(hintText: 'mereytoi.kz/claim/…'),
                  onSubmitted: (_) => _submit(),
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
                    onPressed: _submit,
                    child: Text(
                      t(locale, ru: 'Открыть', kz: 'Ашу', en: 'Open'),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
