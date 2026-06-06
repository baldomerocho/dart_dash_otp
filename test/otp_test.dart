import 'package:base32/base32.dart';
import 'package:dart_dash_otp/dart_dash_otp.dart';
import 'package:test/test.dart';

void main() {
  group('OTP.randomSecret', () {
    test('defaults to 32 characters (160 bits)', () {
      expect(OTP.randomSecret().length, 32);
    });

    test('honours a custom length', () {
      expect(OTP.randomSecret(length: 16).length, 16);
      expect(OTP.randomSecret(length: 48).length, 48);
    });

    test('only emits uppercase Base32 characters [A-Z2-7]', () {
      final secret = OTP.randomSecret(length: 64);
      expect(RegExp(r'^[A-Z2-7]+$').hasMatch(secret), isTrue,
          reason: 'unexpected characters in "$secret"');
    });

    test('two calls produce different secrets', () {
      // A collision between two 160-bit random strings is astronomically
      // unlikely, so an equal pair signals a broken entropy source.
      expect(OTP.randomSecret(), isNot(OTP.randomSecret()));
    });

    test('throws when length is below the 16-character minimum', () {
      expect(() => OTP.randomSecret(length: 15), throwsArgumentError);
      expect(() => OTP.randomSecret(length: 0), throwsArgumentError);
    });

    test('produces a secret accepted by the TOTP constructor', () {
      final secret = OTP.randomSecret();
      final totp = TOTP(secret: secret);
      expect(totp.secret, secret);
      // It must also yield a usable code rather than throwing.
      expect(totp.now(), hasLength(6));
    });
  });

  group('OTP secret validation', () {
    test('rejects a lowercase secret', () {
      expect(() => TOTP(secret: 'j22u6b3wiwrrbtav'), throwsArgumentError);
    });

    test('rejects secrets with characters outside the Base32 alphabet', () {
      // '0', '1', '8' and '9' are not part of RFC 4648 Base32.
      expect(() => TOTP(secret: '11111111'), throwsArgumentError);
      expect(() => TOTP(secret: 'ABCD0189'), throwsArgumentError);
    });

    test('rejects "ABC" because it decodes to zero bytes', () {
      // Inputs shorter than one Base32 group decode to an empty key.
      expect(base32.decode('ABC'), isEmpty);
      expect(() => TOTP(secret: 'ABC'), throwsArgumentError);
    });

    test('accepts a padded secret that the base32 package can decode', () {
      // base32.encodeString('a') yields a padded single-byte secret. The
      // base32 package accepts the '=' padding, so the constructor must too.
      const padded = 'ME======';
      expect(base32.decode(padded), [97]);
      final totp = TOTP(secret: padded);
      expect(totp.secret, padded);
    });
  });
}
