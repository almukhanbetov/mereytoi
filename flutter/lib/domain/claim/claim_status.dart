import '../../core/network/api_exception.dart';

/// Every outcome `ClaimScreen` can land on — mirrors
/// frontend/src/app/claim/[token]/page.js's own state machine
/// (loading → success/used/expired/invalid), plus a distinct
/// `networkError` bucket the web page doesn't separate out (it folds any
/// non-"already used"/"expired" failure into "invalid") — this app can
/// tell the two apart for free from the existing `ApiErrorType`, so it
/// does, rather than showing "invalid link" for a plain offline error.
enum ClaimStatus { loading, success, used, expired, invalid, networkError }

/// Classifies a failed `POST /api/auth/claim/:token` call. The backend
/// (`AuthHandler.Claim`) has no separate error *code* for "already used"
/// vs "expired" — both are a plain 410 Gone with only the message text
/// differing — so, same as the web claim page, this matches on that exact
/// text. A 404 (bad/garbled token, never a real claim row) is `invalid`.
ClaimStatus classifyClaimError(Object err) {
  if (err is! ApiException) return ClaimStatus.networkError;
  switch (err.type) {
    case ApiErrorType.network:
    case ApiErrorType.timeout:
    case ApiErrorType.server:
      return ClaimStatus.networkError;
    case ApiErrorType.gone:
      final message = err.debugMessage ?? '';
      if (message.contains('already used')) return ClaimStatus.used;
      if (message.contains('expired')) return ClaimStatus.expired;
      return ClaimStatus.invalid;
    case ApiErrorType.notFound:
      return ClaimStatus.invalid;
    default:
      return ClaimStatus.invalid;
  }
}
