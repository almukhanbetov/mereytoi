import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/network/api_exception.dart';
import '../models/admin.dart';
import '../services/admin_service.dart';
import 'auth_provider.dart';
import 'providers.dart';

final adminServiceProvider = Provider<AdminService>(
  (ref) => AdminService(ref.watch(apiClientProvider)),
);

/// The id of an account whose admin rights the server has just refused
/// (403 "admin access required"): its admin screens close at once, before
/// the refreshed profile even arrives. Tied to the user id, so signing in as
/// someone else starts clean.
final adminRevokedForUserProvider = StateProvider<int?>((ref) => null);

/// Whether the signed-in account may use the admin panel right now. The
/// server is the authority (it re-reads the role on every request); this
/// only decides what the app shows.
final isAdminProvider = Provider<bool>((ref) {
  final auth = ref.watch(authProvider);
  if (auth is! AuthAuthenticated || !auth.user.isAdmin) return false;
  return ref.watch(adminRevokedForUserProvider) != auth.user.id;
});

/// The server's RequireAdmin refusal — the one 403 that means "no longer an
/// administrator". Other 403s from admin endpoints (e.g. cannot_block_admin)
/// are ordinary refusals.
bool isAdminRightsLost(Object error) =>
    error is ApiException &&
    error.type == ApiErrorType.forbidden &&
    error.debugMessage == 'admin access required';

/// Call on any admin API failure: when the rights are gone, the admin
/// screens close and the profile is refreshed so the entry disappears too.
/// Returns whether that happened.
bool handleAdminRightsLost(WidgetRef ref, Object error) {
  if (!isAdminRightsLost(error)) return false;
  final auth = ref.read(authProvider);
  if (auth is AuthAuthenticated) {
    ref.read(adminRevokedForUserProvider.notifier).state = auth.user.id;
    ref.read(authProvider.notifier).refreshMe().catchError((_) {});
  }
  return true;
}

final adminSummaryProvider = FutureProvider.autoDispose<AdminSummary>(
  (ref) => ref.watch(adminServiceProvider).summary(),
);

final adminUserDetailProvider = FutureProvider.autoDispose
    .family<AdminUserDetail, int>(
      (ref, id) => ref.watch(adminServiceProvider).user(id),
    );

final adminReportDetailProvider = FutureProvider.autoDispose
    .family<AdminReportDetail, int>(
      (ref, id) => ref.watch(adminServiceProvider).report(id),
    );
