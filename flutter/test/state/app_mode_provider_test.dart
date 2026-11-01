import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/state/app_mode_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<ProviderContainer> restored(Map<String, Object> prefs) async {
    SharedPreferences.setMockInitialValues(prefs);
    final container = ProviderContainer();
    addTearDown(container.dispose);
    await container.read(appModeProvider.notifier).ready;
    return container;
  }

  test('nothing chosen yet reads as null', () async {
    final c = await restored({});
    expect(c.read(appModeProvider), isNull);
  });

  test('restores the last chosen mode', () async {
    expect(
      (await restored({'app_mode_v1': 'business'})).read(appModeProvider),
      AppMode.business,
    );
    expect(
      (await restored({'app_mode_v1': 'client'})).read(appModeProvider),
      AppMode.client,
    );
  });

  test('a corrupted value reads as «not chosen», never throws', () async {
    final c = await restored({'app_mode_v1': 'admin'});
    expect(c.read(appModeProvider), isNull);
  });

  test('set() updates the state and persists it', () async {
    final c = await restored({});
    c.read(appModeProvider.notifier).set(AppMode.business);
    expect(c.read(appModeProvider), AppMode.business);
    await c.read(appModeProvider.notifier).debugPersisted;
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('app_mode_v1'), 'business');
  });
}
