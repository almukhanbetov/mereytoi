import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/domain/deeplink/claim_deep_link.dart';

void main() {
  group(
    '18. parseClaimToken — a real https://mereytoi.kz/claim/:token link',
    () {
      test('extracts the token from a well-formed claim link', () {
        final uri = Uri.parse('https://mereytoi.kz/claim/deadbeef1234');
        expect(parseClaimToken(uri), 'deadbeef1234');
      });

      test('is scheme-agnostic — the same host+path also works over http', () {
        final uri = Uri.parse('http://mereytoi.kz/claim/deadbeef1234');
        expect(parseClaimToken(uri), 'deadbeef1234');
      });
    },
  );

  group('19. parseClaimToken — invalid/unrelated links return null', () {
    test('a different host is never treated as a claim link', () {
      final uri = Uri.parse('https://example.com/claim/deadbeef1234');
      expect(parseClaimToken(uri), isNull);
    });

    test('a path that is not /claim/:token is refused', () {
      expect(parseClaimToken(Uri.parse('https://mereytoi.kz/')), isNull);
      expect(parseClaimToken(Uri.parse('https://mereytoi.kz/claim')), isNull);
      expect(
        parseClaimToken(Uri.parse('https://mereytoi.kz/claim/a/b')),
        isNull,
      );
      expect(
        parseClaimToken(Uri.parse('https://mereytoi.kz/events/5')),
        isNull,
      );
    });

    test('an empty token segment is refused', () {
      expect(parseClaimToken(Uri.parse('https://mereytoi.kz/claim/')), isNull);
    });
  });
}
