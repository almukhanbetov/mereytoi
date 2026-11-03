import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_provider.dart';
import 'providers.dart';

/// Whether the signed-in account has a password-recovery backup code:
/// true/false, or null when signed out or it can't be determined. Taken
/// from the current user when already known, otherwise from `GET
/// /api/auth/me` (a plain login response doesn't carry it). Never exposes
/// the code itself — no API ever returns an existing one.
final recoveryCodeStatusProvider = FutureProvider.autoDispose<bool?>((
  ref,
) async {
  final auth = ref.watch(authProvider);
  if (auth is! AuthAuthenticated) return null;
  final known = auth.user.hasRecoveryCode;
  if (known != null) return known;
  try {
    final me = await ref.read(authServiceProvider).fetchMe();
    return me.hasRecoveryCode;
  } catch (_) {
    return null;
  }
});
