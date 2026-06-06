# Flutter integration

`dart_dash_otp` is **pure Dart with no Flutter dependency**, so it runs
unchanged inside a Flutter app on Android, iOS, desktop and web. It has no
widgets of its own — it gives you codes and URLs, and you build the UI.

This page covers the two app shapes that use the library:

1. An app that **adds 2FA to its own accounts** (the server owns the secret; the
   app just shows the enrollment QR and confirms the first code).
2. An **authenticator-style app** (the app holds secrets and continuously
   displays codes with a countdown, like Google Authenticator).

Then it covers storing secrets, web platform caveats, and testing.

> **About the example dependencies.** The snippets below use `qr_flutter`,
> `mobile_scanner` and `flutter_secure_storage`. These are **optional, third-party
> packages** shown for illustration only — `dart_dash_otp` does not depend on
> any of them. Add whichever you actually need to your own `pubspec.yaml`. The
> only line that is always required is:
>
> ```yaml
> dependencies:
>   dart_dash_otp: ^2.0.0
> ```

See also [Getting started](./getting-started.md),
[otpauth:// URIs](./otpauth-uri.md) and, importantly,
[Security considerations](./security-considerations.md) — most of the rules
there apply directly to client code.

## Use case 1: adding 2FA to your own app

Here your **server** is the verifier. The secret is generated and stored on the
server; the Flutter app only displays the enrollment QR and sends the user's
first code back for confirmation. The app should **not** keep the secret.

The flow:

1. The server calls `OTP.randomSecret()`, stores it (encrypted, see the
   security guide), and returns the `otpauth://` URL to the app over TLS.
2. The app renders that URL as a QR code for the user to scan into their
   authenticator app.
3. The user enters the first code their authenticator shows; the app sends it to
   the server, which calls `TOTP.verify` and marks the factor active on success.

### Rendering the enrollment QR (`qr_flutter`)

> Optional dependency: `qr_flutter: ^4`.

In production the `otpauth://` URL comes from the server. To make the snippet
self-contained, this widget builds it locally — in a real app you would receive
`provisioningUri` from your API and pass it straight to `QrImageView`.

```dart
import 'package:flutter/material.dart';
import 'package:qr_flutter/qr_flutter.dart'; // optional example dependency
import 'package:dart_dash_otp/dart_dash_otp.dart';

class EnrollmentQr extends StatelessWidget {
  const EnrollmentQr({super.key, required this.provisioningUri});

  /// The otpauth:// URL returned by your server over TLS.
  final String provisioningUri;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Text('Scan this with your authenticator app'),
        const SizedBox(height: 16),
        QrImageView(
          data: provisioningUri,
          size: 220,
        ),
      ],
    );
  }
}
```

If you are prototyping without a backend, you can build the URL on the client
with `generateUrl` — but remember that doing so means the secret lived on the
device, which is not how a production enrollment should work:

```dart
final totp = TOTP(secret: OTP.randomSecret());
final uri = totp.generateUrl(issuer: 'Acme', account: 'alice@example.com');
// Pass `uri` to QrImageView(data: uri).
```

### Confirming the first code

The text field collects the code; verification belongs on the server. The
client call is shown here only to make the example runnable.

```dart
// Server-side, with the stored TOTP for this user:
final ok = totp.verify(otp: enteredCode, window: 1);
if (ok) {
  // Mark the second factor as confirmed/active for the account.
}
```

Use `window: 1` so a small clock difference between the user's phone and your
server does not reject a correct code. See
[Window trade-offs](./security-considerations.md#window-trade-offs).

## Use case 2: building an authenticator app

Here the **app is the holder**. It scans a QR from some *other* service, stores
the secret, and continuously shows the current code with a countdown ring.

### Parsing a scanned QR (`mobile_scanner` + `TOTP.fromUri`)

> Optional dependency: `mobile_scanner: ^5`.

A scanner gives you the raw string content of the QR — an `otpauth://totp/...`
URL. Hand it to `TOTP.fromUri`, which reads the secret, digits, period and
algorithm. It throws `FormatException` for a non-`otpauth` URL or a missing
secret, and `ArgumentError` for out-of-range values, so guard the call.

```dart
import 'package:mobile_scanner/mobile_scanner.dart'; // optional example dependency
import 'package:dart_dash_otp/dart_dash_otp.dart';

TOTP? parseScannedToken(String rawQrText) {
  try {
    return TOTP.fromUri(rawQrText);
  } on FormatException {
    return null; // not an otpauth://totp/ URI, or no secret.
  } on ArgumentError {
    return null; // e.g. digits out of the 6..8 range.
  }
}

// Wire it into the scanner:
//
// MobileScanner(
//   onDetect: (capture) {
//     final raw = capture.barcodes.first.rawValue;
//     if (raw == null) return;
//     final token = parseScannedToken(raw);
//     if (token != null) {
//       // store token's secret, add it to the list, etc.
//     }
//   },
// );
```

`TOTP.fromUri` does **not** keep the label or issuer from the URI — those are
display metadata only. If you want to show "Acme / alice@example.com" next to
the code, parse them yourself from the URL and store them alongside the token.
For HOTP, use `HOTP.fromUri`, which additionally requires a numeric `counter`
parameter. See [otpauth:// URIs](./otpauth-uri.md).

### Displaying a code with a live countdown

`TOTP.now()` gives the current code and `TOTP.remainingSeconds()` gives how many
seconds it stays valid (always `1..interval`), which is exactly what a countdown
needs. Drive a one-second `Timer` and rebuild:

```dart
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:dart_dash_otp/dart_dash_otp.dart';

class TokenTile extends StatefulWidget {
  const TokenTile({super.key, required this.totp, required this.label});

  final TOTP totp;
  final String label;

  @override
  State<TokenTile> createState() => _TokenTileState();
}

class _TokenTileState extends State<TokenTile> {
  late Timer _timer;
  late String _code;
  late int _remaining;

  @override
  void initState() {
    super.initState();
    _refresh();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  void _refresh() {
    setState(() {
      _code = widget.totp.now();
      _remaining = widget.totp.remainingSeconds();
    });
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(widget.label),
      subtitle: Text(
        _code.replaceAllMapped(
          RegExp(r'(\d{3})(\d{3})'),
          (m) => '${m[1]} ${m[2]}',
        ),
        style: const TextStyle(fontFeatures: [FontFeature.tabularFigures()]),
      ),
      trailing: SizedBox(
        width: 36,
        height: 36,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CircularProgressIndicator(
              value: _remaining / widget.totp.interval,
            ),
            Text('$_remaining'),
          ],
        ),
      ),
    );
  }
}
```

`_code` only actually changes once per time step, but recomputing every second
is cheap (one HMAC) and keeps the code and the countdown in lock-step without
extra bookkeeping. If you prefer a stream-driven version, a
`StreamBuilder<int>` over `Stream.periodic(const Duration(seconds: 1), ...)`
that reads `now()`/`remainingSeconds()` in its `builder` works identically.

### Storing secrets (`flutter_secure_storage`)

> Optional dependency: `flutter_secure_storage: ^9`.

Secrets must go in hardware-backed secure storage — Keychain on iOS, Keystore
on Android — never in `SharedPreferences` or a plain file. A thin wrapper:

```dart
import 'package:flutter_secure_storage/flutter_secure_storage.dart'; // optional
import 'package:dart_dash_otp/dart_dash_otp.dart';

class TokenStore {
  const TokenStore(this._storage);

  final FlutterSecureStorage _storage;

  Future<void> save(String id, TOTP token) {
    // Persist only the secret (plus any display label you keep separately).
    return _storage.write(key: 'totp_$id', value: token.secret);
  }

  Future<TOTP?> load(String id) async {
    final secret = await _storage.read(key: 'totp_$id');
    if (secret == null) return null;
    return TOTP(secret: secret);
  }
}
```

Persist the `secret` string (and your own label/issuer if you kept them), then
reconstruct the `TOTP`/`HOTP` on load. For HOTP, you must also persist and
reload the **counter**, and advance it on every use — see
[Replay protection](./security-considerations.md#replay-protection). Do not
serialise the whole object; just the fields you need to rebuild it.

## Platform notes

The library is platform-agnostic, with one caveat that only matters on **Flutter
web**.

- On web, Dart `int` is a JavaScript number (an IEEE-754 double), so integers
  are only exact up to `2^53`.
- **Timestamps are fine.** A TOTP time step is `epochSeconds ~/ interval`, which
  stays well under `2^53` until roughly the year 287396. TOTP on web has no
  practical limit.
- **Very large HOTP counters are not.** An HOTP counter above `2^53`
  (~9 quadrillion) can no longer be represented exactly on web and would produce
  wrong codes. This is purely theoretical for normal use — counters increment by
  one per code — but if you somehow have astronomically large counters, do not
  rely on them on web.
- On **all native platforms** (Android, iOS, desktop, Dart VM, AOT), `int` is a
  true 64-bit integer and none of this applies.

## Testing widget code deterministically

Code that depends on the wall clock is hard to test. The library lets you inject
the time so widget and unit tests are deterministic — no clock mocking required.

- `TOTP.value(date: ...)` returns the code for a specific instant.
- `TOTP.verify(time: ...)` verifies against a specific instant.
- `HOTP.at(counter: ...)` / `HOTP.verify(counter: ...)` take an explicit
  counter, which is already deterministic.

```dart
import 'package:test/test.dart';
import 'package:dart_dash_otp/dart_dash_otp.dart';

void main() {
  test('code is stable for a fixed instant', () {
    final totp = TOTP(secret: 'J22U6B3WIWRRBTAV');
    final at = DateTime.utc(2024, 1, 1, 0, 0, 0);

    final code = totp.value(date: at);

    expect(code, isNotNull);
    expect(totp.verify(otp: code!, time: at), isTrue);
  });
}
```

In a `flutter_test` widget test, build your `TokenTile` (or equivalent) with a
`TOTP` whose code you derived via `value(date:)`, pump the widget, and assert the
text matches — instead of waiting on a real `Timer`. Inject the same fixed
`DateTime` your widget reads so the rendered code is predictable.

## Where to go next

- [Security considerations](./security-considerations.md) — storage, throttling,
  replay; read this before shipping.
- [otpauth:// URIs](./otpauth-uri.md) — building and parsing provisioning URLs.
- [TOTP guide](./totp.md) and [HOTP guide](./hotp.md) — the APIs in depth.
- Back to the [index](./index.md).
