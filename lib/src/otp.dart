import 'dart:math';
import 'dart:typed_data';

import 'package:base32/base32.dart';
import 'package:dart_dash_otp/src/components/otp_algorithm.dart';
import 'package:dart_dash_otp/src/components/otp_type.dart';
import 'package:dart_dash_otp/src/utils/algorithm_util.dart';
import 'package:dart_dash_otp/src/utils/generic_util.dart';
import 'package:dart_dash_otp/src/utils/otp_util.dart';

/// Base class implementing the HOTP algorithm (RFC 4226) that both
/// [counter-based](https://tools.ietf.org/html/rfc4226) and
/// [time-based](https://tools.ietf.org/html/rfc6238) one-time passwords
/// build on.
///
/// You normally instantiate one of the concrete subclasses (`TOTP` or
/// `HOTP`) instead of extending this class yourself.
abstract class OTP {
  /// The RFC 4648 Base32 alphabet used by [randomSecret].
  static const String _base32Alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ234567';

  /// The length of the one-time password, between 6 and 8.
  final int digits;

  /// The Base32-encoded shared secret used to derive the OTP.
  ///
  /// Must use the uppercase RFC 4648 alphabet (`A`–`Z`, `2`–`7`). The
  /// constructor validates that the value decodes to at least one byte and
  /// throws [ArgumentError] otherwise.
  final String secret;

  /// HMAC algorithm used when generating the OTP.
  final OTPAlgorithm algorithm;

  /// Decoded [secret], cached so [generateOTP] does not re-decode the
  /// Base32 string on every call.
  late final Uint8List _secretBytes;

  /// Token type (HOTP or TOTP).
  OTPType get type;

  /// Extra query parameters added when generating the `otpauth://` URL.
  Map<String, Object?> get extraUrlProperties;

  OTP({
    required this.secret,
    this.digits = 6,
    this.algorithm = OTPAlgorithm.SHA1,
  }) {
    if (digits < 6 || digits > 8) {
      throw ArgumentError.value(digits, 'digits', 'must be between 6 and 8');
    }
    if (secret.isEmpty) {
      throw ArgumentError.value(secret, 'secret', 'must not be empty');
    }
    Uint8List decoded;
    try {
      decoded = base32.decode(secret);
    } on FormatException {
      throw ArgumentError.value(
        secret,
        'secret',
        'must be a valid Base32 string (uppercase A-Z and digits 2-7)',
      );
    }
    if (decoded.isEmpty) {
      // Inputs shorter than one Base32 group (e.g. "ABC") silently decode
      // to zero bytes, which would produce an empty — and insecure — HMAC
      // key. Reject them explicitly.
      throw ArgumentError.value(
        secret,
        'secret',
        'is too short to decode to a Base32 key',
      );
    }
    _secretBytes = decoded;
  }

  /// Generates a cryptographically secure random Base32 secret of [length]
  /// characters, suitable for provisioning a new token.
  ///
  /// The default of 32 characters yields a 160-bit key, the length
  /// recommended by RFC 4226 section 4. [length] must be at least 16
  /// characters (80 bits), the minimum the RFC allows.
  ///
  /// Uses [Random.secure], so it throws [UnsupportedError] on platforms
  /// without a secure entropy source.
  static String randomSecret({int length = 32}) {
    if (length < 16) {
      throw ArgumentError.value(
        length,
        'length',
        'must be at least 16 characters (80 bits, the RFC 4226 minimum)',
      );
    }
    final random = Random.secure();
    final codeUnits = List<int>.generate(
      length,
      (_) => _base32Alphabet.codeUnitAt(random.nextInt(32)),
    );
    return String.fromCharCodes(codeUnits);
  }

  /// Generates an OTP for the given [input] (counter or time step).
  ///
  /// When [algorithm] is provided it overrides the one set in the
  /// constructor for this single invocation.
  String generateOTP({
    required int input,
    OTPAlgorithm? algorithm,
  }) {
    final hmac = AlgorithmUtil.createHmacFor(
      algorithm: algorithm ?? this.algorithm,
      key: _secretBytes,
    );
    final digest = hmac.convert(Util.intToBytelist(input)).bytes;
    final offset = digest[digest.length - 1] & 0xf;
    final code = ((digest[offset] & 0x7f) << 24 |
        (digest[offset + 1] & 0xff) << 16 |
        (digest[offset + 2] & 0xff) << 8 |
        (digest[offset + 3] & 0xff));
    return (code % pow(10, digits)).toInt().toString().padLeft(digits, '0');
  }

  /// Builds an `otpauth://` URL compatible with the Google Authenticator
  /// [Key URI Format](https://github.com/google/google-authenticator/wiki/Key-Uri-Format).
  ///
  /// [issuer] identifies the provider or service the account is with and
  /// [account] identifies the account itself (typically an e-mail address).
  /// When both are given the label takes the recommended `Issuer:Account`
  /// form; authenticator apps display both fields.
  String generateUrl({String? issuer, String? account}) {
    final label = _buildLabel(issuer: issuer, account: account);
    final params = <String, String>{
      'secret': secret,
      'issuer': issuer ?? '',
      'digits': digits.toString(),
      'algorithm': AlgorithmUtil.rawValue(algorithm: algorithm),
    };
    extraUrlProperties.forEach((key, value) {
      params[key] = value?.toString() ?? '';
    });
    final query = params.entries
        .map((e) =>
            '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}')
        .join('&');
    return 'otpauth://${OTPUtil.otpTypeValue(type: type)}/$label?$query';
  }

  String _buildLabel({String? issuer, String? account}) {
    final encodedAccount = Uri.encodeComponent(account ?? '');
    final trimmedIssuer = (issuer ?? '').trim();
    if (trimmedIssuer.isEmpty) {
      return encodedAccount;
    }
    return '${Uri.encodeComponent(trimmedIssuer)}:$encodedAccount';
  }
}
