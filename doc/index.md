# dart_dash_otp

`dart_dash_otp` generates and verifies one-time passwords for two-factor and
multi-factor authentication. It implements the two OATH standards that virtually
every authenticator app speaks:

- **HOTP** — HMAC-based one-time passwords ([RFC 4226](https://tools.ietf.org/html/rfc4226)),
  where each code advances an explicit counter.
- **TOTP** — time-based one-time passwords ([RFC 6238](https://tools.ietf.org/html/rfc6238)),
  where the code changes on a fixed time interval (the kind Google Authenticator,
  Authy, 1Password and friends show by default).

It is **pure Dart** with no Flutter dependency, so it runs on the VM, Flutter
(mobile/desktop/web), AOT-compiled CLIs and server-side Dart alike. The only
runtime dependencies are [`crypto`](https://pub.dev/packages/crypto) for HMAC and
[`base32`](https://pub.dev/packages/base32) for secret encoding.

Codes are validated against the official RFC test vectors (RFC 4226 Appendix D
and the RFC 6238 SHA-1 vectors), so output interoperates with standard
authenticator apps and verifiers.

```dart
import 'package:dart_dash_otp/dart_dash_otp.dart';

void main() {
  final totp = TOTP(secret: OTP.randomSecret());

  final code = totp.now();          // current 6-digit code
  totp.verify(otp: code, window: 1); // accept ±1 time step of drift
}
```

## Documentation

| Page | What it covers |
| --- | --- |
| [Getting started](./getting-started.md) | Installation, core concepts, TOTP/HOTP decision table, first working examples, server-side verification and common pitfalls. |
| [TOTP guide](./totp.md) | Time-based codes in depth: intervals, `now`/`value`, `remainingSeconds` for countdowns, drift windows. |
| [HOTP guide](./hotp.md) | Counter-based codes in depth: counter synchronisation, look-ahead windows, persisting the counter. |
| [otpauth:// URIs](./otpauth-uri.md) | Provisioning tokens: `generateUrl`, QR codes, and parsing scanned URIs with `TOTP.fromUri` / `HOTP.fromUri`. |
| [Security considerations](./security-considerations.md) | Secret storage, algorithm choice, replay protection, rate limiting and window trade-offs. |
| [Flutter integration](./flutter-integration.md) | Using the package in a Flutter app, including web caveats and countdown UI. |
| [Migration from 1.x](./migration-from-1x.md) | What changed in the 2.0 rewrite and how to update existing 1.x code. |
| [Publishing](./publishing.md) | How this package is released to pub.dev via the tagged publish workflow. |
| [FAQ](./faq.md) | Answers to the questions that actually come up: mismatched codes, SHA-1 safety, web int limits, rejected secrets, replay, and more. |

## Quick links

- pub.dev package: <https://pub.dev/packages/dart_dash_otp>
- API reference (dartdoc): <https://pub.dev/documentation/dart_dash_otp/latest/>
- Repository: <https://github.com/baldomerocho/dart_dash_otp>
- Issue tracker: <https://github.com/baldomerocho/dart_dash_otp/issues>

## License

MIT. See the [LICENSE](https://github.com/baldomerocho/dart_dash_otp/blob/master/LICENSE)
file in the repository.
