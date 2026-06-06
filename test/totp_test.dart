import 'package:base32/base32.dart';
import 'package:dart_dash_otp/dart_dash_otp.dart';
import 'package:dart_dash_otp/src/utils/generic_util.dart';
import 'package:test/test.dart';

void main() {
  final totp = TOTP(secret: 'J22U6B3WIWRRBTAV');

  group('TOTP defaults and configuration', () {
    test('defaults are applied correctly', () {
      expect(totp.type, OTPType.TOTP);
      expect(totp.secret, 'J22U6B3WIWRRBTAV');
      expect(totp.digits, 6);
      expect(totp.interval, 30);
      expect(totp.algorithm, OTPAlgorithm.SHA1);
    });

    test('custom values are stored', () {
      final token = TOTP(
        secret: 'J22U6B3WIWRRBTAV',
        digits: 8,
        interval: 60,
        algorithm: OTPAlgorithm.SHA256,
      );
      expect(token.digits, 8);
      expect(token.interval, 60);
      expect(token.algorithm, OTPAlgorithm.SHA256);
    });

    test('rejects invalid digits, interval and secret', () {
      expect(
        () => TOTP(secret: 'J22U6B3WIWRRBTAV', digits: 5),
        throwsArgumentError,
      );
      expect(
        () => TOTP(secret: 'J22U6B3WIWRRBTAV', interval: 0),
        throwsArgumentError,
      );
      expect(() => TOTP(secret: ''), throwsArgumentError);
    });
  });

  group('TOTP generation', () {
    test('matches RFC 6238 SHA1 test vectors', () {
      // Seed "12345678901234567890" base32-encoded.
      const seed = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
      final token = TOTP(secret: seed, digits: 8);
      final vectors = <int, String>{
        59: '94287082',
        1111111109: '07081804',
        1111111111: '14050471',
        1234567890: '89005924',
        2000000000: '69279037',
      };
      vectors.forEach((seconds, expected) {
        final time =
            DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
        expect(token.value(date: time), expected,
            reason: 'time=$seconds should produce $expected');
      });
    });

    test('matches RFC 6238 SHA1 vector beyond 2^32 time steps', () {
      // Seed "12345678901234567890" base32-encoded.
      const seed = 'GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ';
      final token = TOTP(secret: seed, digits: 8);
      final time =
          DateTime.fromMillisecondsSinceEpoch(20000000000 * 1000, isUtc: true);
      // 20000000000 / 30 exceeds 2^32, exercising the 8-byte big-endian
      // counter beyond a single 32-bit word.
      expect(token.value(date: time), '65353130');
    });

    test('matches RFC 6238 Appendix B SHA256 test vectors', () {
      // RFC 6238 uses a 32-byte ASCII seed for SHA-256, Base32-encoded here
      // so the test documents exactly which key it exercises.
      final seed = base32.encodeString('12345678901234567890123456789012');
      final token =
          TOTP(secret: seed, digits: 8, algorithm: OTPAlgorithm.SHA256);
      final vectors = <int, String>{
        59: '46119246',
        1111111109: '68084774',
        1111111111: '67062674',
        1234567890: '91819424',
        2000000000: '90698825',
        20000000000: '77737706',
      };
      vectors.forEach((seconds, expected) {
        final time =
            DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
        expect(token.value(date: time), expected,
            reason: 'time=$seconds should produce $expected');
      });
    });

    test('matches RFC 6238 Appendix B SHA512 test vectors', () {
      // RFC 6238 uses a 64-byte ASCII seed for SHA-512.
      final seed = base32.encodeString(
        '1234567890123456789012345678901234567890123456789012345678901234',
      );
      final token =
          TOTP(secret: seed, digits: 8, algorithm: OTPAlgorithm.SHA512);
      final vectors = <int, String>{
        59: '90693936',
        1111111109: '25091201',
        1111111111: '99943326',
        1234567890: '93441116',
        2000000000: '38618901',
        20000000000: '47863826',
      };
      vectors.forEach((seconds, expected) {
        final time =
            DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);
        expect(token.value(date: time), expected,
            reason: 'time=$seconds should produce $expected');
      });
    });

    test('now() returns a non-null code that matches generateOTP', () {
      final nowStep =
          Util.timeFormat(time: DateTime.now(), interval: totp.interval);
      expect(totp.now(), totp.generateOTP(input: nowStep));
    });

    test('value(null) returns null', () {
      expect(totp.value(date: null), isNull);
    });

    test('generateOTP honours the algorithm argument', () {
      const secret = '3SO3CV7XVSRTLJPK';
      final token = TOTP(
        secret: secret,
        algorithm: OTPAlgorithm.SHA256,
        interval: 60,
      );
      final step = Util.timeFormat(time: DateTime.now(), interval: 60);
      expect(
        token.now(),
        token.generateOTP(input: step, algorithm: OTPAlgorithm.SHA256),
      );
    });
  });

  group('TOTP verification', () {
    test('verifies a code generated for the same time', () {
      final time = DateTime.utc(2020, 1, 1);
      final otp = totp.value(date: time);
      expect(totp.verify(otp: otp, time: time), isTrue);
    });

    test('rejects mismatched time with no tolerance', () {
      final time = DateTime.utc(2019, 1, 1);
      final otp = totp.value(date: time);
      expect(totp.verify(otp: otp), isFalse);
    });

    test('window accepts codes from neighbouring time steps', () {
      final time = DateTime.utc(2020, 1, 1);
      final otp = totp.value(date: time);
      final shifted = time.add(const Duration(seconds: 30));
      expect(totp.verify(otp: otp, time: shifted, window: 1), isTrue);
      expect(totp.verify(otp: otp, time: shifted, window: 0), isFalse);
    });

    test('rejects null otp', () {
      expect(totp.verify(otp: null), isFalse);
    });

    test('rejects negative window', () {
      expect(
        () => totp.verify(otp: '000000', window: -1),
        throwsArgumentError,
      );
    });
  });

  group('TOTP otpauth URL', () {
    test('uses the Issuer:Account label format', () {
      expect(
        totp.generateUrl(issuer: 'Sample', account: 'Account'),
        'otpauth://totp/Sample:Account?secret=J22U6B3WIWRRBTAV'
        '&issuer=Sample&digits=6&algorithm=SHA1&period=30',
      );
    });

    test('URL-encodes labels with spaces', () {
      expect(
        totp.generateUrl(issuer: 'Encoded Issuer', account: 'Account Detailed'),
        'otpauth://totp/Encoded%20Issuer:Account%20Detailed'
        '?secret=J22U6B3WIWRRBTAV&issuer=Encoded+Issuer'
        '&digits=6&algorithm=SHA1&period=30',
      );
    });

    test('reflects custom digits, algorithm and period', () {
      final token = TOTP(
        secret: 'J22U6B3WIWRRBTAV',
        digits: 8,
        interval: 60,
        algorithm: OTPAlgorithm.SHA256,
      );
      expect(
        token.generateUrl(issuer: 'More', account: 'Digits'),
        'otpauth://totp/More:Digits?secret=J22U6B3WIWRRBTAV'
        '&issuer=More&digits=8&algorithm=SHA256&period=60',
      );
    });

    test('omits the label prefix when issuer is missing', () {
      expect(
        totp.generateUrl(issuer: null, account: null),
        'otpauth://totp/?secret=J22U6B3WIWRRBTAV&issuer=&digits=6'
        '&algorithm=SHA1&period=30',
      );
      expect(
        totp.generateUrl(issuer: '', account: ''),
        'otpauth://totp/?secret=J22U6B3WIWRRBTAV&issuer=&digits=6'
        '&algorithm=SHA1&period=30',
      );
    });
  });

  group('TOTP.remainingSeconds', () {
    TOTP token({int interval = 30}) =>
        TOTP(secret: 'J22U6B3WIWRRBTAV', interval: interval);

    DateTime at(int seconds) =>
        DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);

    test('returns the full interval at the start of a step', () {
      expect(token().remainingSeconds(at: at(0)), 30);
      expect(token().remainingSeconds(at: at(30)), 30);
    });

    test('counts down within a step', () {
      expect(token().remainingSeconds(at: at(1)), 29);
      expect(token().remainingSeconds(at: at(15)), 15);
    });

    test('returns 1 on the last second of a step', () {
      expect(token().remainingSeconds(at: at(29)), 1);
      expect(token().remainingSeconds(at: at(59)), 1);
    });

    test('respects a custom interval', () {
      expect(token(interval: 60).remainingSeconds(at: at(0)), 60);
      expect(token(interval: 60).remainingSeconds(at: at(45)), 15);
      expect(token(interval: 45).remainingSeconds(at: at(44)), 1);
    });

    test('always falls within 1..interval', () {
      const interval = 30;
      final token = TOTP(secret: 'J22U6B3WIWRRBTAV', interval: interval);
      for (var s = 0; s < 120; s++) {
        final remaining = token.remainingSeconds(at: at(s));
        expect(remaining, inInclusiveRange(1, interval),
            reason: 'remainingSeconds at ${s}s was $remaining');
      }
    });

    test('defaults to the current time when "at" is omitted', () {
      expect(token().remainingSeconds(), inInclusiveRange(1, 30));
    });
  });

  group('TOTP.fromUri', () {
    test('round-trips a URL produced by generateUrl', () {
      final original = TOTP(
        secret: 'J22U6B3WIWRRBTAV',
        digits: 8,
        interval: 45,
        algorithm: OTPAlgorithm.SHA256,
      );
      final restored = TOTP
          .fromUri(original.generateUrl(issuer: 'Acme', account: 'a@b.com'));
      expect(restored.secret, original.secret);
      expect(restored.digits, original.digits);
      expect(restored.interval, original.interval);
      expect(restored.algorithm, original.algorithm);
    });

    test('applies defaults when optional parameters are absent', () {
      final restored =
          TOTP.fromUri('otpauth://totp/Label?secret=J22U6B3WIWRRBTAV');
      expect(restored.secret, 'J22U6B3WIWRRBTAV');
      expect(restored.digits, 6);
      expect(restored.interval, 30);
      expect(restored.algorithm, OTPAlgorithm.SHA1);
    });

    test('accepts a case-insensitive algorithm name', () {
      final restored = TOTP.fromUri(
        'otpauth://totp/Label?secret=J22U6B3WIWRRBTAV&algorithm=sha256',
      );
      expect(restored.algorithm, OTPAlgorithm.SHA256);
    });

    test('throws FormatException on the wrong scheme', () {
      expect(
        () => TOTP.fromUri('https://totp/Label?secret=J22U6B3WIWRRBTAV'),
        throwsFormatException,
      );
    });

    test('throws FormatException for an hotp URI', () {
      expect(
        () => TOTP.fromUri(
          'otpauth://hotp/Label?secret=J22U6B3WIWRRBTAV&counter=0',
        ),
        throwsFormatException,
      );
    });

    test('throws FormatException when the secret is missing', () {
      expect(
        () => TOTP.fromUri('otpauth://totp/Label?digits=6'),
        throwsFormatException,
      );
    });

    test('throws FormatException for an unknown algorithm', () {
      expect(
        () => TOTP.fromUri(
          'otpauth://totp/Label?secret=J22U6B3WIWRRBTAV&algorithm=MD5',
        ),
        throwsFormatException,
      );
    });

    test('throws ArgumentError for out-of-range digits', () {
      expect(
        () => TOTP.fromUri(
          'otpauth://totp/Label?secret=J22U6B3WIWRRBTAV&digits=10',
        ),
        throwsArgumentError,
      );
    });
  });
}
