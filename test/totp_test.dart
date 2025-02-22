import 'package:dart_dash_otp/dart_dash_otp.dart';
import 'package:dart_dash_otp/src/utils/generic_util.dart';
import 'package:test/test.dart';

void main() {
  var totp = TOTP(secret: "J22U6B3WIWRRBTAV");

  test('[TOTP] Should check the token with default digits and interval', () {
    expect(totp.type, OTPType.TOTP);
    expect(totp.secret, "J22U6B3WIWRRBTAV");
    expect(totp.digits, 6);
    expect(totp.interval, 30);
    expect(totp.algorithm, OTPAlgorithm.SHA1);
  });

  test('[TOTP] Should check the token with custom digits, interval and algorithm', () {
    var token = TOTP(
      secret: "J22U6B3WIWRRBTAV",
      digits: 8,
      interval: 60,
      algorithm: OTPAlgorithm.SHA256,
    );

    expect(token.type, OTPType.TOTP);
    expect(token.secret, "J22U6B3WIWRRBTAV");
    expect(token.digits, 8);
    expect(token.interval, 60);
    expect(token.algorithm, OTPAlgorithm.SHA256);
  });

  test('[TOTP] Should generate the token using current time', () {
    expect(totp.now(), isNotNull);
  });

  test('[TOTP] Should generate the token using the given algorithm', () {
    final secret = '3SO3CV7XVSRTLJPK';
    TOTP t = TOTP(
      secret: secret,
      algorithm: OTPAlgorithm.SHA256,
      interval: 60,
    );
    final totpNow = t.now();
    final totpGenerated = t.generateOTP(
      algorithm: OTPAlgorithm.SHA256,
      input: Util.timeFormat(
        time: DateTime.now(),
        interval: 60,
      ),
    );
    expect(totpNow, totpGenerated);
  });

  test('[TOTP] Should generate and verify using a specific date time', () {
    var time = DateTime.now();
    var otpValue = totp.value(date: time);

    expect(totp.verify(otp: otpValue, time: time), true);
  });

  test('[TOTP] Should generate, verify hard coded date time and compare to current time (should be false)', () {
    var time = DateTime.parse('2019-01-01 00:00:00.000');
    var otpValue = totp.value(date: time);

    expect(otpValue, '734632');
    expect(totp.verify(otp: otpValue), false);
    expect(totp.verify(otp: otpValue, time: time), true);
  });

  test('[HOTP] Should generate token urls', () {
    expect(totp.generateUrl(issuer: "Sample", account: "Account"),
        "otpauth://totp/Account?secret=J22U6B3WIWRRBTAV&issuer=Sample&digits=6&algorithm=SHA1&period=30");
    expect(
      totp.generateUrl(issuer: "Encoded Issuer", account: "Account Detailed"),
      "otpauth://totp/Account%20Detailed?secret=J22U6B3WIWRRBTAV&issuer=Encoded+Issuer&digits=6&algorithm=SHA1&period=30",
    );
  });

  test('[HOTP] Should generate token urls with a custom token', () {
    var token = TOTP(
      secret: "J22U6B3WIWRRBTAV",
      digits: 8,
      interval: 60,
      algorithm: OTPAlgorithm.SHA256,
    );
    expect(
      token.generateUrl(issuer: "More", account: "Digits"),
      "otpauth://totp/Digits?secret=J22U6B3WIWRRBTAV&issuer=More&digits=8&algorithm=SHA256&period=60",
    );
  });

  test('[TOTP] Fail Conditions: Validations', () {
    expect(totp.value(date: null), null);
    expect(totp.verify(otp: null, time: null), false);
    expect(totp.verify(otp: null, time: DateTime.now()), false);
  });

  test('[TOTP] Fail Conditions: Generate Url', () {
    expect(totp.generateUrl(issuer: null, account: null),
        "otpauth://totp/?secret=J22U6B3WIWRRBTAV&issuer=&digits=6&algorithm=SHA1&period=30");
    expect(totp.generateUrl(issuer: null, account: ""),
        "otpauth://totp/?secret=J22U6B3WIWRRBTAV&issuer=&digits=6&algorithm=SHA1&period=30");
    expect(totp.generateUrl(issuer: "", account: null),
        "otpauth://totp/?secret=J22U6B3WIWRRBTAV&issuer=&digits=6&algorithm=SHA1&period=30");
  });
}
