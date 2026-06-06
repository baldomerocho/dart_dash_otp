# FAQ

Practical answers to the questions that come up when wiring up `dart_dash_otp`.
For background, see [Getting started](./getting-started.md), the
[TOTP](./totp.md) / [HOTP](./hotp.md) guides and
[Security considerations](./security-considerations.md).

## Why does my code differ from Google Authenticator?

When a generated code doesn't match what the user's app shows, it is almost
always one of four mismatches between the two sides:

1. **Secret.** The Base32 secret stored on the server must be byte-for-byte the
   same one the app holds. A copy/paste slip or a case change is enough to break
   it.
2. **Algorithm.** The default here is `OTPAlgorithm.SHA1`, which is what
   authenticator apps assume. If you enrolled the token with `SHA256`/`SHA512`,
   the verifier must use the same algorithm.
3. **Digits.** Default is 6. If you enrolled with `digits: 8`, both sides must
   use 8.
4. **Interval / clock (TOTP only).** Default interval is 30 seconds. If the
   device clock and server clock differ by more than one step, codes won't line
   up. Keep servers on NTP and verify with `window: 1`.

For HOTP, the equivalent of "clock" is the **counter**: the verifier's counter
must match (or be just behind, within the look-ahead `window`) the app's counter.

The reliable fix is to provision and verify with the same parameters. Building
the verifier from the provisioning URI via `TOTP.fromUri` / `HOTP.fromUri`
guarantees `secret`, `digits`, `period`/`counter` and `algorithm` agree.

## Why is SHA-1 still the default — is that safe?

Yes, in this context. The known weaknesses of SHA-1 are *collision* attacks on
the bare hash. TOTP/HOTP use SHA-1 inside **HMAC**, which depends on
pre-image/keyed security, not collision resistance; HMAC-SHA-1 remains
unbroken and is what RFC 4226 and RFC 6238 specify. It is also the only
algorithm every authenticator app is guaranteed to support.

Only switch to `SHA256`/`SHA384`/`SHA512` when the verifying side explicitly
documents support for it, because the choice must match on both ends:

```dart
final totp = TOTP(secret: secret, algorithm: OTPAlgorithm.SHA256);
```

## Can I use this on Flutter web?

Yes, but be aware of JavaScript's integer model. On the web, Dart `int` maps to a
JS `number` (an IEEE-754 double), which is only exact up to 2^53. The library
feeds the HOTP counter / TOTP time step through HMAC as a big-endian 8-byte value.
For TOTP this is a non-issue for any realistic date (time-step values stay far
below 2^53 for thousands of years), and ordinary HOTP counters are tiny. You only
risk precision loss with astronomically large HOTP counters (well beyond 2^53),
which you would never reach in practice. Standard 6/8-digit TOTP and HOTP work
correctly on Flutter web.

See [Flutter integration](./flutter-integration.md) for app-side details.

## How do I show a countdown next to a TOTP code?

Use `remainingSeconds()`. It returns how long the current code stays valid, in
the range `1..interval`:

```dart
final totp = TOTP(secret: secret);
final code = totp.now();
final secondsLeft = totp.remainingSeconds(); // e.g. 17
```

Poll it on a timer to drive a progress ring or numeric countdown, and refresh the
code when it reaches the end of the step.

## Why was my secret rejected?

The constructor validates the secret and throws `ArgumentError` unless it:

- is **non-empty**;
- decodes as **Base32** using the RFC 4648 uppercase alphabet (`A`–`Z`,
  `2`–`7`) — lowercase, padding characters, `0`, `1`, `8`, `9` and the like are
  invalid; and
- decodes to **at least one byte**.

That last rule trips people up. A string like `"ABC"` is valid Base32
*characters* but is shorter than one full Base32 group, so it decodes to **zero
bytes** — which would mean an empty (insecure) HMAC key. The library rejects it
rather than silently producing predictable codes. Use a properly sized secret,
ideally from `OTP.randomSecret()`:

```dart
final secret = OTP.randomSecret(); // 32 chars / 160 bits, always valid
```

## How do I test against the RFC test vectors?

The repository already does this. `test/hotp_test.dart` checks the
[RFC 4226 Appendix D](https://tools.ietf.org/html/rfc4226#appendix-D) vectors and
`test/totp_test.dart` checks the RFC 6238 SHA-1 vectors. Both use the standard
seed `"12345678901234567890"`, Base32-encoded as
`GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ`. A minimal HOTP check looks like:

```dart
final token = HOTP(secret: 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ');
assert(token.at(counter: 0) == '755224');
assert(token.at(counter: 1) == '287082');
```

Run the suite with `fvm dart test` (or `dart test`).

## Does `verify` protect against replay attacks?

**No, and it can't on its own.** `verify` only answers "is this code valid for
this moment / counter right now?". The same code stays valid for the rest of its
time step (TOTP) or until the counter advances (HOTP), so a captured code could
be reused. Replay protection is the caller's responsibility:

- **TOTP:** record the last time step you accepted for the user and reject a code
  from a step you've already honoured.
- **HOTP:** after a successful verify, advance and **persist** the counter so the
  old value can never match again.
- **Both:** rate-limit verification attempts to blunt brute-force guessing.

The comparison inside `verify` is constant-time, so it won't leak timing
information about how close a guess was — but that is a different protection from
replay. See [Security considerations](./security-considerations.md).

## How do I migrate from the `dart_otp` or `otp` packages?

The concepts carry over directly: you still have a Base32 secret, you still call a
"generate now" method and a verify method. Map your old calls onto this API —
`TOTP(...).now()`, `TOTP(...).verify(otp: ..., window: ...)`,
`HOTP(...).at(counter: ...)` and `HOTP(...).verify(...)`. Keep the same secret,
`digits`, interval/period and algorithm so existing enrolled tokens keep working.
If you are coming from this package's own 1.x line, follow
[Migration from 1.x](./migration-from-1x.md), which covers the renamed and
restructured members specifically.

## Where did `fromUri`'s issuer / account go?

`TOTP.fromUri` and `HOTP.fromUri` deliberately store **only the cryptographic
parameters** — `secret`, `digits`, `period`/`counter` and `algorithm`. The label
and `issuer` are display metadata, and the constructed token has no field for
them. If you need the issuer or account name (for example to show in a list of
accounts), parse the URI yourself:

```dart
final uri = Uri.parse(scannedUri);
final issuer = uri.queryParameters['issuer'];
final label = Uri.decodeComponent(uri.pathSegments.last); // "Issuer:Account"
final totp = TOTP.fromUri(scannedUri); // crypto params only
```

See [otpauth:// URIs](./otpauth-uri.md) for the label/query format.

## What does the `window` parameter actually do?

`window` widens how many codes are accepted at once, and it is a direct security
trade-off:

- **TOTP** accepts codes from `time - window` to `time + window` time steps. With
  `window: 1` and a 30-second interval, three codes are valid simultaneously
  (~90 seconds of tolerance); `window: 2` makes five codes valid, and so on.
- **HOTP** accepts codes from `counter` to `counter + window` (look-ahead only).

Each extra step of tolerance is another valid code an attacker could guess, so it
shrinks the effective key space per attempt. Keep `window` as small as your real
drift requires — `0` or `1` for TOTP is typical, a small look-ahead for HOTP.
Always pair a non-zero window with rate limiting. `window` must be non-negative;
a negative value throws `ArgumentError`.

## Why does `value()` or `at()` return `null`?

These are intentional sentinels, not errors:

- `TOTP.value(date: ...)` returns `null` when you **omit** `date`. Pass a
  `DateTime` to get a code, or use `now()` for the current time.
- `HOTP.at(counter: ...)` returns `null` for a **negative** counter. Omitting
  `counter` falls back to the instance's own value.

`verify` likewise returns `false` (rather than throwing) for a `null` `otp`, so
you can pass possibly-missing user input straight through.

## Do I need Flutter to use this package?

No. `dart_dash_otp` is pure Dart with no Flutter dependency. It works on the Dart
VM, server-side Dart, AOT-compiled CLIs and Flutter alike. The
[Flutter integration](./flutter-integration.md) page covers the Flutter-specific
bits (countdown UI, web caveats) when you do use it in an app.
