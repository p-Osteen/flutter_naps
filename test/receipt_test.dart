import 'package:flutter_test/flutter_test.dart';
import 'package:naps_flutter/naps_flutter.dart';

void main() {
  group('NapsReceipt Tests', () {
    test('parse empty receipt data', () {
      final receipt = NapsReceipt.parse('');
      expect(receipt.lines, isEmpty);
    });

    test('parse single line receipt data without terminator', () {
      // Line 1, format Simple, alignment Center, text "WELCOME"
      // Tag 030 (DP1), length 002, value "01"
      // Tag 031 (DP2), length 001, value "S"
      // Tag 032 (DP3), length 001, value "C"
      // Tag 033 (DP4), length 007, value "WELCOME"
      final raw = '03000201031001S032001C033007WELCOME';
      final receipt = NapsReceipt.parse(raw);

      expect(receipt.lines.length, 1);
      final line = receipt.lines.first;
      expect(line.lineNumber, 1);
      expect(line.format, NapsPrintFormat.simple);
      expect(line.alignment, NapsAlignment.center);
      expect(line.text, 'WELCOME');
    });

    test('parse single line with terminator', () {
      final raw = '03000201031001G032001G033004TEST?';
      final receipt = NapsReceipt.parse(raw);

      expect(receipt.lines.length, 1);
      final line = receipt.lines.first;
      expect(line.lineNumber, 1);
      expect(line.format, NapsPrintFormat.bold);
      expect(line.alignment, NapsAlignment.left);
      expect(line.text, 'TEST');
    });

    test('parse multi-line receipt', () {
      // Line 1: 01, simple, center, "CHICKEN"
      // Line 2: 02, bold, left, "TOTAL: 100"
      final raw =
          '03000201031001S032001C033007CHICKEN*03000202031001G032001G033010TOTAL: 100?';
      final receipt = NapsReceipt.parse(raw);

      expect(receipt.lines.length, 2);

      expect(receipt.lines[0].lineNumber, 1);
      expect(receipt.lines[0].format, NapsPrintFormat.simple);
      expect(receipt.lines[0].alignment, NapsAlignment.center);
      expect(receipt.lines[0].text, 'CHICKEN');

      expect(receipt.lines[1].lineNumber, 2);
      expect(receipt.lines[1].format, NapsPrintFormat.bold);
      expect(receipt.lines[1].alignment, NapsAlignment.left);
      expect(receipt.lines[1].text, 'TOTAL: 100');
    });

    test('ignores extra content after terminator', () {
      final raw =
          '03000201031001S032001C033002OK?*03000202031001S032001C033006IGNORE';
      final receipt = NapsReceipt.parse(raw);
      expect(receipt.lines.length, 1);
      expect(receipt.lines.first.text, 'OK');
    });

    test('stops at a malformed segment rather than guessing', () {
      // The parse is length-driven, so it cannot resynchronise on '*' — that
      // is the whole point: '*' occurs inside legitimate line text. A DP that
      // does not start with a DP1 sub-tag is a protocol violation, and half a
      // payment receipt is worse than none.
      final raw = 'malformed_garbage*03000201031001S032001C033002OK?';
      final receipt = NapsReceipt.parse(raw);
      expect(receipt.lines, isEmpty);
      expect(receipt.isTruncated, isTrue);
    });

    test('an asterisk inside the line text does not split the line', () {
      // A masked PAN is the common case; the old split('*') parser turned
      // this single line into five fragments and lost all of them.
      final raw = '03000201031001S032001G033019CARTE: 5321****5556?';
      final receipt = NapsReceipt.parse(raw);
      expect(receipt.lines.length, 1);
      expect(receipt.lines.first.text, 'CARTE: 5321****5556');
      expect(receipt.isTruncated, isFalse);
    });

    test('accented text is measured in characters, as the terminal counts', () {
      // Spec III.2.1: LENGTH is the number of characters. 'Opération réussie'
      // is 17 characters and 19 UTF-8 bytes, so a byte-driven reader stops two
      // short, mid-character, and loses the rest of the receipt.
      const plain = 'Conservez-moi, je peux etre';   // 27, ASCII
      const accented = 'Opération réussie';          // 17 chars / 19 bytes
      final raw =
          '03000201031001S032001G033027$plain'
          '*03000202031001S032001C033017$accented?';
      final receipt = NapsReceipt.parse(raw);
      expect(receipt.lines.length, 2);
      expect(receipt.lines[0].text, plain);
      expect(receipt.lines[1].text, accented);
      expect(receipt.isTruncated, isFalse);
    });

    test('trailing spaces in line text are preserved', () {
      // Padding is how the terminal aligns a 24-column line; trimming it
      // silently changes what gets printed.
      final raw = '03000201031001S032001G033008OK      ?';
      final receipt = NapsReceipt.parse(raw);
      expect(receipt.lines.single.text, 'OK      ');
    });
  });

  group('NapsReceipt.extractFields Tests', () {
    test('extracts Merchant ID and Terminal ID from receipt lines', () {
      final receipt = NapsReceipt([
        NapsReceiptLine(
          lineNumber: 1,
          format: NapsPrintFormat.bold,
          alignment: NapsAlignment.center,
          text: 'CHICKEN ARABIA',
        ),
        NapsReceiptLine(
          lineNumber: 2,
          format: NapsPrintFormat.simple,
          alignment: NapsAlignment.left,
          text: 'Merchant ID: 20000',
        ),
        NapsReceiptLine(
          lineNumber: 3,
          format: NapsPrintFormat.simple,
          alignment: NapsAlignment.left,
          text: 'Terminal ID: 88398363',
        ),
        NapsReceiptLine(
          lineNumber: 4,
          format: NapsPrintFormat.simple,
          alignment: NapsAlignment.left,
          text: 'STAN: 000098',
        ),
        NapsReceiptLine(
          lineNumber: 5,
          format: NapsPrintFormat.simple,
          alignment: NapsAlignment.center,
          text: 'APPROVED',
        ),
      ]);

      final fields = receipt.extractFields();

      expect(fields['merchant id'], '20000');
      expect(fields['terminal id'], '88398363');
      expect(fields['stan'], '000098');
      // Non-key:value lines are ignored
      expect(fields.containsKey('chicken arabia'), isFalse);
      expect(fields.containsKey('approved'), isFalse);
    });

    test('keys are normalised to lowercase', () {
      final receipt = NapsReceipt([
        NapsReceiptLine(
          lineNumber: 1,
          format: NapsPrintFormat.simple,
          alignment: NapsAlignment.left,
          text: 'MERCHANT ID: 12345',
        ),
        NapsReceiptLine(
          lineNumber: 2,
          format: NapsPrintFormat.simple,
          alignment: NapsAlignment.left,
          text: 'Terminal Id : 99999',
        ),
      ]);

      final fields = receipt.extractFields();

      expect(fields['merchant id'], '12345');
      expect(fields['terminal id'], '99999');
      // Original casing keys should NOT exist
      expect(fields.containsKey('MERCHANT ID'), isFalse);
      expect(fields.containsKey('Terminal Id'), isFalse);
    });

    test('returns empty map for receipt with no key:value lines', () {
      final receipt = NapsReceipt([
        NapsReceiptLine(
          lineNumber: 1,
          format: NapsPrintFormat.bold,
          alignment: NapsAlignment.center,
          text: 'APPROVED',
        ),
        NapsReceiptLine(
          lineNumber: 2,
          format: NapsPrintFormat.simple,
          alignment: NapsAlignment.center,
          text: '***',
        ),
      ]);

      final fields = receipt.extractFields();
      expect(fields, isEmpty);
    });

    test('returns empty map for empty receipt', () {
      final receipt = NapsReceipt([]);
      final fields = receipt.extractFields();
      expect(fields, isEmpty);
    });
  });
}
