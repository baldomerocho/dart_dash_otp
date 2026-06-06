import 'package:crypto/crypto.dart';
import 'package:dart_dash_otp/src/components/otp_algorithm.dart';

/// Maps [OTPAlgorithm] cases to `package:crypto` HMAC implementations and to
/// the canonical labels used in `otpauth://` URIs.
abstract class AlgorithmUtil {
  /// Builds an [Hmac] instance for the given [algorithm] using [key].
  ///
  /// Throws [ArgumentError] when either argument is null, so callers do not
  /// have to deal with nullable return types.
  static Hmac createHmacFor({
    required OTPAlgorithm algorithm,
    required List<int> key,
  }) {
    switch (algorithm) {
      case OTPAlgorithm.SHA1:
        return Hmac(sha1, key);
      case OTPAlgorithm.SHA256:
        return Hmac(sha256, key);
      case OTPAlgorithm.SHA384:
        return Hmac(sha384, key);
      case OTPAlgorithm.SHA512:
        return Hmac(sha512, key);
    }
  }

  /// Returns the canonical `otpauth://` label for [algorithm]
  /// (`SHA1`, `SHA256`, `SHA384` or `SHA512`).
  static String rawValue({required OTPAlgorithm algorithm}) {
    switch (algorithm) {
      case OTPAlgorithm.SHA1:
        return 'SHA1';
      case OTPAlgorithm.SHA256:
        return 'SHA256';
      case OTPAlgorithm.SHA384:
        return 'SHA384';
      case OTPAlgorithm.SHA512:
        return 'SHA512';
    }
  }

  /// Parses an algorithm label (as found in `otpauth://` URIs) into an
  /// [OTPAlgorithm]. Matching is case-insensitive.
  ///
  /// Throws a [FormatException] when [value] does not name a supported
  /// algorithm.
  static OTPAlgorithm parse(String value) {
    switch (value.toUpperCase()) {
      case 'SHA1':
        return OTPAlgorithm.SHA1;
      case 'SHA256':
        return OTPAlgorithm.SHA256;
      case 'SHA384':
        return OTPAlgorithm.SHA384;
      case 'SHA512':
        return OTPAlgorithm.SHA512;
    }
    throw FormatException('Unsupported HMAC algorithm', value);
  }
}
