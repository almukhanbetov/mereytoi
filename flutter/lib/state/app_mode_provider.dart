import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/storage/app_mode_storage.dart';

/// The two ways to use MEREYTOI with one account: looking for services
/// for an event, or offering them as a business. Only a UI preference —
/// it decides what opens at launch, never what the account may do.
enum AppMode { client, business }

/// The last chosen [AppMode]; `null` until the user has chosen one (the
/// app then asks with the role choice screen).
class AppModeNotifier extends StateNotifier<AppMode?> {
  AppModeNotifier(this._storage) : super(null) {
    _ready = _restore();
  }

  final AppModeStorage _storage;
  late final Future<void> _ready;

  /// Resolves once the stored mode has been read.
  Future<void> get ready => _ready;

  Future<void>? _lastPersist;

  @visibleForTesting
  Future<void> get debugPersisted => _lastPersist ?? Future.value();

  Future<void> _restore() async {
    final saved = await _storage.read();
    if (!mounted) return;
    // A choice made while the read was in flight wins.
    state ??= saved;
  }

  void set(AppMode mode) {
    state = mode;
    _lastPersist = _storage.write(mode).catchError((_) {});
  }
}

final appModeProvider = StateNotifierProvider<AppModeNotifier, AppMode?>(
  (ref) => AppModeNotifier(AppModeStorage.instance),
);
