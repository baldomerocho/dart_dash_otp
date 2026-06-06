import 'package:dart_dash_otp/src/components/otp_algorithm.dart';
import 'package:dart_dash_otp/src/components/otp_type.dart';
import 'package:dart_dash_otp/src/utils/algorithm_util.dart';
import 'package:dart_dash_otp/src/utils/generic_util.dart';
import 'package:dart_dash_otp/src/utils/otp_util.dart';

import 'otp.dart';

/// HMAC-based One-Time Password
/// ([RFC 4226](https://tools.ietf.org/html/rfc4226)).
///
/// An HOTP derives a short numeric code from a shared [secret] and a
/// monotonically increasing [counter] that both parties keep in sync:
///
/// ```dart
/// // RFC 4226 Appendix D seed ("12345678901234567890" in Base32).
/// final hotp = HOTP(secret: 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ');
/// hotp.at(counter: 0);                          // '755224'
/// hotp.verify(otp: code, counter: 0, window: 3); // look-ahead window
/// ```
class HOTP extends OTP {
  /// Initial counter used when serialising the token as an `otpauth://` URL.
  final int counter;

  @override
  OTPType get type => OTPType.HOTP;

  @override
  Map<String, Object?> get extraUrlProperties => {'counter': counter};

  HOTP({
    required super.secret,
    this.counter = 0,
    super.digits = 6,
    super.algorithm = OTPAlgorithm.SHA1,
  }) {
    if (counter < 0) {
      throw ArgumentError.value(counter, 'counter', 'must be non-negative');
    }
  }

  /// Creates an [HOTP] from an `otpauth://hotp/...` URI in the Google
  /// Authenticator
  /// [Key URI Format](https://github.com/google/google-authenticator/wiki/Key-Uri-Format),
  /// typically obtained by scanning a QR code.
  ///
  /// Reads the `secret`, `digits`, `counter` and `algorithm` query
  /// parameters; `digits` defaults to 6 and `algorithm` to SHA-1. The
  /// `counter` parameter is required for HOTP URIs by the specification.
  /// The label and `issuer` are display metadata and are not stored on the
  /// token.
  ///
  /// Throws a [FormatException] when [uri] is not a valid `otpauth://hotp/`
  /// URI or lacks a numeric `counter`, and [ArgumentError] when a parameter
  /// is out of range (for example `digits=10`).
  factory HOTP.fromUri(String uri) {
    final parsed = OTPUtil.parseOtpAuthUri(
      uri: uri,
      expectedType: OTPType.HOTP,
    );
    final params = parsed.queryParameters;
    final counter = int.tryParse(params['counter'] ?? '');
    if (counter == null) {
      throw FormatException(
        'otpauth://hotp/ URIs require a numeric "counter" parameter',
        uri,
      );
    }
    return HOTP(
      secret: params['secret']!,
      counter: counter,
      digits: int.tryParse(params['digits'] ?? '') ?? 6,
      algorithm: params.containsKey('algorithm')
          ? AlgorithmUtil.parse(params['algorithm']!)
          : OTPAlgorithm.SHA1,
    );
  }

  /// Generates the HOTP value for the given [counter].
  ///
  /// Returns `null` when [counter] is negative. When [counter] is omitted the
  /// instance's own [counter] value is used.
  String? at({int? counter}) {
    final value = counter ?? this.counter;
    if (value < 0) {
      return null;
    }
    return generateOTP(input: value);
  }

  /// Verifies that [otp] matches the code generated for [counter].
  ///
  /// [window] allows the verifier to accept codes from `counter`,
  /// `counter + 1`, ..., `counter + window` to handle synchronisation drift
  /// between client and server. Defaults to `0` (strict match).
  ///
  /// Uses a constant-time comparison so response timing does not leak how
  /// close a guessed code was to the expected one. After a successful match
  /// the server must persist the next counter value to prevent replay.
  bool verify({String? otp, int? counter, int window = 0}) {
    if (otp == null || counter == null || counter < 0) {
      return false;
    }
    if (window < 0) {
      throw ArgumentError.value(window, 'window', 'must be non-negative');
    }
    for (var i = 0; i <= window; i++) {
      final candidate = generateOTP(input: counter + i);
      if (Util.constantTimeEquals(otp, candidate)) {
        return true;
      }
    }
    return false;
  }
}
