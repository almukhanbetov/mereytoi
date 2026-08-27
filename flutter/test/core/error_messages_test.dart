import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/network/api_exception.dart';
import 'package:mereytoi_app/core/utils/error_messages.dart';
import 'package:mereytoi_app/state/locale_provider.dart';

void main() {
  group('apiErrorMessage', () {
    test('network failure (offline) shows a friendly RU message, not the raw exception', () {
      final message = apiErrorMessage(AppLocale.ru, const ApiException(ApiErrorType.network, debugMessage: 'SocketException: Failed host lookup'));
      expect(message, isNot(contains('SocketException')));
      expect(message, isNotEmpty);
    });

    test('every ApiErrorType has both a RU and a KZ message and they differ', () {
      for (final type in ApiErrorType.values) {
        final ru = apiErrorMessage(AppLocale.ru, ApiException(type));
        final kz = apiErrorMessage(AppLocale.kz, ApiException(type));
        expect(ru, isNotEmpty, reason: '${type.name} missing a RU message');
        expect(kz, isNotEmpty, reason: '${type.name} missing a KZ message');
        expect(ru, isNot(equals(kz)), reason: '${type.name} RU/KZ text should not be identical');
      }
    });

    test('a non-ApiException error still gets a safe fallback message instead of crashing', () {
      final message = apiErrorMessage(AppLocale.ru, StateError('something internal broke'));
      expect(message, isNot(contains('StateError')));
      expect(message, isNotEmpty);
    });
  });
}
