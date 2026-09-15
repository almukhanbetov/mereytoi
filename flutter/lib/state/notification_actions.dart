import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'notification_providers.dart';
import 'providers.dart';

/// Notification mutations — same "plain async methods + invalidate the
/// providers that just went stale" shape `EventActions` already
/// established.
class NotificationActions {
  NotificationActions(this._ref);

  final Ref _ref;

  Future<void> markRead(int id) async {
    await _ref.read(notificationServiceProvider).markRead(id);
    _ref.invalidate(notificationsProvider);
    _ref.invalidate(unreadNotificationCountProvider);
  }

  Future<void> markAllRead() async {
    await _ref.read(notificationServiceProvider).markAllRead();
    _ref.invalidate(notificationsProvider);
    _ref.invalidate(unreadNotificationCountProvider);
  }
}

final notificationActionsProvider = Provider<NotificationActions>(
  (ref) => NotificationActions(ref),
);
