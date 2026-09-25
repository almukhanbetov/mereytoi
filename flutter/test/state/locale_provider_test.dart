import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/storage/locale_storage.dart';
import 'package:mereytoi_app/state/locale_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Этап 10Б-А5 — before this stage, `localeProvider` was a plain
/// `StateProvider<AppLocale>`: switching language worked in-memory for the
/// current session but was never written to disk, so every app restart
/// silently reset back to `AppLocale.ru` regardless of what the user last
/// picked. Converted to a `StateNotifierProvider` backed by [LocaleStorage],
/// mirroring `ThemeModeNotifier`/`ThemeStorage` exactly (see
/// `theme_provider_test.dart`, which this file's shape deliberately copies).
void main() {
  // shared_preferences' mock channel needs a real TestWidgetsFlutterBinding
  // (same requirement `theme_provider_test.dart` already documents).
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test(
    '1. default — with nothing saved yet, the provider starts on AppLocale.ru',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);

      expect(container.read(localeProvider), AppLocale.ru);
      await container.read(localeProvider.notifier).ready;
      expect(container.read(localeProvider), AppLocale.ru);
    },
  );

  test('2. switch ru -> kz -> en -> ru', () async {
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(localeProvider.notifier).ready;

    container.read(localeProvider.notifier).setLocale(AppLocale.kz);
    expect(container.read(localeProvider), AppLocale.kz);

    container.read(localeProvider.notifier).setLocale(AppLocale.en);
    expect(container.read(localeProvider), AppLocale.en);

    container.read(localeProvider.notifier).setLocale(AppLocale.ru);
    expect(container.read(localeProvider), AppLocale.ru);
  });

  test(
    '3. persistence — setLocale() actually writes to storage, not just in-memory state',
    () async {
      final container = ProviderContainer();
      addTearDown(container.dispose);
      await container.read(localeProvider.notifier).ready;

      container.read(localeProvider.notifier).setLocale(AppLocale.en);
      await container.read(localeProvider.notifier).debugPersisted;

      expect(await LocaleStorage.instance.read(), AppLocale.en);
    },
  );

  test(
    '4. restore after restart (simulated) — a fresh notifier picks up the previously-saved language',
    () async {
      final first = ProviderContainer();
      await first.read(localeProvider.notifier).ready;
      first.read(localeProvider.notifier).setLocale(AppLocale.kz);
      await first.read(localeProvider.notifier).debugPersisted;
      first.dispose();

      // A brand-new container/notifier — nothing in memory carries over,
      // only whatever `LocaleStorage` itself now holds, exactly like a
      // fresh app process reading shared_preferences on cold start.
      final second = ProviderContainer();
      addTearDown(second.dispose);
      expect(second.read(localeProvider), AppLocale.ru); // pre-restore
      await second.read(localeProvider.notifier).ready;
      expect(second.read(localeProvider), AppLocale.kz);
    },
  );

  test(
    'an unreadable/corrupted stored value falls back to ru, never crashes',
    () async {
      SharedPreferences.setMockInitialValues({
        'app_locale_v1': 'not-a-real-locale',
      });
      final container = ProviderContainer();
      addTearDown(container.dispose);

      await container.read(localeProvider.notifier).ready;
      expect(container.read(localeProvider), AppLocale.ru);
    },
  );
}
