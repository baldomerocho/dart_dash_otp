## [1.0.1]

* Release the first stable version

## [1.0.2]

* Add docs
* Add example file
* Fix dart format warning

## [1.0.3]

* Add documentation
* Minor code style enhancements
* Make interval and digits properties public for time based tokens

## [1.1.0]

* Add unit tests
* Update documentation
* Update components API
* Refactor some components
* Minor code style enhancements
* Increase options export option for generate url function

## [1.2.0]

* Minor enhancements
* Add new counter property inside hotp object
* Update documentation according to dart guidelines
* Add support for SHA256 algorithm (available: SHA1 and SHA256)
* Add extra url proprties to otp object in order to export:
  * Digits
  * Issuer
  * Period
  * Account
  * Counter
  * Algorithm

## [1.3.0]

* Minor enhancements
* Add support for SHA384 and SHA512 algorithm (available: SHA1, SHA256, SHA384 and SHA512)

## [1.3.1]

* Null safety

## [1.3.2]

* Fixing installation

## [1.3.3]

* Use algorithm value from constructor when generating OTP

## [1.3.4]

* Upgrade
* Update dependencies
* Update documentation

## [2.0.0]

Major rewrite. Contains breaking changes.

### Breaking changes

* Dart SDK constraint bumped to `>=3.0.0 <4.0.0`.
* `OTP.digits`, `OTP.secret` and `OTP.algorithm` are now `final`.
* `TOTP.interval` is now a non-nullable `final int`; constructors validate
  that it is positive.
* Generated `otpauth://` URLs now use the Google Authenticator
  `Issuer:Account` label format instead of just `Account`.
* All query parameters in the generated URL are URL-encoded.
* `Util.intToBytelist`'s `padding` parameter was renamed to `byteLength` and
  now produces a true big-endian byte sequence.
* `AlgorithmUtil.createHmacFor`, `AlgorithmUtil.rawValue` and
  `OTPUtil.otpTypeValue` take `required`, non-nullable parameters and return
  non-nullable values.
* Invalid arguments throw `ArgumentError` in release mode instead of silently
  passing an `assert`.

### Added

* `window` parameter on `TOTP.verify` and `HOTP.verify` to tolerate clock /
  counter drift.
* Constant-time code comparison on both verify paths.
* `OTP.randomSecret()` — cryptographically secure Base32 secret generator
  (160-bit default, RFC 4226 recommendation).
* `TOTP.fromUri` and `HOTP.fromUri` factories that parse `otpauth://` URIs
  in the Google Authenticator Key URI format.
* `TOTP.remainingSeconds()` — seconds of validity left for the current code,
  for countdown UIs.
* The shared secret is validated as Base32 at construction time; invalid or
  too-short secrets throw `ArgumentError` instead of failing later (or
  silently producing an empty HMAC key).
* The decoded secret is cached, so generating a code no longer re-decodes
  the Base32 string on every call.
* `AlgorithmUtil.parse` — case-insensitive `String` → `OTPAlgorithm`.
* The `OTP` base class is now exported (enables `OTP.randomSecret()` and
  typing variables as `OTP`).
* RFC 4226 Appendix D and RFC 6238 Appendix B test vectors (SHA-1, SHA-256
  and SHA-512).
* `analysis_options.yaml` with `package:lints/recommended.yaml`.
* pub.dev `topics` and SEO-focused package description.
* CI workflow (format, analyze, tests, coverage gate) and tag-driven
  automated publishing to pub.dev via OIDC.
* In-repo documentation under `doc/` (getting started, TOTP/HOTP deep
  dives, otpauth URI guide, security considerations, Flutter integration,
  migration and publishing guides, FAQ).

### Fixed

* `Util.timeFormat` uses integer arithmetic; no longer fails on timestamps
  that stringify to fewer than 4 characters (e.g. pre-epoch dates).
* `OTP.generateOTP` no longer relies on the null-check operator on the HMAC
  instance.

### Changed

* Dependencies refreshed: `crypto ^3.0.3`, `base32 ^2.1.3`,
  `test ^1.25.0`, added `lints ^5.0.0`.
* Removed the unmaintained `test_coverage` dev dependency.