# otpauth:// URIs

Authenticator apps are provisioned with a token by scanning a QR code that
encodes an `otpauth://` URI — the Google Authenticator
[Key URI Format](https://github.com/google/google-authenticator/wiki/Key-Uri-Format).
This package both builds these URIs (`generateUrl`) and parses them
(`TOTP.fromUri` / `HOTP.fromUri`).

This page covers the URI anatomy, how the package generates and parses it, the
end-to-end QR provisioning flow, and the compatibility gotchas worth knowing
before you ship.

## Anatomy of the URI

```
otpauth://TYPE/LABEL?PARAMETERS
```

```
otpauth://totp/Acme%20Corp:jane%40acme.example?secret=J22U6B3WIWRRBTAV&issuer=Acme+Corp&digits=6&algorithm=SHA1&period=30
\______/   \__/ \____________________________/ \_____________________________________________________________________/
 scheme    type           label                                      parameters (query string)
```

- **scheme** — always `otpauth`.
- **type** — `totp` or `hotp`. (Internally this is the URI *host*; the package
  validates it against the token type.)
- **label** — a display string identifying the account. By convention
  `Issuer:Account`, both URL-encoded. The label is for humans; the cryptographic
  parameters live in the query string.
- **parameters** — a URL-encoded query string carrying the secret and settings.

### Parameter reference

| Parameter | TOTP | HOTP | Meaning |
| --- | --- | --- | --- |
| `secret` | required | required | Base32 shared secret (RFC 4648 alphabet). |
| `issuer` | recommended | recommended | Provider/service name, shown by the app and used to namespace the account. |
| `algorithm` | optional | optional | `SHA1` (default), `SHA256`, `SHA384` or `SHA512`. |
| `digits` | optional | optional | `6` (default), `7` or `8`. |
| `period` | optional | n/a | TOTP time step in seconds (default `30`). |
| `counter` | n/a | **required** | HOTP initial counter. Mandatory for `hotp` URIs. |

"Optional" means the spec assigns a default when the parameter is absent
(`SHA1`, `6`, `30`). This package always *emits* `secret`, `issuer`, `digits`
and `algorithm`, plus `period` (TOTP) or `counter` (HOTP). When *parsing*, it
applies the defaults for any it does not find — except `counter`, which is
required for HOTP and raises an error if missing.

## How `generateUrl` builds the URI

```dart
String generateUrl({String? issuer, String? account})
```

`generateUrl` is defined on the base `OTP` class, so it is identical for `TOTP`
and `HOTP` except for the type segment and the trailing `period` / `counter`
parameter.

```dart
import 'package:dart_dash_otp/dart_dash_otp.dart';

final totp = TOTP(secret: 'J22U6B3WIWRRBTAV');
final uri = totp.generateUrl(issuer: 'Acme Corp', account: 'jane@acme.example');
// otpauth://totp/Acme%20Corp:jane%40acme.example?secret=J22U6B3WIWRRBTAV
//   &issuer=Acme+Corp&digits=6&algorithm=SHA1&period=30

final hotp = HOTP(secret: 'J22U6B3WIWRRBTAV', counter: 0);
final hUri = hotp.generateUrl(issuer: 'Acme Corp', account: 'jane@acme.example');
// otpauth://hotp/Acme%20Corp:jane%40acme.example?secret=J22U6B3WIWRRBTAV
//   &issuer=Acme+Corp&digits=6&algorithm=SHA1&counter=0
```

### The label

- When `issuer` is non-empty (after trimming), the label is
  `Issuer:Account` — the recommended form; apps display both fields.
- When `issuer` is null or empty, the label is just the encoded `account` (no
  leading colon).
- Both `issuer` and `account` are percent-encoded in the label. Note this uses
  path-style encoding, so a space becomes `%20` (for example `Acme Corp` →
  `Acme%20Corp`).

| `issuer` | `account` | Resulting label |
| --- | --- | --- |
| `'Acme Corp'` | `'jane@acme.example'` | `Acme%20Corp:jane%40acme.example` |
| `null` / `''` | `'jane@acme.example'` | `jane%40acme.example` |
| `null` / `''` | `null` / `''` | *(empty)* |

### The query string

Every parameter value is URL-encoded as a query component. Query-component
encoding differs from path encoding: a space becomes `+` (for example the
`issuer` value `Acme Corp` → `Acme+Corp`), while `@` becomes `%40`. So the same
issuer text appears as `Acme%20Corp` in the label and `Acme+Corp` in the
`issuer` query parameter — both decode back to `Acme Corp`. The parameter order
the package emits is `secret`, `issuer`, `digits`, `algorithm`, then `period`
(TOTP) or `counter` (HOTP).

The `digits`, `algorithm` and `period`/`counter` values reflect the token's
configuration, so a token built with `digits: 8` and `OTPAlgorithm.SHA256`
serialises those into the URI.

> If `issuer` is omitted the URI still contains `issuer=` (empty). Supplying a
> real issuer is strongly recommended so the account is namespaced in the app.

## How `TOTP.fromUri` / `HOTP.fromUri` parse the URI

The two factories reverse the process, typically on a string obtained from a
scanned QR code.

```dart
final totp = TOTP.fromUri(
  'otpauth://totp/Acme:jane@acme.example'
  '?secret=J22U6B3WIWRRBTAV&issuer=Acme&digits=6&algorithm=SHA1&period=30',
);

final hotp = HOTP.fromUri(
  'otpauth://hotp/Acme:jane@acme.example'
  '?secret=J22U6B3WIWRRBTAV&issuer=Acme&digits=6&algorithm=SHA1&counter=0',
);
```

### Defaults applied when parsing

| Missing parameter | TOTP default | HOTP default |
| --- | --- | --- |
| `digits` | `6` | `6` |
| `algorithm` | `SHA1` | `SHA1` |
| `period` | `30` | n/a |
| `counter` | n/a | **none — required** |

### Errors thrown

Both factories share the same validation for scheme/host/secret and then add
type-specific rules:

- **`FormatException`** when:
  - the scheme is not `otpauth`;
  - the host does not match the type (`totp` for `TOTP.fromUri`, `hotp` for
    `HOTP.fromUri`);
  - the `secret` parameter is missing or empty;
  - `algorithm` names an algorithm the package does not support;
  - (HOTP only) the `counter` parameter is missing or non-numeric.
- **`ArgumentError`** when a parameter is out of range — for example `digits=10`,
  `period=0`, a non-Base32 `secret`, or a negative `counter` — surfaced from the
  underlying constructor.

### Metadata is not stored

> `fromUri` recovers the **cryptographic parameters** (`secret`, `digits`,
> `algorithm`, `period`/`counter`) — not the account identity. The **label and
> `issuer` are not stored** on the returned token. If you need to display the
> issuer or account later, keep them yourself alongside the token.

## QR-code provisioning flow, end to end

The whole point of the URI is enrolment: the server creates a token, shows it as
a QR code, the user scans it, and the first verified code proves the enrolment
worked.

1. **Generate a fresh secret** (server side). Use `OTP.randomSecret()` — never a
   hand-typed string.

   ```dart
   final secret = OTP.randomSecret(); // 160-bit, cryptographically secure
   ```

2. **Persist the secret** against the user account (encrypted at rest). For HOTP,
   also store the initial counter. See
   [Security considerations](./security-considerations.md).

3. **Build the provisioning URI.**

   ```dart
   final totp = TOTP(secret: secret);
   final uri = totp.generateUrl(
     issuer: 'Acme Corp',
     account: 'jane@acme.example',
   );
   ```

4. **Render the URI as a QR code** for the user to scan. This package does not
   draw QR codes (it is pure Dart with no UI dependency). In Flutter, feed `uri`
   to [`qr_flutter`](https://pub.dev/packages/qr_flutter):

   ```dart
   // Flutter only — requires the qr_flutter package.
   // import 'package:qr_flutter/qr_flutter.dart';
   QrImageView(data: uri, size: 220);
   ```

   See [Flutter integration](./flutter-integration.md) for a complete widget,
   including offering the secret as copyable text for users who cannot scan.

5. **The user scans the QR** with their authenticator app (Google Authenticator,
   Authy, 1Password, ...). The app decodes the URI, stores the secret, and
   starts showing codes.

6. **Confirm enrolment by verifying the first code.** Ask the user to type the
   code their app now shows and verify it before you mark 2FA as enabled. This
   catches clock skew (TOTP) or a botched scan early.

   ```dart
   // Server side, after the user submits the code from their app:
   final ok = totp.verify(otp: userEnteredCode, window: 1);
   if (ok) {
     // mark the account as 2FA-enabled and persist
   }
   ```

For HOTP the same flow applies, but step 3 uses `HOTP(...).generateUrl(...)`
(which embeds `counter`), and step 6 verifies with a look-ahead window and
advances the stored counter on success — see the
[HOTP guide](./hotp.md#the-counter-management-contract).

### Parsing a scanned URI on your own client

If your own app scans the QR (rather than a third-party authenticator), turn the
scanned string straight into a token:

```dart
final token = TOTP.fromUri(scannedString); // or HOTP.fromUri(...)
final code = token.now();                   // TOTP
```

Because `fromUri` carries `digits`, `algorithm` and `period`/`counter`, the
reconstructed token uses the same settings as the one that generated the URI —
which is exactly what you need so the codes match.

## Compatibility notes

The Key URI Format is widely implemented but unevenly. The most important
caveat:

> **Some authenticator apps ignore `algorithm`, `digits` and `period`.** Google
> Authenticator in particular has historically ignored these and assumed the
> defaults (SHA-1, 6 digits, 30 seconds). If you provision a token with, say,
> `digits=8` or `algorithm=SHA256`, such an app will happily import it but then
> generate **default** codes that never verify against your non-default
> configuration.

Practical guidance:

- **For maximum compatibility, stick to the defaults**: SHA-1, 6 digits, and a
  30-second period for TOTP. The vast majority of deployments use exactly these.
- If you must use non-default parameters, **verify that every app your users
  rely on honours them** before rolling out, and prefer apps known to respect
  the full URI.
- **Always confirm enrolment with a live code** (flow step 6). It is the only
  reliable way to detect a parameter the user's app silently ignored.
- **Include an `issuer`.** Apps use it to group and label accounts, and some
  also cross-check it against the label; omitting it leads to confusing,
  unnamespaced entries.
- **`secret` casing matters.** Keep secrets uppercase Base32 (the package
  emits and requires this). Some apps tolerate lowercase, but the spec and this
  package do not.

## See also

- [Getting started](./getting-started.md) — provisioning in context.
- [TOTP guide](./totp.md#totpfromuri) — `TOTP.fromUri` specifics.
- [HOTP guide](./hotp.md#hotpfromuri) — `HOTP.fromUri` and the required counter.
- [Flutter integration](./flutter-integration.md) — rendering and scanning QR
  codes with `qr_flutter`.
- [Security considerations](./security-considerations.md) — secret storage and
  algorithm choice.
- [FAQ](./faq.md) — why a scanned token produces non-matching codes.
