import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/storage/theme_storage.dart';
import 'package:mereytoi_app/state/theme_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  // shared_preferences' mock channel needs a real TestWidgetsFlutterBinding
  // (same requirement `cart_provider_test.dart` already documents).
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    '1. default — with nothing saved yet, the provider starts on ThemeMode.system',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(themeModeProvider), ThemeMode.system);
      await container.read(themeModeProvider.notifier).ready;
      // Still system — an empty store must never be misread as an explicit
      // choice for one specific mode.
      expect(container.read(themeModeProvider), ThemeMode.system);
    },
  );

  test('2. switch dark -> light', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(themeModeProvider.notifier).ready;

    container.read(themeModeProvider.notifier).setMode(ThemeMode.dark);
    expect(container.read(themeModeProvider), ThemeMode.dark);

    container.read(themeModeProvider.notifier).setMode(ThemeMode.light);
    expect(container.read(themeModeProvider), ThemeMode.light);
  });

  test('3. switch light -> dark', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(themeModeProvider.notifier).ready;

    container.read(themeModeProvider.notifier).setMode(ThemeMode.light);
    expect(container.read(themeModeProvider), ThemeMode.light);

    container.read(themeModeProvider.notifier).setMode(ThemeMode.dark);
    expect(container.read(themeModeProvider), ThemeMode.dark);
  });

  test(
    '4. persistence — setMode() actually writes to storage, not just in-memory state',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(themeModeProvider.notifier).ready;

      container.read(themeModeProvider.notifier).setMode(ThemeMode.light);
      await container.read(themeModeProvider.notifier).debugPersisted;

      expect(await ThemeStorage.instance.read(), ThemeMode.light);
    },
  );

  test(
    '5. restore after restart (simulated) — a fresh notifier picks up the previously-saved mode',
    () async {
      final first = ProviderContainer();
      await first.read(themeModeProvider.notifier).ready;
      first.read(themeModeProvider.notifier).setMode(ThemeMode.dark);
      await first.read(themeModeProvider.notifier).debugPersisted;
      first.dispose();

      // A brand-new container/notifier — nothing in memory carries over,
      // only whatever `ThemeStorage` itself now holds, exactly like a
      // fresh app process reading shared_preferences on cold start.
      final second = ProviderContainer();
      addTearDown(second.dispose);
      expect(second.read(themeModeProvider), ThemeMode.system); // pre-restore
      await second.read(themeModeProvider.notifier).ready;
      expect(second.read(themeModeProvider), ThemeMode.dark);
    },
  );

  test(
    'an unreadable/corrupted stored value falls back to system, never crashes',
    () async {
      SharedPreferences.setMockInitialValues({
        'theme_mode_v1': 'not-a-real-mode',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(themeModeProvider.notifier).ready;
      expect(container.read(themeModeProvider), ThemeMode.system);
    },
  );
}
