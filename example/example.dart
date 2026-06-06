// A guided tour of dart_dash_otp, runnable top to bottom:
//
//   dart run example/example.dart
//
// It walks through generating secrets, producing and verifying TOTP and
// HOTP codes, building and parsing otpauth:// URIs, and handling the
// errors the API throws on bad input. Each section explains the intent
// before the code so you can copy the pieces you need into a real app.

import 'package:dart_dash_otp/dart_dash_otp.dart';

void main() {
  // ==========================================================================
  // 1. Secrets
  // ==========================================================================
  // Every token is derived from a Base32-encoded shared secret. Generate it
  // once per user with OTP.randomSecret(), which uses a cryptographically
  // secure RNG. The default length of 32 characters is a 160-bit key, the
  // size RFC 4226 recommends.
  //
  // In production you persist this secret server-side (encrypted at rest) and
  // never log or hardcode it: anyone holding it can mint valid codes. The
  // fixed secret below is used only so this example prints stable output.
  final provisioningSecret = OTP.randomSecret();
  print('Section 1 - Secrets');
  print('  random secret (160-bit): $provisioningSecret');

  const demoSecret = 'J22U6B3WIWRRBTAV'; // demo only; do not reuse.
  print('');

  // ==========================================================================
  // 2. TOTP basics
  // ==========================================================================
  // A TOTP turns the secret plus the current time into a short code. Time is
  // sliced into fixed steps (interval, default 30 s); every code is valid for
  // the step it falls in. now() uses the wall clock; value(date:) computes the
  // code for any instant, which is handy for tests and reproducible examples.
  final totp = TOTP(secret: demoSecret); // SHA1, 6 digits, 30 s by default.
  final fixedInstant = DateTime.utc(2019, 1, 1);
  print('Section 2 - TOTP basics');
  print('  now():              ${totp.now()}');
  print('  value(2019-01-01):  ${totp.value(date: fixedInstant)}');
  print('');

  // ==========================================================================
  // 3. TOTP verification & the drift window
  // ==========================================================================
  // The server verifies a submitted code with verify(). By default it only
  // accepts the code for the exact current step, so a code computed one step
  // (30 s) earlier fails. Set window: 1 to also accept the neighbouring steps
  // and tolerate client/server clock drift.
  //
  // The trade-off: a larger window forgives more drift but widens the time a
  // code stays valid, so keep it as small as your clocks allow (window: 1 is
  // a common, conservative choice).
  final now = DateTime.now();
  final currentCode = totp.value(date: now)!;
  final previousStepTime = now.subtract(const Duration(seconds: 30));
  final previousCode = totp.value(date: previousStepTime)!;

  print('Section 3 - Verification');
  print('  current code verifies:       '
      '${totp.verify(otp: currentCode, time: now)}');
  print('  30s-old code, window 0:      '
      '${totp.verify(otp: previousCode, time: now)}');
  print('  30s-old code, window 1:      '
      '${totp.verify(otp: previousCode, time: now, window: 1)}');
  print('');

  // ==========================================================================
  // 4. Countdown
  // ==========================================================================
  // remainingSeconds() returns how long the current code stays valid (1..
  // interval). A UI shows it as a shrinking ring or number; when it counts
  // down to the interval again the step has rolled over, so re-read now() and
  // reset the indicator.
  print('Section 4 - Countdown');
  print('  code valid for another ${totp.remainingSeconds()}s');
  print('');

  // ==========================================================================
  // 5. Custom parameters
  // ==========================================================================
  // digits, interval and algorithm are all configurable. Both sides of the
  // exchange must agree on every parameter, otherwise the codes will never
  // match. Communicate them out of band or via the otpauth:// URI (section 6).
  final customTotp = TOTP(
    secret: demoSecret,
    digits: 8,
    interval: 60,
    algorithm: OTPAlgorithm.SHA256,
  );
  print('Section 5 - Custom parameters (8 digits / 60s / SHA256)');
  print('  now(): ${customTotp.now()}');
  print('');

  // ==========================================================================
  // 6. Provisioning URI + QR
  // ==========================================================================
  // generateUrl() produces the Google Authenticator Key URI. This is the
  // string you render as a QR code so apps like Google Authenticator, Authy
  // or 1Password can import the token by scanning it. The issuer names your
  // service and the account identifies the user (often their e-mail).
  final uri = totp.generateUrl(issuer: 'Acme', account: 'alice@example.com');
  print('Section 6 - Provisioning URI (render this as a QR code)');
  print('  $uri');
  print('');

  // ==========================================================================
  // 7. Parsing URIs
  // ==========================================================================
  // TOTP.fromUri() (and HOTP.fromUri()) does the inverse: it reads a scanned
  // otpauth:// URI back into a token, restoring secret, digits, period and
  // algorithm. Label and issuer are display metadata and are not stored.
  // Malformed input throws a FormatException (see section 9).
  final imported = TOTP.fromUri(uri);
  print('Section 7 - Parsing a URI back into a token');
  print('  imported.now() matches original.now(): '
      '${imported.now() == totp.now()}');
  print('');

  // ==========================================================================
  // 8. HOTP (counter-based)
  // ==========================================================================
  // HOTP replaces time with a counter that both parties advance in lock step.
  // at(counter:) computes the code for a specific counter. On the server,
  // verify() with a look-ahead window accepts the next few counters in case
  // the client advanced ahead (e.g. generated codes that were never sent).
  //
  // The server contract: after a successful verify(), persist the matched
  // counter + 1 as the next expected value. Never accept a counter you have
  // already used; that is what stops replay of an old code.
  final hotp = HOTP(secret: demoSecret);
  final clientCode = hotp.at(counter: 4)!; // client is two steps ahead.
  print('Section 8 - HOTP');
  print('  code at counter 0: ${hotp.at(counter: 0)}');
  print('  server expects 2, accepts counter 4 with window 3: '
      '${hotp.verify(otp: clientCode, counter: 2, window: 3)}');
  print('');

  // ==========================================================================
  // 9. Error handling
  // ==========================================================================
  // The constructors and parsers fail fast on invalid input. A non-decodable
  // secret raises ArgumentError; a URI with the wrong scheme or a missing
  // secret raises FormatException. Catch them where you accept untrusted data.
  print('Section 9 - Error handling');
  try {
    TOTP(secret: 'not valid base32!');
  } on ArgumentError catch (e) {
    print('  invalid secret -> ArgumentError: ${e.message}');
  }
  try {
    TOTP.fromUri('https://example.com/not-an-otp-uri');
  } on FormatException catch (e) {
    print('  bad URI -> FormatException: ${e.message}');
  }
}
