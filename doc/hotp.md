# HOTP guide

HMAC-based one-time passwords ([RFC 4226](https://tools.ietf.org/html/rfc4226))
derive a code from a shared secret and an explicit, monotonically increasing
**counter**. Unlike TOTP, nothing about HOTP depends on a clock — which makes it
a good fit for hardware tokens, emailed/SMS codes, and any setting where the two
sides cannot rely on synchronised time. The price is that both sides must keep
the counter in sync.

If you want a clock-driven code that rotates on its own, you want
[TOTP](./totp.md) instead. For provisioning into an authenticator app see
[otpauth:// URIs](./otpauth-uri.md), and for window/storage trade-offs see
[Security considerations](./security-considerations.md).

## How RFC 4226 works

Given a secret key `K` and a counter `C` (an unsigned integer), HOTP is:

```
HOTP(K, C) = Truncate(HMAC-SHA-1(K, C)) mod 10^digits
```

Step by step, exactly as this package implements it in `generateOTP`:

1. **Encode the counter.** `C` is serialised to an **8-byte big-endian** byte
   string. So counter `0` becomes `00 00 00 00 00 00 00 00` and counter `1`
   becomes `00 00 00 00 00 00 00 01`.

2. **HMAC.** Compute `HMAC-SHA-1(K, C)`, a 20-byte digest `HS` (SHA-256/384/512
   produce 32/48/64 bytes; the truncation below still works because it only
   reads four bytes at a computed offset).

   ```
   HS = HMAC(K, counterBytes)   // 20 bytes for SHA-1
   ```

3. **Dynamic truncation.** Take the low 4 bits of the **last** byte of `HS` as
   an offset `0..15`:

   ```
   offset = HS[19] & 0x0f
   ```

   Read the 4 bytes starting at that offset and mask off the top bit of the
   first one (to stay positive and sign-agnostic across platforms):

   ```
   P =  (HS[offset]     & 0x7f) << 24
      | (HS[offset + 1] & 0xff) << 16
      | (HS[offset + 2] & 0xff) <<  8
      | (HS[offset + 3] & 0xff)
   ```

   `P` is a 31-bit unsigned integer.

4. **Reduce to the requested number of digits** and zero-pad:

   ```
   code = P mod 10^digits          // e.g. P mod 1000000 for 6 digits
   return code as a string, left-padded with '0' to `digits` characters
   ```

The "dynamic" in dynamic truncation is the offset: which four bytes get used
depends on the HMAC output itself, which spreads the result evenly over the
digit space. This is the heart of both HOTP and (by extension)
[TOTP](./totp.md), where the counter is replaced by a time step.

## Constructor

```dart
HOTP({
  required String secret,
  int counter = 0,
  int digits = 6,
  OTPAlgorithm algorithm = OTPAlgorithm.SHA1,
})
```

| Parameter | Type | Default | Validation |
| --- | --- | --- | --- |
| `secret` | `String` | — (required) | Base32, RFC 4648 alphabet (uppercase `A`–`Z`, digits `2`–`7`). Non-empty and must decode to **at least one byte**, otherwise `ArgumentError`. Inputs that decode to zero bytes (e.g. `"ABC"`) are rejected. |
| `counter` | `int` | `0` | Must be `>= 0`, otherwise `ArgumentError`. This is the token's initial/serialised counter. |
| `digits` | `int` | `6` | Must be `6`, `7` or `8`. Anything else throws `ArgumentError`. |
| `algorithm` | `OTPAlgorithm` | `SHA1` | One of `SHA1`, `SHA256`, `SHA384`, `SHA512`. |

```dart
import 'package:dart_dash_otp/dart_dash_otp.dart';

final hotp = HOTP(secret: 'J22U6B3WIWRRBTAV');          // counter starts at 0
final resumed = HOTP(secret: OTP.randomSecret(), counter: 42);
```

> The `counter` field is mainly the value embedded when you call
> [`generateUrl`](#generateurl). When **verifying**, you pass the expected
> counter to [`verify`](#verify) explicitly rather than mutating the instance —
> the class is immutable and does not advance the counter for you.

### Inherited members

`HOTP` extends the exported base class `OTP`, so it also exposes:

- `OTP.randomSecret({int length = 32})` — a static factory for new secrets
  (cryptographically secure, default 160 bits, minimum 80 bits). See the
  [TOTP guide](./totp.md#generating-a-secret) for the full description.
- `generateOTP({required int input, OTPAlgorithm? algorithm})` — the raw
  HMAC-and-truncate primitive described above.
- `generateUrl({String? issuer, String? account})`.
- The fields `digits`, `secret`, `algorithm` and the getter `type`
  (`OTPType.HOTP`).

## Methods

### `at`

```dart
String? at({int? counter})
```

Generates the code for a given counter, zero-padded to `digits` characters.

- When `counter` is omitted it uses the instance's own `counter`.
- **Returns `null` only for a negative `counter`.** Any non-negative counter
  yields a code.

```dart
// The RFC 4226 Appendix D seed (see the test-vector table below).
final hotp = HOTP(secret: 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ');

hotp.at(counter: 0); // '755224' — the RFC 4226 Appendix D vector
hotp.at();           // same as at(counter: 0) — uses the instance counter
hotp.at(counter: -1); // null
```

### `verify`

```dart
bool verify({String? otp, int? counter, int window = 0})
```

Re-derives the expected code(s) and compares against `otp` using a
**constant-time** comparison, so response timing does not leak how close a guess
was.

- Returns `false` (does not throw) when `otp` is `null`, when `counter` is
  `null`, or when `counter` is negative.
- `window` is a **look-ahead**: it accepts codes for `counter`, `counter + 1`,
  ..., `counter + window`. It must be `>= 0`; a negative value throws
  `ArgumentError`.

```dart
final hotp = HOTP(secret: 'J22U6B3WIWRRBTAV');
final code = hotp.at(counter: 5);

hotp.verify(otp: code, counter: 5);            // true
hotp.verify(otp: code, counter: 6);            // false (wrong counter)
hotp.verify(otp: code, counter: 3, window: 2); // true (3,4,5 all checked)
```

#### Look-ahead window semantics

HOTP drift is one-directional: the client can only get *ahead* of the server (by
generating codes the server has not yet consumed), never behind. So the window
extends forward only, unlike TOTP's symmetric window.

| `counter` | `window` | Counters checked | Codes accepted |
| --- | --- | --- | --- |
| `n` | `0` | `n` | 1 |
| `n` | `1` | `n`, `n+1` | 2 |
| `n` | `3` | `n`, `n+1`, `n+2`, `n+3` | 4 |

```
window = 0:  [ n ]
window = 1:  [ n ][ n+1 ]
window = 3:  [ n ][ n+1 ][ n+2 ][ n+3 ]
              expected  ---->  look-ahead
```

A window of `w` accepts `w + 1` codes at once, so larger windows make brute
force easier and tolerate more silent counter advances. Keep it modest — a value
around 3–10 covers the usual case of a user tapping a hardware token a few times
without submitting. See
[Security considerations](./security-considerations.md).

### `generateOTP`

```dart
String generateOTP({required int input, OTPAlgorithm? algorithm})
```

The raw RFC 4226 primitive (steps 1–4 above). For `HOTP`, `input` is the
counter. Passing `algorithm` overrides the instance algorithm for that single
call. `at` and `verify` are thin wrappers over it.

```dart
// With the RFC 4226 Appendix D seed 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ':
final hotp = HOTP(secret: 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ');
hotp.generateOTP(input: 0);                                  // '755224'
hotp.generateOTP(input: 0, algorithm: OTPAlgorithm.SHA256);  // SHA-256 variant
```

### `generateUrl`

```dart
String generateUrl({String? issuer, String? account})
```

Builds an `otpauth://hotp/...` provisioning URI. For HOTP it includes `secret`,
`issuer`, `digits`, `algorithm` and the current `counter`.

```dart
final uri = hotp.generateUrl(issuer: 'Acme Corp', account: 'jane@acme.example');
// otpauth://hotp/Acme%20Corp:jane%40acme.example?secret=J22U6B3WIWRRBTAV
//   &issuer=Acme+Corp&digits=6&algorithm=SHA1&counter=0
```

The label uses the `Issuer:Account` form when `issuer` is given and every
component is URL-encoded. Full anatomy in
[otpauth:// URIs](./otpauth-uri.md).

### `HOTP.fromUri`

```dart
factory HOTP.fromUri(String uri)
```

Parses an `otpauth://hotp/...` URI back into an `HOTP`. It reads `secret`,
`digits`, `counter` and `algorithm`, defaulting `digits` to 6 and `algorithm`
to SHA-1.

**The `counter` parameter is required for HOTP URIs** by the specification.

```dart
final hotp = HOTP.fromUri(
  'otpauth://hotp/Acme:jane@acme.example'
  '?secret=J22U6B3WIWRRBTAV&issuer=Acme&digits=6&algorithm=SHA1&counter=0',
);
```

It throws:

- `FormatException` when `uri` is not a valid `otpauth://hotp/` URI (wrong
  scheme, wrong host, missing `secret`), when the `counter` parameter is
  missing or non-numeric, or when `algorithm` names an unsupported algorithm.
- `ArgumentError` when a parameter is out of range (for example `digits=10` or a
  negative `counter`), surfaced from the `HOTP` constructor.

> As with [`TOTP.fromUri`](./totp.md#totpfromuri), the label and `issuer` are
> display metadata and are **not** stored on the returned token. Only the
> cryptographic parameters (and the counter) are recovered.

## The counter-management contract

HOTP security rests entirely on the counter. The contract:

- **The counter only ever moves forward, and each value is used once.** Never
  accept a code for a counter you have already accepted — that is the entire
  replay defence.
- **The server is the source of truth.** Store the next expected counter for
  each token. After a successful verification, advance it and persist before
  granting access.
- **The client advances when it generates.** A hardware token bumps its counter
  each time the user presses the button, whether or not the resulting code is
  ever submitted. That is how the two sides drift apart.

### What "in sync" means

Let `S` be the server's next-expected counter and `Cc` the client's current
counter.

- If `Cc == S`, they are in sync; a `window: 0` verification succeeds and the
  server advances `S` to `S + 1`.
- If `Cc > S`, the client is **ahead** (the user pressed the button a few times
  without submitting). The submitted code matches some counter `S + k` with
  `k >= 1`.
- `Cc < S` cannot legitimately happen — a smaller counter means a replayed or
  stale code, which must be rejected.

### Look-ahead resynchronisation

To recover from the client being ahead, verify with a look-ahead `window`. If
the code matches at offset `k` within the window, the user was `k` presses
ahead; resynchronise by setting the server's next-expected counter to the
matched value **plus one**.

`verify` returns only a boolean, so to learn `k` (and thus the resynchronised
counter) probe the offsets yourself with `at`:

```dart
import 'package:dart_dash_otp/dart_dash_otp.dart';

/// Verifies `code` with look-ahead and returns the resynchronised
/// next-expected counter, or null if no match within the window.
int? verifyHotpAndResync({
  required String secret,
  required String code,
  required int nextExpectedCounter, // server's stored value
  int lookAhead = 10,
}) {
  final hotp = HOTP(secret: secret);
  for (var k = 0; k <= lookAhead; k++) {
    final candidate = nextExpectedCounter + k;
    if (hotp.verify(otp: code, counter: candidate)) {
      return candidate + 1; // persist this as the new next-expected counter
    }
  }
  return null;
}
```

Pseudo-flow for a login request:

```
load token.secret and token.nextCounter from the database
resynced = verifyHotpAndResync(secret, code, token.nextCounter, lookAhead: 10)
if resynced != null:
    token.nextCounter = resynced     # persist atomically with granting access
    save token
    grant access
else:
    count a failed attempt; rate-limit / lock after N failures
    deny access
```

(`verifyHotpAndResync` above iterates `verify` per offset for clarity; a single
`hotp.verify(otp: code, counter: nextCounter, window: lookAhead)` tells you
*whether* a match exists in one call, but not the offset. Use the loop when you
need to advance the counter precisely, which you almost always do.)

Notes:

- **Persist the advanced counter atomically** with granting access (same
  transaction) so two concurrent requests with the same code cannot both
  succeed.
- **Keep the look-ahead modest** (commonly 3–10). A huge window lets a desynced
  token resync but also widens the brute-force surface and the replay risk.
- **Rate-limit.** A 6-digit code is one in a million; throttle attempts per
  token and per IP.
- **Never reuse a counter.** Even within a look-ahead match, advance past the
  matched value so the same code cannot be presented twice.

## RFC 4226 test vectors

RFC 4226 Appendix D lists the 6-digit codes for the ASCII seed
`"12345678901234567890"` (Base32 `GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ`) using
SHA-1 and the default 6 digits, for counters 0 through 9:

| Counter | Code |
| --- | --- |
| 0 | `755224` |
| 1 | `287082` |
| 2 | `359152` |
| 3 | `969429` |
| 4 | `338314` |
| 5 | `254676` |
| 6 | `287922` |
| 7 | `162583` |
| 8 | `399871` |
| 9 | `520489` |

These exact vectors are asserted in `test/hotp_test.dart`.

### Checking a vector with this package

```dart
import 'package:dart_dash_otp/dart_dash_otp.dart';

void main() {
  // ASCII "12345678901234567890" Base32-encoded.
  const seed = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
  final hotp = HOTP(secret: seed); // SHA-1, 6 digits by default

  assert(hotp.at(counter: 0) == '755224');
  assert(hotp.at(counter: 1) == '287082');
  print(hotp.at(counter: 9)); // 520489
}
```

## See also

- [Getting started](./getting-started.md) — installation and first examples.
- [TOTP guide](./totp.md) — the time-based sibling.
- [otpauth:// URIs](./otpauth-uri.md) — provisioning, QR codes, `HOTP.fromUri`.
- [Security considerations](./security-considerations.md) — windows, storage,
  rate limiting.
- [FAQ](./faq.md) — counter desync, rejected secrets, SHA-1 safety.
