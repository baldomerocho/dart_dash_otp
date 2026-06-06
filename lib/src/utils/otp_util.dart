import 'package:dart_dash_otp/src/components/otp_type.dart';

/// Helpers shared by the `otpauth://` URI generation and parsing code.
abstract class OTPUtil {
  /// Returns the `otpauth://` host segment for [type] (`totp` or `hotp`).
  static String otpTypeValue({required OTPType type}) {
    switch (type) {
      case OTPType.TOTP:
        return 'totp';
      case OTPType.HOTP:
        return 'hotp';
    }
  }

  /// Parses and validates an `otpauth://` URI of the given [expectedType].
  ///
  /// Performs the validation shared by `TOTP.fromUri` and `HOTP.fromUri`:
  ///
  /// * the scheme must be `otpauth`;
  /// * the host must match [expectedType] (`totp` or `hotp`);
  /// * a non-empty `secret` query parameter must be present.
  ///
  /// Returns the parsed [Uri] so callers can read type-specific query
  /// parameters (`period`, `counter`, ...). Throws a [FormatException] when
  /// any of the rules above is violated.
  static Uri parseOtpAuthUri({
    required String uri,
    required OTPType expectedType,
  }) {
    final parsed = Uri.tryParse(uri);
    if (parsed == null || parsed.scheme != 'otpauth') {
      throw FormatException('Not an otpauth:// URI', uri);
    }
    final expectedHost = otpTypeValue(type: expectedType);
    if (parsed.host != expectedHost) {
      throw FormatException(
        'Expected an otpauth://$expectedHost/ URI but found '
        '"${parsed.host}"',
        uri,
      );
    }
    final secret = parsed.queryParameters['secret'];
    if (secret == null || secret.isEmpty) {
      throw FormatException(
        'The otpauth:// URI is missing the required "secret" parameter',
        uri,
      );
    }
    return parsed;
  }
}
