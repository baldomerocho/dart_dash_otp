import 'package:dart_dash_otp/src/components/otp_type.dart';
import 'package:dart_dash_otp/src/utils/otp_util.dart';
import 'package:test/test.dart';

void main() {
  test('otpTypeValue maps each enum case to its canonical string', () {
    expect(OTPUtil.otpTypeValue(type: OTPType.TOTP), 'totp');
    expect(OTPUtil.otpTypeValue(type: OTPType.HOTP), 'hotp');
  });

  group('OTPUtil.parseOtpAuthUri', () {
    test('returns the parsed Uri for a valid otpauth URI', () {
      final parsed = OTPUtil.parseOtpAuthUri(
        uri: 'otpauth://totp/Label?secret=J22U6B3WIWRRBTAV&period=30',
        expectedType: OTPType.TOTP,
      );
      expect(parsed.scheme, 'otpauth');
      expect(parsed.host, 'totp');
      expect(parsed.queryParameters['secret'], 'J22U6B3WIWRRBTAV');
    });

    test('throws FormatException for a non-otpauth scheme', () {
      expect(
        () => OTPUtil.parseOtpAuthUri(
          uri: 'https://totp/Label?secret=J22U6B3WIWRRBTAV',
          expectedType: OTPType.TOTP,
        ),
        throwsFormatException,
      );
    });

    test('throws FormatException when the host does not match the type', () {
      expect(
        () => OTPUtil.parseOtpAuthUri(
          uri: 'otpauth://hotp/Label?secret=J22U6B3WIWRRBTAV&counter=0',
          expectedType: OTPType.TOTP,
        ),
        throwsFormatException,
      );
    });

    test('throws FormatException when the secret is missing or empty', () {
      expect(
        () => OTPUtil.parseOtpAuthUri(
          uri: 'otpauth://totp/Label?period=30',
          expectedType: OTPType.TOTP,
        ),
        throwsFormatException,
      );
      expect(
        () => OTPUtil.parseOtpAuthUri(
          uri: 'otpauth://totp/Label?secret=',
          expectedType: OTPType.TOTP,
        ),
        throwsFormatException,
      );
    });
  });
}
