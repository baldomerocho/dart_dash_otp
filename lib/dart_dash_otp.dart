/// Generate and verify RFC 4226 (HOTP) and RFC 6238 (TOTP) one-time
/// passwords for two-factor / multi-factor authentication flows.
///
/// ```dart
/// import 'package:dart_dash_otp/dart_dash_otp.dart';
///
/// final totp = TOTP(secret: OTP.randomSecret());
/// final code = totp.now();
/// totp.verify(otp: code, window: 1);
/// ```
///
/// See the package README and the `doc/` guides for full documentation.
library;

export 'src/components/otp_algorithm.dart';
export 'src/components/otp_type.dart';
export 'src/hotp.dart';
export 'src/otp.dart';
export 'src/totp.dart';
