# Security considerations

`dart_dash_otp` implements the cryptographic core of HOTP (RFC 4226) and TOTP
(RFC 6238): deriving a code from a shared secret and verifying a submitted code
in constant time. Everything *around* that core — where secrets live, how they
are provisioned, how many guesses an attacker gets — is the responsibility of
the application using the library. This page covers those responsibilities and
the trade-offs involved.

If you only read one thing: **a one-time password is only as strong as the
secrecy of its shared key and the discipline of its verifier.** The algorithm
is the easy part.

See also [Getting started](./getting-started.md), the [TOTP guide](./totp.md),
the [HOTP guide](./hotp.md) and the [FAQ](./faq.md).

## What this library does and does not do

It is worth being explicit, because mistaking the boundary here is the most
common way to ship an insecure 2FA flow.

The library **does**:

- Derive RFC-compliant HOTP/TOTP codes from a Base32 secret.
- Generate cryptographically secure random secrets (`OTP.randomSecret`, backed
  by `Random.secure`).
- Compare a submitted code against expected codes in **constant time**
  (`TOTP.verify` / `HOTP.verify`), so verification latency does not leak how
  many characters matched.
- Validate construction inputs and throw `ArgumentError` on bad values.

The library **does not**:

- **Store secrets.** There is no persistence layer. You decide where the secret
  is written and how it is protected.
- **Rate-limit or throttle.** `verify` will happily answer a million calls a
  second. Throttling and lockout are yours to implement (see
  [Verification hygiene](#verification-hygiene)).
- **Track replay.** `verify` is stateless. It does not remember which time step
  or counter you already accepted. Replay protection is yours to implement (see
  [Replay protection](#replay-protection)).
- **Bind a code to a session, device or user.** Associating a verified code
  with the right account and a single login attempt is application logic.

Treat the four items in the second list as a checklist. A correct call to
`verify` with none of them in place is not meaningfully secure.

## Secret generation and entropy

The secret is the entire security of the scheme. If it is guessable, the codes
are guessable.

- **Use a CSPRNG.** Generate secrets with `OTP.randomSecret`, which draws from
  `Random.secure` (the platform's cryptographic entropy source). Never derive a
  secret from a username, e-mail, timestamp, `Random()` (the non-secure PRNG),
  `DateTime.now()`, or any other low-entropy or predictable input.
- **Use enough bits.** RFC 4226 §4 requires a shared secret of at least 128
  bits and **recommends 160 bits**. The default `OTP.randomSecret()` returns a
  32-character Base32 string, which decodes to 160 bits — the recommended size.
  The function rejects any `length` below 16 characters (80 bits, the absolute
  RFC minimum) with an `ArgumentError`.

```dart
import 'package:dart_dash_otp/dart_dash_otp.dart';

// 160-bit secret (recommended).
final secret = OTP.randomSecret();

// 256-bit secret, if your verifier and authenticator app support it.
final strongSecret = OTP.randomSecret(length: 52);

final totp = TOTP(secret: secret);
```

`OTP.randomSecret` throws `UnsupportedError` on the rare platform without a
secure entropy source. Do not catch that and fall back to `Random()` — fail
the enrollment instead.

## Secret storage

A leaked secret database is a leaked set of every user's second factor. Protect
it accordingly.

**On the server (the verifier):**

- Store secrets **encrypted at rest**. Use envelope encryption with a key held
  in a KMS / HSM rather than a column you can read with a plain `SELECT`. The
  threat you are defending against is a database dump, which encryption-at-rest
  alone (full-disk) does not stop.
- **Never log the secret.** Not in application logs, not in request traces, not
  in crash reports, not in analytics. The Base32 secret and the generated
  `otpauth://` URL (which *contains* the secret) must be excluded from every
  logging and observability pipeline.
- Restrict read access to the verification service only. Application code that
  merely *displays* account settings has no reason to read the secret.

**On a mobile authenticator app (the holder):**

Store the secret in the platform's hardware-backed secure storage, never in
plain `SharedPreferences` / `NSUserDefaults` or an unencrypted file:

- iOS: the **Keychain**.
- Android: the **Keystore** (e.g. `EncryptedSharedPreferences`).
- A common cross-platform wrapper is the `flutter_secure_storage` package, which
  uses Keychain on iOS and Keystore-backed encryption on Android.

These are named here only as the correct storage targets; `dart_dash_otp`
itself has no dependency on any of them. See
[Flutter integration](./flutter-integration.md) for a storage sketch.

## Provisioning and transport

The window during which a secret travels from server to authenticator is the
window in which it can be intercepted.

- **Provision over TLS only.** The `otpauth://` URL and the bare secret must
  only ever cross the network over an authenticated TLS connection. Never send a
  secret over plain HTTP, e-mail, SMS or a chat message.
- **Render QR codes on a trusted display.** A QR code encodes the secret in the
  clear. Show it only to an authenticated user on a device they control, and do
  not persist screenshots of it. Treat a displayed enrollment QR like a
  displayed password.
- **Show each secret once.** After the user confirms enrollment by submitting a
  valid first code, stop offering the secret/QR for redisplay. If they need to
  re-enroll, issue a *new* secret.
- **Confirm before trusting.** Require the user to enter one valid code before
  marking the factor as active. This proves the secret was transported intact
  and the clocks are roughly aligned (TOTP).

See [otpauth:// URIs](./otpauth-uri.md) for how to build and parse provisioning
URLs.

## Verification hygiene

This is where most of the real-world security lives, and most of it is your
code, not the library's.

- **Verify on the server, never on the client.** The secret lives on the
  server; the client sends only the 6–8 digit code. A client-side check can be
  bypassed by anyone who controls the client. The only exception is an
  authenticator app, which by design holds the secret to *generate* codes — it
  is not the verifier.
- **Constant-time comparison is already built in.** `TOTP.verify` and
  `HOTP.verify` compare the submitted code against expected codes with a
  constant-time equality check, so an attacker cannot recover a code one digit
  at a time by measuring response latency. Do not reimplement verification with
  `submitted == expected`, which is a timing oracle — call `verify`.
- **Throttle and lock out.** RFC 4226 §7.3 explicitly requires the verifier to
  limit the number of attempts. A 6-digit code has only 1,000,000 possible
  values; without throttling, an attacker can brute-force it (see
  [Brute-force math](#brute-force-math)). Enforce a small number of attempts per
  time window, add increasing delays, and lock the account (or require a step-up
  challenge) after `N` consecutive failures. Count failures per account, not
  just per IP, so an attacker cannot dodge the limit by rotating addresses.
- **Fail closed.** If your throttling store is unavailable, deny the
  verification rather than letting attempts through unmetered.
- **Keep `window` small.** Every extra step in the window is extra codes an
  attacker can hit (see [Window trade-offs](#window-trade-offs)).

## Replay protection

`verify` is stateless: it tells you whether a code is valid *right now*, not
whether it has already been used. A valid TOTP code is valid for the whole time
step (plus the window), so without replay protection an attacker who observes
one code can reuse it within that span. You must record what you have accepted.

**TOTP — persist the last accepted time step.**

After a successful `verify`, record the time step that matched and reject any
later submission for that step or an earlier one. Re-derive the step with the
same interval the token uses:

```dart
import 'package:dart_dash_otp/dart_dash_otp.dart';
import 'package:dart_dash_otp/src/utils/generic_util.dart'; // internal helper

bool verifyOnce(TOTP totp, String code, {required int lastAcceptedStep}) {
  if (!totp.verify(otp: code, window: 1)) {
    return false;
  }
  final step = Util.timeFormat(time: DateTime.now(), interval: totp.interval);
  if (step <= lastAcceptedStep) {
    return false; // already used this step (or an older one) — replay.
  }
  // Persist `step` as the new lastAcceptedStep for this user, then accept.
  return true;
}
```

`Util.timeFormat` is an internal helper and not part of the exported API; it is
imported here through the `src/` path. If you would rather not depend on an
internal, compute the step yourself:
`DateTime.now().millisecondsSinceEpoch ~/ 1000 ~/ totp.interval`.

**HOTP — require a strictly increasing counter.**

HOTP has no time component; replay protection *is* the counter. After a
successful `verify` with a look-ahead window, advance the stored counter to
**one past** the matched value, and reject any future code that does not
re-synchronise to a strictly greater counter. Never accept the same counter
twice.

```dart
int? resyncCounter(HOTP hotp, String code, {required int storedCounter}) {
  const lookAhead = 3;
  for (var c = storedCounter; c <= storedCounter + lookAhead; c++) {
    if (hotp.verify(otp: code, counter: c)) {
      return c + 1; // persist this as the new storedCounter.
    }
  }
  return null; // no match within look-ahead — reject.
}
```

## Window trade-offs

The `window` parameter on `verify` exists to tolerate drift: clock skew for
TOTP, missed button presses for HOTP. It does so by accepting more than one
code, which directly enlarges the attack surface.

- **TOTP:** `window: w` accepts steps `now - w` through `now + w`, i.e.
  `2w + 1` codes are valid at once. `window: 0` accepts one code; `window: 1`
  accepts three. Each `+1` to the window roughly multiplies the number of
  simultaneously valid codes and lengthens the span during which an observed
  code can be replayed. **Recommend `window <= 1`** (one step of slack in each
  direction); rely on NTP-synchronised clocks rather than a wide window.
- **HOTP:** the window is a forward-only look-ahead (`counter` through
  `counter + window`). Keep it **small** — enough to cover a few accidental
  presses, not so large that an attacker gets dozens of valid candidates.
  Combine it with strict counter advancement (see
  [Replay protection](#replay-protection)).

A wide window is not a substitute for synchronising clocks or for the user
generating a fresh code.

## Algorithm choice and SHA-1

The default HMAC algorithm is SHA-1, and that is fine.

- The well-known SHA-1 attacks are **collision** attacks on the bare hash. HOTP
  and TOTP use SHA-1 inside **HMAC**, whose security does not rely on the
  underlying hash being collision-resistant. There is no known attack that
  breaks HMAC-SHA-1 as used here, and RFC 6238 continues to specify it as the
  default.
- SHA-1 is also the only algorithm **every** authenticator app is guaranteed to
  accept. Many do not implement SHA-256/384/512.
- If your verifier and the target app both document support for it, you may use
  `OTPAlgorithm.SHA256` (or 384/512) for defence in depth. Set it on the token
  and advertise it in the `otpauth://` URL so the app matches:

```dart
final totp = TOTP(
  secret: OTP.randomSecret(),
  algorithm: OTPAlgorithm.SHA256,
);
```

Choosing a SHA-2 variant is a compatibility decision, not a fix for a real
SHA-1-in-HMAC weakness.

## Brute-force math

The numbers are what justify throttling.

- A 6-digit code has `10^6 = 1,000,000` possible values; 7 digits is
  `10,000,000`; 8 digits is `100,000,000`.
- With **no throttling**, an attacker guessing a single 6-digit code expects
  success after about `500,000` attempts and is guaranteed within `1,000,000`.
  A widened `window` makes this easier still: `window: 1` (three valid TOTP
  codes) cuts the expected attempts to roughly a third.
- With throttling — say, lockout after 5 failures — the attacker's success
  probability per lockout window is about `5 / 1,000,000`, i.e. one in 200,000.
  This is the entire point of RFC 4226 §7.3.

The takeaway is not "use more digits" (8 digits buys you ~100× but hurts
usability); it is **throttle aggressively**. Throttling, not code length, is
what makes online guessing infeasible.

## Backup and recovery codes

If a user loses the device holding their secret, they are locked out. Provide a
recovery path, but treat it with the same care as the secret itself, because it
is an equally powerful authenticator.

- Issue a small set of **single-use** backup codes at enrollment.
- Generate them from a CSPRNG (you can use `OTP.randomSecret` to source
  high-entropy strings, or any secure random generator).
- **Hash them before storing**, exactly as you would a password (a slow,
  salted hash). Never store backup codes in plaintext.
- **Show each once**, mark it used on redemption, and let the user regenerate
  the whole set (invalidating the old ones).
- Apply the same throttling and lockout to backup-code entry as to OTP entry.

Do not use backup codes to "remember" a device indefinitely; a recovery
mechanism that never expires is a permanent bypass of the second factor.

## Quick checklist

- [ ] Secrets generated with `OTP.randomSecret` (>= 160 bits).
- [ ] Secrets encrypted at rest on the server; in Keychain/Keystore on device.
- [ ] Secrets and `otpauth://` URLs excluded from all logs.
- [ ] Provisioning only over TLS; QR shown once on a trusted display.
- [ ] Verification happens server-side via `verify` (constant-time built in).
- [ ] Attempts throttled; account locked after `N` failures (RFC 4226 §7.3).
- [ ] Replay blocked: TOTP last-step persisted; HOTP counter strictly advances.
- [ ] `window <= 1` for TOTP; small look-ahead for HOTP.
- [ ] Backup codes are single-use and stored hashed.

Continue to [Flutter integration](./flutter-integration.md) for client-side
patterns, or back to the [index](./index.md).
