import 'dart:convert';

import 'package:crypto/crypto.dart';
import 'package:dart_dash_otp/src/components/otp_algorithm.dart';
import 'package:dart_dash_otp/src/utils/algorithm_util.dart';
import 'package:test/test.dart';

void main() {
  final key = utf8.encode('sample key string');

  test('createHmacFor builds an Hmac for each supported algorithm', () {
    expect(
      AlgorithmUtil.createHmacFor(algorithm: OTPAlgorithm.SHA1, key: key)
          .toString(),
      Hmac(sha1, key).toString(),
    );
    expect(
      AlgorithmUtil.createHmacFor(algorithm: OTPAlgorithm.SHA256, key: key)
          .toString(),
      Hmac(sha256, key).toString(),
    );
    expect(
      AlgorithmUtil.createHmacFor(algorithm: OTPAlgorithm.SHA384, key: key)
          .toString(),
      Hmac(sha384, key).toString(),
    );
    expect(
      AlgorithmUtil.createHmacFor(algorithm: OTPAlgorithm.SHA512, key: key)
          .toString(),
      Hmac(sha512, key).toString(),
    );
  });

  test('rawValue returns the canonical label for each algorithm', () {
    expect(AlgorithmUtil.rawValue(algorithm: OTPAlgorithm.SHA1), 'SHA1');
    expect(AlgorithmUtil.rawValue(algorithm: OTPAlgorithm.SHA256), 'SHA256');
    expect(AlgorithmUtil.rawValue(algorithm: OTPAlgorithm.SHA384), 'SHA384');
    expect(AlgorithmUtil.rawValue(algorithm: OTPAlgorithm.SHA512), 'SHA512');
  });

  group('AlgorithmUtil.parse', () {
    test('parses every supported algorithm label', () {
      expect(AlgorithmUtil.parse('SHA1'), OTPAlgorithm.SHA1);
      expect(AlgorithmUtil.parse('SHA256'), OTPAlgorithm.SHA256);
      expect(AlgorithmUtil.parse('SHA384'), OTPAlgorithm.SHA384);
      expect(AlgorithmUtil.parse('SHA512'), OTPAlgorithm.SHA512);
    });

    test('matches case-insensitively', () {
      expect(AlgorithmUtil.parse('sha1'), OTPAlgorithm.SHA1);
      expect(AlgorithmUtil.parse('Sha256'), OTPAlgorithm.SHA256);
      expect(AlgorithmUtil.parse('sHa512'), OTPAlgorithm.SHA512);
    });

    test('throws FormatException for an unknown label', () {
      expect(() => AlgorithmUtil.parse('MD5'), throwsFormatException);
      expect(() => AlgorithmUtil.parse(''), throwsFormatException);
    });
  });
}
