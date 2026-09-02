import 'package:flutter_test/flutter_test.dart';
import 'package:naps_flutter/naps_flutter.dart';

void main() {
  group('NapsTlv Tests', () {
    test('encode single TLV element', () {
      final element = TlvElement('001', '001');
      expect(element.encode(), '001003001');
    });

    test('encode multiple TLV elements', () {
      final elements = [
        TlvElement('001', '001'),
        TlvElement('003', '1234567'),
      ];
      expect(NapsTlv.encode(elements), '0010030010030071234567');
    });

    test('decode valid TLV frame', () {
      final frame = '0010030010030071234567';
      final decoded = NapsTlv.decode(frame);
      expect(decoded.length, 2);
      expect(decoded[0].tag, '001');
      expect(decoded[0].value, '001');
      expect(decoded[1].tag, '003');
      expect(decoded[1].value, '1234567');
    });

    test('decode empty frame', () {
      expect(NapsTlv.decode(''), isEmpty);
    });

    test('decode malformed frame throws FormatException', () {
      expect(() => NapsTlv.decode('001'), throwsFormatException);
      expect(() => NapsTlv.decode('001abc001'), throwsFormatException);
      expect(() => NapsTlv.decode('001005abc'), throwsFormatException);
    });
  });
}
