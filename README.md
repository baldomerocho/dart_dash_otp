# dart_dash_otp

Pure-Dart TOTP and HOTP one-time passwords for two-factor authentication (2FA)
and multi-factor authentication (MFA). Implements [RFC 6238](https://tools.ietf.org/html/rfc6238)
(TOTP) and [RFC 4226](https://tools.ietf.org/html/rfc4226) (HOTP), generates and
parses Google Authenticator `otpauth://` URIs, and verifies codes with drift
tolerance and constant-time comparison.

[![CI](https://github.com/baldomerocho/dart_dash_otp/actions/workflows/ci.yaml/badge.svg)](https://github.com/baldomerocho/dart_dash_otp/actions/workflows/ci.yaml)
[![pub version](https://img.shields.io/pub/v/dart_dash_otp.svg)](https://pub.dev/packages/dart_dash_otp)
[![pub points](https://img.shields.io/pub/points/dart_dash_otp.svg)](https://pub.dev/packages/dart_dash_otp/score)
[![License: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](./LICENSE)

## Features

- **TOTP and HOTP** — generate and verify time-based (RFC 6238) and
  counter-based (RFC 4226) one-time passwords.
- **RFC test-vector validated** — checked against the RFC 4226 Appendix D and
  RFC 6238 reference vectors.
- **Configurable** — 6 to 8 digit codes and SHA-1 / SHA-256 / SHA-384 / SHA-512
  HMAC algorithms.
- **Drift tolerance** — a `window` parameter accepts neighbouring time steps
  (TOTP) or look-ahead counters (HOTP).
- **Constant-time verification** — code comparison runs in constant time so
  response timing does not leak how close a guess was.
- **`otpauth://` URIs** — emit (`generateUrl`) and parse (`TOTP.fromUri` /
  `HOTP.fromUri`) Google Authenticator
  [Key URI Format](https://github.com/google/google-authenticator/wiki/Key-Uri-Format)
  links, ready for QR codes.
- **Secure random secrets** — `OTP.randomSecret()` generates Base32 keys using
  `Random.secure`.
- **TOTP countdown** — `remainingSeconds()` reports how long the current code
  stays valid, for countdown UIs.
- **Pure Dart, zero Flutter dependency** — runs in Flutter apps, server-side
  Dart, and CLIs. (On the web, integers are exact only up to 2^53, so the
  astronomically large HOTP counters beyond that need a native-int target;
  ordinary counters and TOTP are unaffected.)

## Installation

Add the dependency to your `pubspec.yaml`:

```yaml
dependencies:
  dart_dash_otp: ^2.0.0
```

Then fetch it:

```bash
dart pub get
```

## Quick start

```dart
import 'package:dart_dash_otp/dart_dash_otp.dart';

void main() {
  final totp = TOTP(secret: OTP.randomSecret());

  final code = totp.now();          // current 6-digit code
  final ok = totp.verify(otp: code); // true

  print('Code $code is valid: $ok');
}
```

## Usage

### TOTP — time-based (RFC 6238)

```dart
import 'package:dart_dash_otp/dart_dash_otp.dart';

void main() {
  final totp = TOTP(secret: 'J22U6B3WIWRRBTAV');

  totp.now();                                 // current 6-digit code
  totp.value(date: DateTime.utc(2024, 1, 1)); // code for a specific instant

  // Strict verification against the current time step.
  totp.verify(otp: '123456');

  // Tolerate +/-1 time step (e.g. 30 s of clock drift) on the server.
  totp.verify(otp: '123456', window: 1);

  // Seconds the current code is still valid, for a countdown indicator.
  final ttl = totp.remainingSeconds(); // 1..interval
  print('Code expires in $ttl s');
}
```

`value()` returns `null` when `date` is omitted; pass a `DateTime` to compute a
code for a specific instant. Customise the digits, time step and algorithm:

```dart
final totp = TOTP(
  secret: 'J22U6B3WIWRRBTAV',
  digits: 8,
  interval: 60,
  algorithm: OTPAlgorithm.SHA256,
);
```

### HOTP — counter-based (RFC 4226)

```dart
import 'package:dart_dash_otp/dart_dash_otp.dart';

void main() {
  // The RFC 4226 Appendix D seed, so the codes below match the spec.
  final hotp = HOTP(secret: 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ');

  hotp.at(counter: 0);    // '755224' (RFC 4226 Appendix D vector)
  hotp.at(counter: 2019); // code for counter 2019

  // Strict verification.
  hotp.verify(otp: '755224', counter: 0);

  // Look-ahead window to tolerate a few missed client clicks.
  hotp.verify(otp: '755224', counter: 0, window: 3);
}
```

> **Persist the counter.** HOTP relies on both sides keeping the counter in
> sync. After a successful `verify`, store the next counter value
> (`matchedCounter + 1`) on the server and never accept it again — this is what
> prevents replay.

### `otpauth://` URIs

Export a token a standard authenticator app can scan:

```dart
final totp = TOTP(secret: 'J22U6B3WIWRRBTAV');
totp.generateUrl(issuer: 'Acme', account: 'alice@example.com');
// otpauth://totp/Acme:alice%40example.com?secret=J22U6B3WIWRRBTAV
//   &issuer=Acme&digits=6&algorithm=SHA1&period=30
```

When an `issuer` is provided the label takes the recommended `Issuer:Account`
form and every query parameter is URL-encoded.

Parse a scanned URI back into a token:

```dart
final totp = TOTP.fromUri(
  'otpauth://totp/Acme:alice@example.com'
  '?secret=J22U6B3WIWRRBTAV&digits=6&period=30&algorithm=SHA1',
);
totp.now();

// HOTP URIs require a numeric `counter` parameter.
final hotp = HOTP.fromUri(
  'otpauth://hotp/Acme:alice@example.com'
  '?secret=J22U6B3WIWRRBTAV&counter=0',
);
hotp.at();
```

`fromUri` reads only the `secret`, `digits`, `algorithm` and `period`/`counter`
parameters (with defaults of 6 digits, 30 s period and SHA-1). The label and
`issuer` are display metadata and are not stored on the returned token.

### Random secrets

Provision a new token with a cryptographically secure Base32 secret:

```dart
final secret = OTP.randomSecret();          // 32 chars = 160-bit key
final shortSecret = OTP.randomSecret(length: 16); // 80-bit RFC 4226 minimum

final totp = TOTP(secret: secret);
```

### Errors

Invalid construction arguments throw `ArgumentError` at runtime (not only in
debug mode):

| Source                    | Argument  | Rule                                                                 |
| ------------------------- | --------- | ------------------------------------------------------------------- |
| `TOTP` / `HOTP` / `OTP`   | `digits`  | between 6 and 8                                                      |
| `TOTP` / `HOTP` / `OTP`   | `secret`  | non-empty, valid uppercase Base32 (`A`–`Z`, `2`–`7`) that decodes to at least one byte (e.g. `"ABC"` is rejected) |
| `TOTP`                    | `interval`| positive integer                                                    |
| `HOTP`                    | `counter` | non-negative integer                                                |
| `verify`                  | `window`  | non-negative integer                                                |
| `OTP.randomSecret`        | `length`  | at least 16 characters                                              |

`TOTP.fromUri` and `HOTP.fromUri` throw `FormatException` for a wrong scheme or
host, a missing `secret`, a missing/non-numeric `counter` (HOTP), or an unknown
`algorithm`; out-of-range values such as `digits=10` still throw `ArgumentError`.

## Documentation

Detailed guides live in [`doc/`](./doc/):

| Page | Description |
| ---- | ----------- |
| [Overview](./doc/index.md) | Documentation index and where to start. |
| [Getting started](./doc/getting-started.md) | Install, first TOTP/HOTP token, and verification. |
| [TOTP guide](./doc/totp.md) | Time-based codes, intervals, drift windows, countdown. |
| [HOTP guide](./doc/hotp.md) | Counter-based codes, look-ahead, counter persistence. |
| [otpauth:// URIs](./doc/otpauth-uri.md) | Generating and parsing Key URI Format links for QR codes. |
| [Security considerations](./doc/security-considerations.md) | Secret storage, replay protection, window sizing. |
| [Flutter integration](./doc/flutter-integration.md) | Using the package in a Flutter app. |
| [Migration from 1.x](./doc/migration-from-1x.md) | Breaking changes and upgrade steps for 2.0.0. |
| [Publishing](./doc/publishing.md) | Release and tagging workflow for maintainers. |
| [FAQ](./doc/faq.md) | Common questions and gotchas. |

## Security considerations

- **Verify on the server.** Treat client-side generation as convenience only;
  the authoritative `verify` belongs on a trusted backend.
- **Store secrets carefully.** Keep shared secrets encrypted at rest and never
  expose them through logs, URLs or analytics.
- **Protect HOTP against replay.** After a match, advance and persist the
  counter so the same code can never be accepted twice.
- **Keep the window small.** A `window` of `0` or `1` is enough for normal clock
  drift; larger windows widen the brute-force surface.

See [doc/security-considerations.md](./doc/security-considerations.md) for the
full discussion.

## Migrating from 1.x

Version 2.0.0 is a major rewrite with validated inputs, `fromUri` parsing,
secure secret generation and verification windows. See
[doc/migration-from-1x.md](./doc/migration-from-1x.md) for the complete list of
breaking changes and an upgrade checklist.

## Contributing

Issues and pull requests are welcome. CI runs `dart analyze` and the full test
suite (including the RFC test vectors) on every push and pull request via the
[CI workflow](https://github.com/baldomerocho/dart_dash_otp/actions/workflows/ci.yaml).

## Release notes

See [CHANGELOG.md](./CHANGELOG.md).

## License

[MIT](./LICENSE).
