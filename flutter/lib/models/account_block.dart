import '../core/network/api_exception.dart';

/// An administrator's block on the signed-in (or signing-in) account, as
/// the server reports it: 401 `account_blocked` on a live session, 403 on
/// sign-in or recovery. [until] null means indefinite. After a recovery the
/// password did change, and [recoveryCode] is the new backup code — it must
/// be shown, the old one is spent.
class AccountBlock {
  const AccountBlock({
    this.until,
    this.reason = '',
    this.passwordReset = false,
    this.recoveryCode = '',
  });

  final DateTime? until;
  final String reason;
  final bool passwordReset;
  final String recoveryCode;

  bool get indefinite => until == null;

  factory AccountBlock.fromJson(Map<String, dynamic> j) => AccountBlock(
    until: j['blocked_until'] is String
        ? DateTime.tryParse(j['blocked_until'] as String)?.toLocal()
        : null,
    reason: j['reason'] as String? ?? '',
    passwordReset: j['password_reset'] == true,
    recoveryCode: j['recovery_code'] as String? ?? '',
  );
}

/// The block behind an API failure, or null when it wasn't one.
AccountBlock? accountBlockFrom(Object error) {
  if (error is! ApiException) return null;
  final data = error.data;
  if (data == null || data['error'] != 'account_blocked') return null;
  return AccountBlock.fromJson(data);
}
