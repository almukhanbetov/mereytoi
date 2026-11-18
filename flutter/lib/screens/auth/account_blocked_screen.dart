import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_theme.dart';
import '../../models/account_block.dart';
import '../../state/locale_provider.dart';
import '../../widgets/app_card.dart';

final _date = DateFormat('dd.MM.yyyy HH:mm');

/// «Аккаунт заблокирован» — shown instead of a technical code or a silent
/// sign-out: on sign-in, when a live session is refused, and after a
/// recovery on a blocked account (then with the new backup code, which must
/// not be lost — the old one is spent).
class AccountBlockedScreen extends ConsumerWidget {
  const AccountBlockedScreen({super.key, required this.block});

  final AccountBlock block;

  /// Opens the screen over everything else on [navigator].
  static Future<void> open(NavigatorState navigator, AccountBlock block) =>
      navigator.push(
        MaterialPageRoute(
          fullscreenDialog: true,
          builder: (_) => AccountBlockedScreen(block: block),
        ),
      );

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locale = ref.watch(localeProvider);
    final colors = context.mereytoiColors;
    final textTheme = Theme.of(context).textTheme;
    final until = block.until;
    final term = until == null
        ? t(locale, ru: 'Бессрочно', kz: 'Мерзімсіз', en: 'Indefinite')
        : t(
            locale,
            ru: 'До ${_date.format(until)}',
            kz: '${_date.format(until)} дейін',
            en: 'Until ${_date.format(until)}',
          );
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: Text(t(locale, ru: 'Аккаунт', kz: 'Аккаунт', en: 'Account')),
      ),
      body: SafeArea(
        child: ListView(
          key: const ValueKey('account-blocked'),
          padding: const EdgeInsets.all(AppSpacing.lg),
          children: [
            Icon(Icons.lock_person_outlined, size: 48, color: colors.error),
            const SizedBox(height: AppSpacing.sm),
            Text(
              t(
                locale,
                ru: 'Аккаунт заблокирован',
                kz: 'Аккаунт бұғатталған',
                en: 'Your account is blocked',
              ),
              textAlign: TextAlign.center,
              style: textTheme.titleLarge,
            ),
            const SizedBox(height: AppSpacing.lg),
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    t(locale, ru: 'Срок', kz: 'Мерзімі', en: 'Term'),
                    style: textTheme.bodySmall,
                  ),
                  Text(
                    term,
                    key: const ValueKey('account-blocked-term'),
                    style: textTheme.bodyLarge?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: until == null ? colors.error : null,
                    ),
                  ),
                  if (block.reason.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Text(
                      t(locale, ru: 'Причина', kz: 'Себебі', en: 'Reason'),
                      style: textTheme.bodySmall,
                    ),
                    Text(
                      block.reason,
                      key: const ValueKey('account-blocked-reason'),
                      style: textTheme.bodyLarge,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            Text(
              t(
                locale,
                ru:
                    'Пока действует блокировка, войти в MEREYTOI нельзя. '
                    'Если вы считаете это ошибкой, свяжитесь с поддержкой.',
                kz:
                    'Бұғаттау әрекет етіп тұрғанда MEREYTOI-ға кіру мүмкін '
                    'емес. Егер бұл қате деп ойласаңыз, қолдау қызметіне '
                    'хабарласыңыз.',
                en:
                    "While the block is in force you can't sign in to "
                    'MEREYTOI. If you think this is a mistake, contact '
                    'support.',
              ),
              style: textTheme.bodyMedium?.copyWith(
                color: colors.textSecondary,
              ),
            ),
            if (block.passwordReset && block.recoveryCode.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.lg),
              _NewCode(code: block.recoveryCode, locale: locale),
            ],
            const SizedBox(height: AppSpacing.xl),
            ElevatedButton(
              key: const ValueKey('account-blocked-ok'),
              onPressed: () => Navigator.of(context).maybePop(),
              child: Text(
                t(locale, ru: 'Понятно', kz: 'Түсінікті', en: 'Got it'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _NewCode extends StatelessWidget {
  const _NewCode({required this.code, required this.locale});

  final String code;
  final AppLocale locale;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t(
              locale,
              ru:
                  'Пароль изменён. Сохраните новый резервный код — старый '
                  'больше не действует.',
              kz:
                  'Құпиясөз өзгертілді. Жаңа резервтік кодты сақтаңыз — '
                  'ескісі енді жарамсыз.',
              en:
                  'Your password was changed. Save your new backup code — '
                  'the old one no longer works.',
            ),
            style: textTheme.bodyMedium,
          ),
          const SizedBox(height: AppSpacing.sm),
          SelectableText(
            code,
            key: const ValueKey('account-blocked-code'),
            style: textTheme.titleLarge?.copyWith(letterSpacing: 1.5),
          ),
          const SizedBox(height: AppSpacing.xs),
          OutlinedButton.icon(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: code));
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    t(
                      locale,
                      ru: 'Код скопирован',
                      kz: 'Код көшірілді',
                      en: 'Code copied',
                    ),
                  ),
                ),
              );
            },
            icon: const Icon(Icons.copy_rounded, size: 18),
            label: Text(
              t(
                locale,
                ru: 'Скопировать код',
                kz: 'Кодты көшіру',
                en: 'Copy code',
              ),
            ),
          ),
        ],
      ),
    );
  }
}
