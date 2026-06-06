import 'package:dart_dash_otp/src/utils/generic_util.dart';
import 'package:test/test.dart';

void main() {
  group('Util.timeFormat', () {
    test('returns 30-second step for UTC reference time', () {
      final time = DateTime.utc(2019, 1, 1);
      expect(Util.timeFormat(time: time, interval: 30), 51543360);
    });

    test('returns 60-second step for UTC reference time', () {
      final time = DateTime.utc(2019, 1, 1);
      expect(Util.timeFormat(time: time, interval: 60), 25771680);
    });

    test('throws when interval is not positive', () {
      expect(
        () => Util.timeFormat(time: DateTime.utc(2019), interval: 0),
        throwsArgumentError,
      );
      expect(
        () => Util.timeFormat(time: DateTime.utc(2019), interval: -5),
        throwsArgumentError,
      );
    });
  });

  group('Util.intToBytelist', () {
    test('returns a big-endian 8-byte representation by default', () {
      expect(
        Util.intToBytelist(1),
        [0, 0, 0, 0, 0, 0, 0, 1],
      );
      expect(
        Util.intToBytelist(0x0102030405060708),
        [0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08],
      );
    });

    test('respects custom byteLength and pads with zeros', () {
      expect(Util.intToBytelist(1, byteLength: 4), [0, 0, 0, 1]);
      expect(Util.intToBytelist(0, byteLength: 8), [0, 0, 0, 0, 0, 0, 0, 0]);
    });

    test('throws when byteLength is not positive', () {
      expect(
        () => Util.intToBytelist(1, byteLength: 0),
        throwsArgumentError,
      );
    });
  });

  group('Util.constantTimeEquals', () {
    test('returns true for equal strings', () {
      expect(Util.constantTimeEquals('123456', '123456'), isTrue);
    });

    test('returns false for different strings of the same length', () {
      expect(Util.constantTimeEquals('123456', '123457'), isFalse);
      // A difference in the first character must be caught too.
      expect(Util.constantTimeEquals('023456', '123456'), isFalse);
    });

    test('returns false for strings of different length', () {
      expect(Util.constantTimeEquals('12345', '123456'), isFalse);
      expect(Util.constantTimeEquals('123456', '12345'), isFalse);
    });

    test('returns true for two empty strings', () {
      expect(Util.constantTimeEquals('', ''), isTrue);
    });
  });
}
