import 'package:dart_dash_otp/dart_dash_otp.dart';
import 'package:test/test.dart';

void main() {
  final hotp = HOTP(secret: 'J22U6B3WIWRRBTAV');

  group('HOTP defaults and configuration', () {
    test('defaults are applied correctly', () {
      expect(hotp.digits, 6);
      expect(hotp.counter, 0);
      expect(hotp.type, OTPType.HOTP);
      expect(hotp.secret, 'J22U6B3WIWRRBTAV');
      expect(hotp.algorithm, OTPAlgorithm.SHA1);
    });

    test('custom values are stored', () {
      final token = HOTP(
        secret: 'J22U6B3WIWRRBTAV',
        digits: 8,
        counter: 50,
        algorithm: OTPAlgorithm.SHA256,
      );
      expect(token.digits, 8);
      expect(token.counter, 50);
      expect(token.algorithm, OTPAlgorithm.SHA256);
    });

    test('rejects invalid digits, secret and counter', () {
      expect(
        () => HOTP(secret: 'J22U6B3WIWRRBTAV', digits: 5),
        throwsArgumentError,
      );
      expect(
        () => HOTP(secret: 'J22U6B3WIWRRBTAV', digits: 9),
        throwsArgumentError,
      );
      expect(() => HOTP(secret: ''), throwsArgumentError);
      expect(
        () => HOTP(secret: 'J22U6B3WIWRRBTAV', counter: -1),
        throwsArgumentError,
      );
    });
  });

  group('HOTP generation', () {
    test('matches RFC 4226 Appendix D test vectors', () {
      // Seed "12345678901234567890" base32-encoded.
      const seed = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
      final token = HOTP(secret: seed);
      const expected = [
        '755224',
        '287082',
        '359152',
        '969429',
        '338314',
        '254676',
        '287922',
        '162583',
        '399871',
        '520489',
      ];
      for (var i = 0; i < expected.length; i++) {
        expect(token.at(counter: i), expected[i],
            reason: 'counter=$i should produce ${expected[i]}');
      }
    });

    test('at(null) falls back to the instance counter', () {
      final token = HOTP(secret: 'J22U6B3WIWRRBTAV', counter: 5);
      expect(token.at(), token.at(counter: 5));
    });

    test('at() returns null for negative counters', () {
      expect(hotp.at(counter: -1), isNull);
    });

    test('generateOTP honours the algorithm argument', () {
      final h = HOTP(
        secret: '3SO3CV7XVSRTLJPK',
        algorithm: OTPAlgorithm.SHA512,
        counter: 3,
      );
      expect(
        h.at(counter: 3),
        h.generateOTP(input: 3, algorithm: OTPAlgorithm.SHA512),
      );
    });
  });

  group('HOTP verification', () {
    test('verifies a code produced for the same counter', () {
      final otp = hotp.at(counter: 0);
      expect(hotp.verify(otp: otp, counter: 0), isTrue);
      expect(hotp.verify(otp: otp, counter: 1), isFalse);
    });

    test('window accepts codes within the look-ahead range', () {
      final otp = hotp.at(counter: 12);
      expect(hotp.verify(otp: otp, counter: 10, window: 2), isTrue);
      expect(hotp.verify(otp: otp, counter: 10, window: 1), isFalse);
    });

    test('rejects missing, null or negative inputs', () {
      expect(hotp.verify(otp: null, counter: null), isFalse);
      expect(hotp.verify(otp: null, counter: 0), isFalse);
      expect(hotp.verify(otp: '', counter: 0), isFalse);
      expect(hotp.verify(otp: '000000', counter: -1), isFalse);
      expect(
        () => hotp.verify(otp: '000000', counter: 0, window: -1),
        throwsArgumentError,
      );
    });
  });

  group('HOTP otpauth URL', () {
    test('uses the Issuer:Account label format', () {
      expect(
        hotp.generateUrl(issuer: 'Sample', account: 'Account'),
        'otpauth://hotp/Sample:Account?secret=J22U6B3WIWRRBTAV'
        '&issuer=Sample&digits=6&algorithm=SHA1&counter=0',
      );
    });

    test('URL-encodes labels with spaces', () {
      expect(
        hotp.generateUrl(issuer: 'Encoded Issuer', account: 'Account Detailed'),
        'otpauth://hotp/Encoded%20Issuer:Account%20Detailed'
        '?secret=J22U6B3WIWRRBTAV&issuer=Encoded+Issuer'
        '&digits=6&algorithm=SHA1&counter=0',
      );
    });

    test('omits the label prefix when issuer is missing', () {
      expect(
        hotp.generateUrl(issuer: null, account: null),
        'otpauth://hotp/?secret=J22U6B3WIWRRBTAV&issuer=&digits=6'
        '&algorithm=SHA1&counter=0',
      );
      expect(
        hotp.generateUrl(issuer: '', account: 'Account'),
        'otpauth://hotp/Account?secret=J22U6B3WIWRRBTAV&issuer='
        '&digits=6&algorithm=SHA1&counter=0',
      );
    });

    test('reflects custom digits, algorithm and counter', () {
      final token = HOTP(
        secret: 'J22U6B3WIWRRBTAV',
        digits: 8,
        counter: 10,
        algorithm: OTPAlgorithm.SHA256,
      );
      expect(
        token.generateUrl(issuer: 'More', account: 'Digits'),
        'otpauth://hotp/More:Digits?secret=J22U6B3WIWRRBTAV'
        '&issuer=More&digits=8&algorithm=SHA256&counter=10',
      );
    });
  });

  group('HOTP.fromUri', () {
    test('round-trips a URL produced by generateUrl', () {
      final original = HOTP(
        secret: 'J22U6B3WIWRRBTAV',
        digits: 7,
        counter: 42,
        algorithm: OTPAlgorithm.SHA512,
      );
      final restored = HOTP
          .fromUri(original.generateUrl(issuer: 'Acme', account: 'a@b.com'));
      expect(restored.secret, original.secret);
      expect(restored.digits, original.digits);
      expect(restored.counter, original.counter);
      expect(restored.algorithm, original.algorithm);
    });

    test('applies defaults when optional parameters are absent', () {
      final restored = HOTP.fromUri(
        'otpauth://hotp/Label?secret=J22U6B3WIWRRBTAV&counter=0',
      );
      expect(restored.secret, 'J22U6B3WIWRRBTAV');
      expect(restored.digits, 6);
      expect(restored.counter, 0);
      expect(restored.algorithm, OTPAlgorithm.SHA1);
    });

    test('throws FormatException when the counter is missing', () {
      expect(
        () => HOTP.fromUri('otpauth://hotp/Label?secret=J22U6B3WIWRRBTAV'),
        throwsFormatException,
      );
    });

    test('throws FormatException when the counter is not numeric', () {
      expect(
        () => HOTP.fromUri(
          'otpauth://hotp/Label?secret=J22U6B3WIWRRBTAV&counter=abc',
        ),
        throwsFormatException,
      );
    });

    test('throws FormatException for a totp URI', () {
      expect(
        () => HOTP.fromUri(
          'otpauth://totp/Label?secret=J22U6B3WIWRRBTAV&counter=0',
        ),
        throwsFormatException,
      );
    });
  });
}
