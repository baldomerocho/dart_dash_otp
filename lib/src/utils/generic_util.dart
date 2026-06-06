import 'dart:typed_data';

/// Internal helpers shared by the HOTP / TOTP implementations.
abstract class Util {
  /// Returns the number of [interval]-second steps elapsed since the Unix
  /// epoch for [time].
  ///
  /// Uses integer arithmetic so it works for timestamps before the epoch as
  /// well.
  static int timeFormat({required DateTime time, required int interval}) {
    if (interval <= 0) {
      throw ArgumentError.value(interval, 'interval', 'must be positive');
    }
    return time.millisecondsSinceEpoch ~/ 1000 ~/ interval;
  }

  /// Serialises [input] to a big-endian byte list of [byteLength] bytes as
  /// required by the HOTP / TOTP specification (8 bytes by default).
  static List<int> intToBytelist(int input, {int byteLength = 8}) {
    if (byteLength <= 0) {
      throw ArgumentError.value(
        byteLength,
        'byteLength',
        'must be positive',
      );
    }
    final bytes = Uint8List(byteLength);
    var value = input;
    for (var i = byteLength - 1; i >= 0; i--) {
      bytes[i] = value & 0xff;
      value >>= 8;
    }
    return bytes;
  }

  /// Compares two strings in constant time to avoid leaking how many
  /// leading characters matched through timing differences.
  ///
  /// Used by `TOTP.verify` and `HOTP.verify` so that an attacker cannot
  /// recover a valid code one character at a time by measuring response
  /// latency. Returns `false` immediately when the lengths differ, which is
  /// safe because the expected code length (`OTP.digits`) is public.
  static bool constantTimeEquals(String a, String b) {
    if (a.length != b.length) {
      return false;
    }
    var result = 0;
    for (var i = 0; i < a.length; i++) {
      result |= a.codeUnitAt(i) ^ b.codeUnitAt(i);
    }
    return result == 0;
  }
}
