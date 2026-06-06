# TOTP guide

Time-based one-time passwords ([RFC 6238](https://tools.ietf.org/html/rfc6238))
are the kind of code authenticator apps rotate every 30 seconds. This page
covers how they work, the full `TOTP` API, and how to verify them safely on a
server.

If you only want to get something working, start with
[Getting started](./getting-started.md). For provisioning a token into an app
(QR codes, `otpauth://` URIs) see [otpauth:// URIs](./otpauth-uri.md). For
storage, algorithm and window trade-offs see
[Security considerations](./security-considerations.md).

## How RFC 6238 works

TOTP is HOTP ([RFC 4226](https://tools.ietf.org/html/rfc4226)) with the counter
replaced by a number derived from the clock. Both sides hold the same shared
secret and the same notion of the current time, so they compute the same code
without ever exchanging it.

The current **time step** `T` is:

```
T = floor((currentUnixTime - T0) / period)
```

- `currentUnixTime` — seconds since the Unix epoch (1970-01-01 00:00:00 UTC).
- `T0` — the epoch the count starts from. This package uses `T0 = 0`, the RFC
  default, so the term drops out.
- `period` — the length of a time step in seconds. Here that is the `interval`
  constructor argument (default 30).

So with the defaults, `T` is simply `floor(unixSeconds / 30)`: a counter that
ticks up by one every 30 seconds. The code is then `HOTP(secret, T)` — the
RFC 4226 HMAC-and-truncate construction applied to that step. (The
[HOTP guide](./hotp.md) explains the truncation bit by bit.)

Two consequences fall straight out of this:

- A code is valid for the remainder of its time step, not a fixed number of
  seconds after you read it. A code shown at second 29 of a step expires one
  second later. `remainingSeconds()` exists precisely so you can show this.
- Client and server only agree if their clocks agree. Keep servers on NTP and
  use a `window` to tolerate small drift (see [Verifying](#verify) below).

## Constructor

```dart
TOTP({
  required String secret,
  int digits = 6,
  int interval = 30,
  OTPAlgorithm algorithm = OTPAlgorithm.SHA1,
})
```

| Parameter | Type | Default | Validation |
| --- | --- | --- | --- |
| `secret` | `String` | — (required) | Base32, RFC 4648 alphabet (uppercase `A`–`Z`, digits `2`–`7`). Must be non-empty and decode to **at least one byte**, otherwise `ArgumentError`. Inputs that decode to zero bytes (e.g. `"ABC"`) are rejected. |
| `digits` | `int` | `6` | Must be `6`, `7` or `8`. Anything else throws `ArgumentError`. |
| `interval` | `int` | `30` | The time step in seconds. Must be `> 0`, otherwise `ArgumentError`. |
| `algorithm` | `OTPAlgorithm` | `SHA1` | One of `SHA1`, `SHA256`, `SHA384`, `SHA512`. |

```dart
import 'package:dart_dash_otp/dart_dash_otp.dart';

// All defaults: 6 digits, 30-second steps, SHA-1.
final totp = TOTP(secret: 'J22U6B3WIWRRBTAV');

// Fully specified.
final custom = TOTP(
  secret: OTP.randomSecret(),
  digits: 8,
  interval: 60,
  algorithm: OTPAlgorithm.SHA256,
);
```

> Generate secrets with `OTP.randomSecret()` rather than typing them by hand;
> see [`randomSecret`](#generating-a-secret) below.

### Inherited members

`TOTP` extends the exported base class `OTP`, so it also exposes:

- `OTP.randomSecret({int length = 32})` — a static factory for new secrets.
- `generateOTP({required int input, OTPAlgorithm? algorithm})` — the raw
  HMAC-and-truncate primitive.
- `generateUrl({String? issuer, String? account})` — build an `otpauth://` URI.
- The fields `digits`, `secret`, `algorithm` and the getter `type`
  (`OTPType.TOTP` for `TOTP`).

## Generating a secret

```dart
final secret = OTP.randomSecret();          // 32 chars = 160 bits (recommended)
final shorter = OTP.randomSecret(length: 16); // 16 chars = 80 bits (RFC minimum)
```

`randomSecret` uses `Random.secure`, so the result is cryptographically secure.
The default 32 characters yields a 160-bit key, the length RFC 4226 section 4
recommends. `length` must be at least 16 (80 bits); a smaller value throws
`ArgumentError`. On a platform without a secure entropy source it throws
`UnsupportedError`.

## Methods

### `now`

```dart
String now()
```

Returns the code for the current wall-clock time, zero-padded to `digits`
characters. Always non-null.

```dart
final code = totp.now(); // e.g. '382637'
```

Internally this computes `T = floor(DateTime.now() / interval)` and calls
`generateOTP(input: T)`.

### `value`

```dart
String? value({DateTime? date})
```

Returns the code for a specific moment. **Returns `null` when `date` is
omitted** — this is intentional, so callers must be explicit about which instant
they mean.

```dart
final at59s = totp.value(
  date: DateTime.fromMillisecondsSinceEpoch(59 * 1000, isUtc: true),
);
final nothing = totp.value(); // null
```

Use `value` for deterministic tests (pin a `DateTime`) and for computing a code
for a past or future step. Use `now()` when you mean "right now".

### `remainingSeconds`

```dart
int remainingSeconds({DateTime? at})
```

Returns how many seconds the current code stays valid, counting from `at`
(defaults to now). The result is always in the range `1..interval`, which makes
it convenient for a countdown indicator.

```dart
final code = totp.now();
final ttl = totp.remainingSeconds(); // e.g. 17
print('$code (valid for ${ttl}s)');
```

It is computed as `interval - (unixSeconds % interval)`, so at the very start of
a step it returns `interval` and at the last second it returns `1`.

### `verify`

```dart
bool verify({String? otp, DateTime? time, int window = 0})
```

Re-derives the expected code(s) and compares against `otp` using a
**constant-time** comparison, so response timing does not leak how many leading
characters matched.

- Returns `false` (does not throw) when `otp` is `null`, so you can pass
  possibly-missing user input straight in.
- `time` defaults to now.
- `window` tolerates clock drift by accepting codes from `time - window` to
  `time + window` steps. It must be `>= 0`; a negative value throws
  `ArgumentError`.

```dart
// Strict: only the current step.
totp.verify(otp: userInput);

// Tolerate one step of drift in each direction.
totp.verify(otp: userInput, window: 1);

// Verify against a fixed instant (deterministic).
final t = DateTime.utc(2020, 1, 1);
final code = totp.value(date: t);
totp.verify(otp: code, time: t); // true
```

#### Window semantics

With time step `T = floor(time / interval)`, `verify` checks every step from
`T - window` through `T + window` inclusive — that is `2 * window + 1` steps.

| `window` | Steps checked | Drift tolerated each side | Codes valid at once |
| --- | --- | --- | --- |
| `0` | `T` | none | 1 |
| `1` | `T-1`, `T`, `T+1` | one step (e.g. 30 s) | 3 |
| `2` | `T-2`, `T-1`, `T`, `T+1`, `T+2` | two steps (e.g. 60 s) | 5 |

```
window = 0:                      [ T ]
window = 1:               [ T-1 ][ T ][ T+1 ]
window = 2:        [ T-2 ][ T-1 ][ T ][ T+1 ][ T+2 ]
                    earlier  <----  T  ---->  later
```

Each extra step of window roughly doubles, then triples, the count of codes an
attacker could guess at any instant, so keep it small. `window: 1` (about ±30 s
with the default interval) covers ordinary drift; if you routinely need more,
fix the clocks instead. See
[Security considerations](./security-considerations.md).

### `generateOTP`

```dart
String generateOTP({required int input, OTPAlgorithm? algorithm})
```

The raw RFC 4226 primitive: HMAC the 8-byte big-endian `input`, apply dynamic
truncation, reduce mod `10^digits`, zero-pad. For `TOTP`, `input` is the time
step `T`. Passing `algorithm` overrides the instance algorithm for that single
call.

You rarely call this directly — `now`, `value` and `verify` do. It is exposed
for test vectors and unusual flows.

```dart
final step = 1234567890 ~/ 30;       // a time step
final code = totp.generateOTP(input: step);
// Override the algorithm just for this call:
final sha256 = totp.generateOTP(input: step, algorithm: OTPAlgorithm.SHA256);
```

### `generateUrl`

```dart
String generateUrl({String? issuer, String? account})
```

Builds an `otpauth://totp/...` provisioning URI in the Google Authenticator Key
URI Format, ready to render as a QR code. For TOTP it includes `secret`,
`issuer`, `digits`, `algorithm` and `period` (the `interval`).

```dart
final uri = totp.generateUrl(issuer: 'Acme Corp', account: 'jane@acme.example');
// otpauth://totp/Acme%20Corp:jane%40acme.example?secret=J22U6B3WIWRRBTAV
//   &issuer=Acme+Corp&digits=6&algorithm=SHA1&period=30
```

The label takes the `Issuer:Account` form when `issuer` is given, and every
component is URL-encoded. The full anatomy, encoding rules and QR flow live in
[otpauth:// URIs](./otpauth-uri.md).

### `TOTP.fromUri`

```dart
factory TOTP.fromUri(String uri)
```

Parses an `otpauth://totp/...` URI (typically the result of scanning a QR code)
back into a `TOTP`. It reads `secret`, `digits`, `period` and `algorithm`,
defaulting to 6 digits, a 30-second period and SHA-1 when those parameters are
absent — matching the specification.

```dart
final totp = TOTP.fromUri(
  'otpauth://totp/Acme:jane@acme.example'
  '?secret=J22U6B3WIWRRBTAV&issuer=Acme&digits=6&algorithm=SHA1&period=30',
);
totp.verify(otp: userInput, window: 1);
```

It throws:

- `FormatException` when `uri` is not a valid `otpauth://totp/` URI (wrong
  scheme, wrong host, or a missing `secret`), or when `algorithm` names an
  algorithm the package does not support.
- `ArgumentError` when a parameter is out of range (for example `digits=10`, or
  `period=0`), surfaced from the `TOTP` constructor.

> The label and `issuer` are display metadata and are **not** stored on the
> returned token. `fromUri` recovers the cryptographic parameters, not the
> account identity. Keep the issuer/account yourself if you need them.

## Choosing interval, digits and algorithm

- **`interval` (period).** The de facto standard is **30 seconds**, and it is
  what most apps display by default. A longer interval is more forgiving of
  drift but leaves each code valid longer. Stay on 30 unless you have a specific
  reason and control both ends.
- **`digits`.** **6** is standard and universally supported; **8** gives more
  entropy per code at the cost of a longer code to type. Whatever you pick, the
  generator and verifier must agree.
- **`algorithm`.** **SHA-1** is the RFC default and the only algorithm every
  authenticator app is guaranteed to support, even though SHA-1 as a hash is
  considered weak elsewhere — in HMAC-OTP its use is not a practical weakness.
  Choose SHA-256/384/512 only when you control both the enrolling app and the
  verifier and have confirmed support. Many apps silently ignore a non-default
  `algorithm` in the URI and assume SHA-1; see
  [otpauth:// URIs](./otpauth-uri.md) for compatibility notes.

The cardinal rule: **the verifier must use the same `secret`, `digits`,
`interval` and `algorithm` as the enrolled token.** A mismatch never verifies.
When you provision via a URI, reconstruct the verifier with `TOTP.fromUri` so
those parameters travel together.

## Server-side verification recipe

`verify` checks a code; it does **not** stop replay. Within a single time step a
code can be presented more than once. To close that gap, remember the last time
step you accepted for each user and refuse to accept the same or an earlier step
again.

```dart
import 'package:dart_dash_otp/dart_dash_otp.dart';

/// Returns true if `code` is valid AND has not been used yet.
/// `lastAcceptedStep` is per-user state you persist (e.g. in your DB); pass the
/// stored value in and write the returned value back on success.
({bool ok, int lastAcceptedStep}) verifyTotpOnce({
  required String secret,
  required String code,
  required int lastAcceptedStep,
  int interval = 30,
  int window = 1,
}) {
  final totp = TOTP(secret: secret, interval: interval);
  final now = DateTime.now();
  final currentStep = now.millisecondsSinceEpoch ~/ 1000 ~/ interval;

  // 1. Constant-time check across the drift window.
  if (!totp.verify(otp: code, time: now, window: window)) {
    return (ok: false, lastAcceptedStep: lastAcceptedStep);
  }

  // 2. Replay guard: the accepted step must be strictly newer than the last
  //    one we honoured. With a window we cannot tell exactly which step matched,
  //    so require the current step to advance past the last accepted one.
  if (currentStep <= lastAcceptedStep) {
    return (ok: false, lastAcceptedStep: lastAcceptedStep);
  }

  // 3. Persist the new high-water mark, then return success.
  return (ok: true, lastAcceptedStep: currentStep);
}
```

Pseudo-flow for a login request:

```
load user.secret and user.lastAcceptedStep from the database
result = verifyTotpOnce(secret, code, user.lastAcceptedStep)
if result.ok:
    user.lastAcceptedStep = result.lastAcceptedStep   # persist!
    save user
    grant access
else:
    count a failed attempt; rate-limit / lock after N failures
    deny access
```

Notes:

- **Persist `lastAcceptedStep` atomically** with granting access (same
  transaction) so two concurrent requests with the same code cannot both win.
- **Rate-limit.** A 6-digit code is one in a million; without throttling an
  attacker can brute force it. Cap attempts per account and per IP.
- **Keep clocks honest.** Run NTP on your servers so `window: 1` is enough.

## RFC 6238 test vectors

RFC 6238 Appendix B publishes 8-digit codes for a known seed across three
algorithms. The seeds are ASCII strings; note that each algorithm uses a
different seed length:

- **SHA-1** — `"12345678901234567890"` (20 bytes), Base32
  `GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ`.
- **SHA-256** — `"12345678901234567890123456789012"` (32 bytes).
- **SHA-512** — `"1234567890123456789012345678901234567890123456789012345678901234"`
  (64 bytes).

All vectors below use `digits = 8`, `period = 30`, `T0 = 0`, and the times are
in UTC.

| Time (Unix seconds) | UTC | SHA-1 | SHA-256 | SHA-512 |
| --- | --- | --- | --- | --- |
| 59 | 1970-01-01 00:00:59 | `94287082` | `46119246` | `90693936` |
| 1111111109 | 2005-03-18 01:58:29 | `07081804` | `68084774` | `25091201` |
| 1111111111 | 2005-03-18 01:58:31 | `14050471` | `67062674` | `99943326` |
| 1234567890 | 2009-02-13 23:31:30 | `89005924` | `91819424` | `93441116` |
| 2000000000 | 2033-05-18 03:33:20 | `69279037` | `90698825` | `38618901` |
| 20000000000 | 2603-10-11 11:33:20 | `65353130` | `77737706` | `47863826` |

### Checking a vector with this package

The SHA-1 vectors are already exercised in `test/totp_test.dart`. Here is a
standalone check for the SHA-1 row at `T = 59`:

```dart
import 'package:dart_dash_otp/dart_dash_otp.dart';

void main() {
  // ASCII "12345678901234567890" Base32-encoded.
  const seed = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
  final totp = TOTP(secret: seed, digits: 8); // SHA-1, 30s by default

  final t = DateTime.fromMillisecondsSinceEpoch(59 * 1000, isUtc: true);
  assert(totp.value(date: t) == '94287082');
  print(totp.value(date: t)); // 94287082
}
```

To check the SHA-256 / SHA-512 rows, encode the 32-byte / 64-byte seeds to
Base32 and construct the token with the matching `algorithm`. For example, the
SHA-256 seed `"12345678901234567890123456789012"` Base32-encodes to
`GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQGEZA====`; building a
`TOTP(secret: that, digits: 8, algorithm: OTPAlgorithm.SHA256)` reproduces the
SHA-256 column.

## See also

- [Getting started](./getting-started.md) — installation and first examples.
- [HOTP guide](./hotp.md) — the counter-based sibling and the truncation details.
- [otpauth:// URIs](./otpauth-uri.md) — provisioning, QR codes, `fromUri`.
- [Security considerations](./security-considerations.md) — windows, storage,
  rate limiting.
- [Flutter integration](./flutter-integration.md) — countdown UI with
  `remainingSeconds`.
- [FAQ](./faq.md) — mismatched codes, SHA-1 safety, rejected secrets.
