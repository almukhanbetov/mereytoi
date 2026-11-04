import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'providers.dart';

/// Whether a recovery code can be sent by email. Any failure means "no": the
/// other ways to recover stay on offer.
final emailOtpAvailableProvider = FutureProvider.autoDispose<bool>((ref) async {
  try {
    return await ref.watch(authServiceProvider).fetchEmailOtpAvailable();
  } catch (_) {
    return false;
  }
});

/// Whether "Forgot password?" should be offered: the backend says codes
/// can be delivered. Any failure (offline, older backend without the
/// endpoint) simply means "no" — it must never get in the way of signing in.
final passwordResetAvailableProvider = FutureProvider.autoDispose<bool>((
  ref,
) async {
  try {
    return await ref.watch(authServiceProvider).fetchPasswordResetConfig();
  } catch (_) {
    return false;
  }
});
