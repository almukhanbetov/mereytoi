import '../../core/network/api_exception.dart';

/// Minimum new-password length — the backend's own rule for password
/// reset/change (internal/passwordreset.MinPasswordLen).
const minNewPasswordLength = 8;

/// The same "strong" normalization the backend matches accounts by
/// (handlers.strongNormalizePhone): digits only, a leading 8 read as the
/// Kazakhstani 7, exactly 11 digits starting with 7 → "+7XXXXXXXXXX".
/// Anything else is null — not a number a reset code could go to.
String? normalizeKzPhone(String input) {
  var digits = input.replaceAll(RegExp(r'\D'), '');
  if (digits.length == 11 && digits.startsWith('8')) {
    digits = '7${digits.substring(1)}';
  }
  if (digits.length != 11 || !digits.startsWith('7')) return null;
  return '+$digits';
}

/// "+77011234545" → "+7 701 ••• •• 45": enough for the user to recognise
/// their number, never the whole of it.
String maskKzPhone(String normalized) {
  if (normalized.length != 12) return '••• •• ••';
  return '+7 ${normalized.substring(2, 5)} ••• •• ${normalized.substring(10)}';
}

/// What's wrong with a new password pair, if anything (checked in this
/// order, so the first problem is the one shown).
enum NewPasswordProblem { tooShort, mismatch }

NewPasswordProblem? newPasswordProblem(String password, String repeat) {
  if (password.runes.length < minNewPasswordLength) {
    return NewPasswordProblem.tooShort;
  }
  if (password != repeat) return NewPasswordProblem.mismatch;
  return null;
}

/// How a reset/change call failed, from the user's point of view.
enum PasswordResetFailure {
  invalidCode,
  weakPassword,
  tooManyRequests,

  /// Change password (signed in): the current password was wrong.
  wrongCurrentPassword,

  /// Change password by code: the account has no usable phone.
  phoneMissing,

  /// Change password by code: codes can't be delivered right now.
  deliveryUnavailable,
  other,
}

/// Reads the backend's error codes off an [ApiException] (a 400's
/// `{"error": ...}` lands in `debugMessage`; see ApiClient._mapError).
PasswordResetFailure passwordResetFailureOf(Object error) {
  if (error is! ApiException) return PasswordResetFailure.other;
  if (error.statusCode == 429) return PasswordResetFailure.tooManyRequests;
  if (error.statusCode == 503) return PasswordResetFailure.deliveryUnavailable;
  if (error.statusCode == 409 && error.debugMessage == 'phone_missing') {
    return PasswordResetFailure.phoneMissing;
  }
  if (error.statusCode == 400) {
    switch (error.debugMessage) {
      case 'invalid_code':
        return PasswordResetFailure.invalidCode;
      case 'weak_password':
      case 'password_too_long':
        return PasswordResetFailure.weakPassword;
      case 'wrong_current_password':
        return PasswordResetFailure.wrongCurrentPassword;
    }
  }
  return PasswordResetFailure.other;
}
