import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/app_notification.dart';
import 'providers.dart';

/// `(notifications, total)` — the first page, `GET /api/notifications`
/// (default `limit=20`). The list screen re-fetches this same first page
/// on pull-to-refresh/after a mutation rather than paginating further —
/// matches the bottom nav's own "reasonable minimum" scope for this stage.
final notificationsProvider = FutureProvider<(List<AppNotification>, int)>((
  ref,
) {
  return ref.watch(notificationServiceProvider).list();
});

/// `GET /api/notifications/unread-count` — the real count `AppBottomNav`'s
/// badge reads; always a fresh server COUNT, never derived from whatever
/// page happens to be loaded.
final unreadNotificationCountProvider = FutureProvider<int>((ref) {
  return ref.watch(notificationServiceProvider).unreadCount();
});
