import 'package:dart_dash_otp/src/components/otp_algorithm.dart';
import 'package:dart_dash_otp/src/components/otp_type.dart';
import 'package:dart_dash_otp/src/utils/algorithm_util.dart';
import 'package:dart_dash_otp/src/utils/generic_util.dart';
import 'package:dart_dash_otp/src/utils/otp_util.dart';

import 'otp.dart';

/// Time-based One-Time Password
/// ([RFC 6238](https://tools.ietf.org/html/rfc6238)).
///
/// A TOTP derives a short numeric code from a shared [secret] and the
/// current time, divided into steps of [interval] seconds:
///
/// ```dart
/// final totp = TOTP(secret: 'J22U6B3WIWRRBTAV');
/// totp.now();                       // e.g. '382637'
/// totp.verify(otp: code, window: 1); // tolerate ±1 time step of drift
/// ```
class TOTP extends OTP {
  /// Length of a time step, in seconds.
  final int interval;

  @override
  OTPType get type => OTPType.TOTP;

  @override
  Map<String, Object?> get extraUrlProperties => {'period': interval};

  TOTP({
    required super.secret,
    super.digits = 6,
    this.interval = 30,
    super.algorithm = OTPAlgorithm.SHA1,
  }) {
    if (interval <= 0) {
      throw ArgumentError.value(interval, 'interval', 'must be positive');
    }
  }

  /// Creates a [TOTP] from an `otpauth://totp/...` URI in the Google
  /// Authenticator
  /// [Key URI Format](https://github.com/google/google-authenticator/wiki/Key-Uri-Format),
  /// typically obtained by scanning a QR code.
  ///
  /// Reads the `secret`, `digits`, `period` and `algorithm` query
  /// parameters; `digits` defaults to 6, `period` to 30 seconds and
  /// `algorithm` to SHA-1, matching the specification. The label and
  /// `issuer` are display metadata and are not stored on the token.
  ///
  /// Throws a [FormatException] when [uri] is not a valid `otpauth://totp/`
  /// URI and [ArgumentError] when a parameter is out of range (for example
  /// `digits=10`).
  factory TOTP.fromUri(String uri) {
    final parsed = OTPUtil.parseOtpAuthUri(
      uri: uri,
      expectedType: OTPType.TOTP,
    );
    final params = parsed.queryParameters;
    return TOTP(
      secret: params['secret']!,
      digits: int.tryParse(params['digits'] ?? '') ?? 6,
      interval: int.tryParse(params['period'] ?? '') ?? 30,
      algorithm: params.containsKey('algorithm')
          ? AlgorithmUtil.parse(params['algorithm']!)
          : OTPAlgorithm.SHA1,
    );
  }

  /// Generates the TOTP for the current wall-clock time.
  String now() {
    final step = Util.timeFormat(time: DateTime.now(), interval: interval);
    return generateOTP(input: step);
  }

  /// Generates the TOTP for [date]. Returns `null` when [date] is omitted.
  String? value({DateTime? date}) {
    if (date == null) {
      return null;
    }
    final step = Util.timeFormat(time: date, interval: interval);
    return generateOTP(input: step);
  }

  /// Returns how many seconds the code for the current time step is still
  /// valid, counting from [at] (defaults to now).
  ///
  /// The result is always in the range `1..interval`, so it can drive a
  /// countdown indicator next to the displayed code:
  ///
  /// ```dart
  /// final code = totp.now();
  /// final ttl = totp.remainingSeconds(); // e.g. 17
  /// ```
  int remainingSeconds({DateTime? at}) {
    final reference = at ?? DateTime.now();
    final elapsed = (reference.millisecondsSinceEpoch ~/ 1000) % interval;
    return interval - elapsed;
  }

  /// Verifies [otp] against the TOTP computed for [time] (defaults to now).
  ///
  /// [window] accepts tokens from `time - window` to `time + window` steps to
  /// tolerate clock drift between client and server. Defaults to `0`.
  ///
  /// Uses a constant-time comparison so response timing does not leak how
  /// close a guessed code was to the expected one.
  bool verify({String? otp, DateTime? time, int window = 0}) {
    if (otp == null) {
      return false;
    }
    if (window < 0) {
      throw ArgumentError.value(window, 'window', 'must be non-negative');
    }
    final reference = time ?? DateTime.now();
    final step = Util.timeFormat(time: reference, interval: interval);
    for (var i = -window; i <= window; i++) {
      final candidate = generateOTP(input: step + i);
      if (Util.constantTimeEquals(otp, candidate)) {
        return true;
      }
    }
    return false;
  }
}
