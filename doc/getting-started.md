# Getting started

This page takes you from an empty project to generating and verifying real
one-time passwords. If you have used a 1.x release, read
[Migration from 1.x](./migration-from-1x.md) first — the API changed.

## Installation

Add the dependency to your `pubspec.yaml`:

```yaml
dependencies:
  dart_dash_otp: ^2.0.0
```

Then fetch it:

```sh
# Dart projects
dart pub get

# Flutter projects (this also edits pubspec.yaml for you)
flutter pub add dart_dash_otp
```

Import the single public entry point everywhere you use the package:

```dart
import 'package:dart_dash_otp/dart_dash_otp.dart';
```

That export gives you `OTP`, `TOTP`, `HOTP`, `OTPAlgorithm` and `OTPType`.

## Core concepts

### The shared secret

Both algorithms rely on a **shared secret**: a random key that the server and
the user's authenticator app each hold a copy of. Neither side ever sends the
secret over the wire after provisioning — instead, both derive the same short
numeric code from it. The server generates the secret once, shows it to the user
(usually as a QR code), and stores it.

Keep that secret confidential. Anyone who has it can generate valid codes
forever. See [Security considerations](./security-considerations.md) for storage
guidance.

### Base32

Secrets in this ecosystem are **Base32-encoded** using the RFC 4648 alphabet:
uppercase `A`–`Z` and the digits `2`–`7`. That is what authenticator apps expect
in a QR code, and it is what this package accepts.

The constructor validates the secret strictly. It must be non-empty, decode as
Base32, and decode to **at least one byte**. A surprising consequence: very short
strings such as `"ABC"` decode to zero bytes and are rejected — see the
[FAQ](./faq.md#why-was-my-secret-rejected) for the details. Lowercase secrets are
also rejected; uppercase them first.

Don't invent secrets by hand. Use `OTP.randomSecret()` (covered below).

### TOTP vs HOTP — which one?

| | TOTP (time-based) | HOTP (counter-based) |
| --- | --- | --- |
| RFC | 6238 | 4226 |
| What advances the code | Wall-clock time, every `interval` seconds (default 30) | An explicit `counter` that both sides increment |
| Server keeps in sync via | A reasonably accurate clock | Persisting the last accepted counter |
| Code lifetime | A few seconds (one time step) | Until used / counter advances |
| Typical use | App-based 2FA (Google Authenticator, Authy, ...) | Hardware tokens, SMS/email codes, offline scenarios |
| Main risk to manage | Clock drift between client and server | Counter getting out of sync |

**Rule of thumb:** if you want the familiar "code that rotates every 30 seconds"
experience, choose TOTP. Choose HOTP when there is no reliable shared clock, or
when you control a counter on both ends (for example a hardware key or an
emailed code). When in doubt, use TOTP.

Each type has a dedicated guide: [TOTP](./totp.md) and [HOTP](./hotp.md).

## Your first TOTP, line by line

```dart
import 'package:dart_dash_otp/dart_dash_otp.dart';

void main() {
  // 1. Construct a TOTP from a Base32 secret. digits, interval and algorithm
  //    all have sensible defaults (6 digits, 30 seconds, SHA-1).
  final totp = TOTP(secret: 'J22U6B3WIWRRBTAV');

  // 2. now() returns the code for the current wall-clock time as a String,
  //    zero-padded to `digits` characters.
  final code = totp.now(); // e.g. '382637'
  print('Current code: $code');

  // 3. remainingSeconds() tells you how long that code stays valid, from 1 up
  //    to `interval`. Handy for a countdown next to the code.
  print('Valid for ${totp.remainingSeconds()} more seconds');

  // 4. verify() re-derives the code and compares in constant time. With the
  //    same secret and clock, the code you just produced verifies as true.
  print('Verifies: ${totp.verify(otp: code)}'); // true
}
```

A few details worth knowing:

- `now()` always returns a non-null `String`. If you need the code for a
  specific moment instead, use `value(date: someDateTime)` — note that
  `value()` returns `null` when you omit the `date` argument.
- `verify()` returns `false` (it does not throw) when `otp` is `null`, so you can
  pass a possibly-missing user input straight in.

## Your first HOTP

HOTP is counter-driven. Both the generator and the verifier must agree on the
counter value.

```dart
import 'package:dart_dash_otp/dart_dash_otp.dart';

void main() {
  // The RFC 4226 Appendix D seed, so counter 0 produces the spec's '755224'.
  final hotp = HOTP(secret: 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ'); // counter starts at 0

  // at() generates the code for a specific counter. It returns null only for
  // negative counters; omit `counter` to use the instance's own value.
  final code = hotp.at(counter: 0); // '755224' for this RFC seed
  print('Code for counter 0: $code');

  // Verify against the same counter.
  print(hotp.verify(otp: code, counter: 0)); // true

  // After a successful login, advance and persist the counter on the server so
  // the same code cannot be replayed.
}
```

See the [HOTP guide](./hotp.md) for counter persistence and look-ahead windows.

## Validating user-entered codes (server side)

In a real login flow the server holds the secret, the user types the code their
app shows, and you verify it. Allow a small tolerance for clock drift (TOTP) or
counter drift (HOTP) with the `window` argument.

```dart
// TOTP: window: 1 accepts the previous, current and next 30-second step.
bool checkTotp(String storedSecret, String userInput) {
  final totp = TOTP(secret: storedSecret);
  return totp.verify(otp: userInput, window: 1);
}

// HOTP: window is a look-ahead from `counter` to `counter + window`.
bool checkHotp(String storedSecret, int expectedCounter, String userInput) {
  final hotp = HOTP(secret: storedSecret);
  return hotp.verify(otp: userInput, counter: expectedCounter, window: 1);
}
```

`window` must be non-negative; a negative value throws `ArgumentError`. Larger
windows are more forgiving but weaken security, because more codes are valid at
once — see [Security considerations](./security-considerations.md) and the
[FAQ](./faq.md#what-does-the-window-parameter-actually-do).

> **Important:** `verify` does **not** prevent replay on its own. For TOTP,
> remember the last time step you accepted and reject a repeat; for HOTP,
> persist the advanced counter after each success. Rate-limit attempts in both
> cases.

## Generating a secret and provisioning it

When a user enrols in 2FA, generate a fresh secret with `OTP.randomSecret()` and
hand it to their authenticator app via an `otpauth://` URI (typically rendered as
a QR code).

```dart
import 'package:dart_dash_otp/dart_dash_otp.dart';

void main() {
  // Cryptographically secure (Random.secure). Default length 32 = 160 bits,
  // the RFC 4226 recommendation. Minimum length is 16 (80 bits).
  final secret = OTP.randomSecret();

  // Store `secret` against the user account, then build the provisioning URI.
  final totp = TOTP(secret: secret);
  final uri = totp.generateUrl(issuer: 'Acme Corp', account: 'jane@acme.example');

  // Render `uri` as a QR code for the user to scan, or show it as a string.
  print(uri);
  // otpauth://totp/Acme%20Corp:jane%40acme.example?secret=...&issuer=Acme+Corp&digits=6&algorithm=SHA1&period=30
}
```

Full details — label format, URL-encoding, QR rendering and parsing scanned
codes with `TOTP.fromUri` / `HOTP.fromUri` — live in
[otpauth:// URIs](./otpauth-uri.md).

## Common pitfalls

- **Clock skew (TOTP).** If the server clock and the user's device clock differ
  by more than a time step, codes won't match. Keep servers on NTP and verify
  with `window: 1` to tolerate up to one step of drift in each direction.
- **Lowercase or non-Base32 secrets are rejected.** The secret must be uppercase
  RFC 4648 Base32 (`A`–`Z`, `2`–`7`). Passing lowercase, padding, or other
  characters throws `ArgumentError`. Uppercase the value before constructing the
  token.
- **Secrets that are too short are rejected.** Strings that decode to zero bytes
  (such as `"ABC"`) throw `ArgumentError`. Prefer `OTP.randomSecret()`; its
  minimum length already satisfies the RFC.
- **Storing the secret.** Treat it like a password-equivalent credential.
  Encrypt it at rest and never log it. Anyone with the secret can mint valid
  codes. See [Security considerations](./security-considerations.md).
- **Digits / interval / algorithm mismatch between generator and verifier.** The
  verifier must use the *same* `digits`, `interval` (TOTP) and `algorithm` as the
  enrolled token. A token enrolled with 8 digits or SHA-256 will never verify
  against a default 6-digit SHA-1 `TOTP`. When provisioning via a URI, build the
  verifier with `TOTP.fromUri` / `HOTP.fromUri` so those parameters travel
  together — but note the label and issuer are *not* stored, only the
  cryptographic parameters.

## Next steps

- [TOTP guide](./totp.md) and [HOTP guide](./hotp.md) for the full surface of each type.
- [otpauth:// URIs](./otpauth-uri.md) for provisioning and parsing.
- [Security considerations](./security-considerations.md) before you ship.
- [FAQ](./faq.md) for the questions that come up in practice.
