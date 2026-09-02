import 'package:flutter_test/flutter_test.dart';
import 'package:naps_flutter/naps_flutter.dart';

void main() {
  group('NapsMessage Tests', () {
    test('validation throws FormatException if mandatory tags are missing', () {
      final message = NapsMessage({});
      expect(() => message.toFrame(), throwsFormatException);
    });

    test('paymentRequest builds and serializes correctly', () {
      final timestamp = DateTime(2026, 7, 14, 12, 34, 56);
      final msg = NapsMessage.paymentRequest(
        amountInCents: 200,
        posId: '1234567',
        sequenceNumber: 159159,
        currencyCode: '504',
        timestamp: timestamp,
      );

      expect(msg.messageType, '001');
      expect(msg.amountInCents, 200);
      expect(msg.posId, '1234567');
      expect(msg.sequenceNumber, 159159);
      expect(msg.currencyCode, '504');
      expect(msg.dateStr, '14072026');
      expect(msg.timeStr, '123456');

      // Stricter MD compliance checks for padding and lengths
      expect(msg.elements['001']?.value.length, 3, reason: 'TM must be 3 chars');
      expect(msg.elements['002']?.value.length, 12, reason: 'MT (Amount) must be 12 chars');
      expect(msg.elements['003']?.value.length, 7, reason: 'NCAI (POS ID) must be 7 chars');
      expect(msg.elements['004']?.value.length, 6, reason: 'NS (Sequence) must be 6 chars');
      expect(msg.elements['012']?.value.length, 3, reason: 'DE (Currency) must be 3 chars');
      expect(msg.elements['014']?.value.length, 8, reason: 'DA (Date) must be 8 chars');
      expect(msg.elements['015']?.value.length, 6, reason: 'HE (Time) must be 6 chars');

      final frame = msg.toFrame();
      final decoded = NapsMessage.fromFrame(frame);

      expect(decoded.messageType, '001');
      expect(decoded.amountInCents, 200);
      expect(decoded.posId, '1234567');
      expect(decoded.sequenceNumber, 159159);
      expect(decoded.currencyCode, '504');
      expect(decoded.dateStr, '14072026');
      expect(decoded.timeStr, '123456');
    });

    test('paymentConfirmationRequest builds correctly', () {
      final timestamp = DateTime(2026, 7, 14, 12, 34, 56);
      final msg = NapsMessage.paymentConfirmationRequest(
        amountInCents: 200,
        posId: '1234567',
        sequenceNumber: 159159,
        stan: '000098',
        cardMasked: '533576******8237',
        expirationDate: '2409',
        currencyCode: '504',
        timestamp: timestamp,
      );

      expect(msg.messageType, '002');
      expect(msg.amountInCents, 200);
      expect(msg.posId, '1234567');
      expect(msg.sequenceNumber, 159159);
      expect(msg.stan, '000098');
      expect(msg.cardNumber, '533576******8237');
      expect(msg.cardNumber, '533576******8237');
      expect(msg.cardExpirationDate, '2409');
      
      // Stricter MD compliance checks for padding and lengths
      expect(msg.elements['001']?.value.length, 3, reason: 'TM must be 3 chars');
      expect(msg.elements['002']?.value.length, 12, reason: 'MT (Amount) must be 12 chars');
      expect(msg.elements['003']?.value.length, 7, reason: 'NCAI (POS ID) must be 7 chars');
      expect(msg.elements['004']?.value.length, 6, reason: 'NS (Sequence) must be 6 chars');
      expect(msg.elements['008']?.value.length, 6, reason: 'STAN must be 6 chars');
      expect(msg.elements['012']?.value.length, 3, reason: 'DE (Currency) must be 3 chars');
      expect(msg.elements['017']?.value.length, 4, reason: 'DAEX (Expiry) must be 4 chars');
    });

    test('duplicateRequest builds correctly', () {
      final msg = NapsMessage.duplicateRequest(
        posId: '1234567',
        sequenceNumber: 159159,
        stan: '000098',
      );

      expect(msg.messageType, '008');
      expect(msg.stan, '000098');
    });

    test('networkTestRequest builds correctly', () {
      final msg = NapsMessage.networkTestRequest(
        posId: '1234567',
        sequenceNumber: 159159,
      );

      expect(msg.messageType, '009');
      expect(msg.posId, '1234567');
      expect(msg.sequenceNumber, 159159);
    });
  });
}
