import 'package:flutter_test/flutter_test.dart';
import 'package:mereytoi_app/core/network/api_exception.dart';
import 'package:mereytoi_app/domain/claim/claim_status.dart';

void main() {
  group('classifyClaimError', () {
    test(
      'a 410 Gone with "already used" in the message classifies as used',
      () {
        const err = ApiException(
          ApiErrorType.gone,
          statusCode: 410,
          debugMessage: 'claim link already used',
        );
        expect(classifyClaimError(err), ClaimStatus.used);
      },
    );

    test('a 410 Gone with "expired" in the message classifies as expired', () {
      const err = ApiException(
        ApiErrorType.gone,
        statusCode: 410,
        debugMessage: 'claim link expired',
      );
      expect(classifyClaimError(err), ClaimStatus.expired);
    });

    test('a 404 (garbled/unknown token) classifies as invalid', () {
      const err = ApiException(
        ApiErrorType.notFound,
        statusCode: 404,
        debugMessage: 'claim link not found',
      );
      expect(classifyClaimError(err), ClaimStatus.invalid);
    });

    test(
      'network/timeout/server failures classify as networkError, not invalid',
      () {
        expect(
          classifyClaimError(const ApiException(ApiErrorType.network)),
          ClaimStatus.networkError,
        );
        expect(
          classifyClaimError(const ApiException(ApiErrorType.timeout)),
          ClaimStatus.networkError,
        );
        expect(
          classifyClaimError(const ApiException(ApiErrorType.server)),
          ClaimStatus.networkError,
        );
      },
    );

    test(
      'a non-ApiException error (e.g. a bug) still falls back to networkError, never throws',
      () {
        expect(classifyClaimError(Exception('boom')), ClaimStatus.networkError);
      },
    );
  });
}
