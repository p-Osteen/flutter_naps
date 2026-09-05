// ignore_for_file: avoid_print

import 'dart:async';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:naps_flutter/naps_flutter.dart';

class MockNapsConnection implements NapsConnection {
  bool _connected = false;
  final List<NapsMessage> sentMessages = [];
  final List<NapsMessage> _responseQueue =
      []; // Responses EPT will output when client sends a message
  final List<NapsMessage> _receivedBuffer =
      []; // Messages received and buffered waiting to be read by client
  Completer<NapsMessage>? _pendingReceive;

  /// If non-negative, the send() call at this 0-indexed position will throw
  /// a SocketException to simulate a transient disconnect.
  int failOnSendIndex = -1;

  /// Internal counter tracking how many send() calls have been made.
  int _sendCallCount = 0;

  /// If true, reconnect() will succeed.
  bool reconnectSuccess = true;

  /// Tracks reconnect calls for verification.
  int reconnectCallCount = 0;

  /// Configurable timeout for receive() when no message is available.
  /// Defaults to 30s, but can be set shorter for timeout tests.
  Duration mockReceiveTimeout = const Duration(seconds: 30);

  /// Delay before the queued response is delivered. Non-zero lets a test put
  /// the terminal's answer *after* a cancel, which is the case that matters:
  /// cancelling stops our wait, not the terminal's transaction.
  Duration responseDelay = Duration.zero;

  void queueResponse(NapsMessage msg) {
    _responseQueue.add(msg);
  }

  @override
  String get transportDescription => 'mock';

  @override
  bool get isConnected => _connected;

  @override
  Future<bool> connect() async {
    _connected = true;
    return true;
  }

  @override
  Future<void> disconnect() async {
    _connected = false;
  }

  @override
  Future<void> send(NapsMessage message) async {
    final currentIndex = _sendCallCount;
    _sendCallCount++;
    if (currentIndex == failOnSendIndex) {
      print('--> [Mock TPE] Connection lost on send #$currentIndex');
      throw const SocketException('Mock: Connection lost');
    }
    sentMessages.add(message);
    print('--> [Mock TPE] Sending: ${message.toFrame()}');

    // Simulate EPT responding to a sent message
    if (_responseQueue.isNotEmpty) {
      final nextResponse = _responseQueue.removeAt(0);
      if (responseDelay == Duration.zero) {
        _deliverMessage(nextResponse);
      } else {
        Future.delayed(responseDelay, () => _deliverMessage(nextResponse));
      }
    }
  }

  void _deliverMessage(NapsMessage message) {
    print('<-- [Mock TPE] Responding with: ${message.toFrame()}');
    if (_pendingReceive != null && !_pendingReceive!.isCompleted) {
      _pendingReceive!.complete(message);
      _pendingReceive = null;
    } else {
      _receivedBuffer.add(message);
    }
  }

  @override
  Future<NapsMessage> receive({Duration? timeout}) async {
    if (_receivedBuffer.isNotEmpty) {
      final msg = _receivedBuffer.removeAt(0);
      print('<-- [Mock TPE] Received (buffered): ${msg.toFrame()}');
      return msg;
    }

    final completer = Completer<NapsMessage>();
    _pendingReceive = completer;

    // Use the shorter of: caller-supplied timeout or mockReceiveTimeout
    final effectiveTimeout = timeout != null && timeout < mockReceiveTimeout
        ? timeout
        : mockReceiveTimeout;

    return completer.future.timeout(
      effectiveTimeout,
      onTimeout: () {
        if (_pendingReceive == completer) {
          _pendingReceive = null;
        }
        print('<-- [Mock TPE] Receive Timeout after $effectiveTimeout');
        throw TimeoutException('Timed out waiting for NAPS response in mock.');
      },
    );
  }

  @override
  Future<bool> reconnect({int maxAttempts = 3}) async {
    reconnectCallCount++;
    await disconnect();
    if (reconnectSuccess) {
      await connect();
      return true;
    }
    return false;
  }
}

void main() {
  group('NapsSdk Transaction Flow Tests', () {
    late MockNapsConnection connection;
    late NapsSdk sdk;
    const posId = '1234567';

    setUp(() {
      connection = MockNapsConnection();
      sdk = NapsSdk(
        connection: connection,
        posId: posId,
        initialSequenceNumber: 100,
      );
      connection.connect();
    });

    test(
      'networkTest reports success when EPT answers TM 109 with CR 000',
      () async {
        // Queue EPT's response (TM 109, CR 000)
        connection.queueResponse(
          NapsMessage.fromElements([
            TlvElement('001', '109'),
            TlvElement('003', posId),
            TlvElement('004', '000101'),
            TlvElement('013', '000'),
            TlvElement('014', '14072026'),
            TlvElement('015', '120000'),
          ]),
        );

        final result = await sdk.networkTest();
        expect(result.isSuccess, isTrue);
        expect(result.responseCode, '000');
        expect(connection.sentMessages.length, 1);
        expect(connection.sentMessages[0].messageType, '009');
        expect(connection.sentMessages[0].sequenceNumber, 101);
      },
    );

    test(
      'pay with autoConfirm executes the complete payment-to-confirmation flow',
      () async {
        // 1. Queue EPT's payment response (TM 101, CR 000, STAN 000098)
        // Contains the merchant print receipt in DP tag (010)
        final rawMerchantReceipt = '03000201031001S032001C033008MERCHANT?';
        connection.queueResponse(
          NapsMessage.fromElements([
            TlvElement('001', '101'),
            TlvElement('003', posId),
            TlvElement('004', '000101'),
            TlvElement('013', '000'),
            TlvElement('008', '000098'),
            TlvElement('007', '533576******8237'),
            TlvElement('017', '2409'),
            TlvElement('016', 'CARD / PREPAID'),
            TlvElement('009', '123456'),
            TlvElement('040', 'CC'),
            TlvElement('021', 'PREPAID'),
            TlvElement('002', '000000000200'),
            TlvElement('012', '504'),
            TlvElement('010', rawMerchantReceipt),
            TlvElement('014', '14072026'),
            TlvElement('015', '120000'),
          ]),
        );

        // 2. Queue EPT's confirmation response (TM 102, CR 000)
        // Contains customer receipt in DP tag
        final rawCustomerReceipt = '03000201031001S032001C033008CUSTOMER?';
        connection.queueResponse(
          NapsMessage.fromElements([
            TlvElement('001', '102'),
            TlvElement('003', posId),
            TlvElement('004', '000101'),
            TlvElement('013', '000'),
            TlvElement('010', rawCustomerReceipt),
            TlvElement('014', '14072026'),
            TlvElement('015', '120005'),
          ]),
        );

        final result = await sdk.pay(amountInCents: 200, autoConfirm: true);

        // Verify overall result
        expect(result.isSuccess, isTrue);
        expect(result.responseCode, '000');
        expect(result.stan, '000098');
        expect(result.cardNumber, '533576******8237');
        expect(result.cardholderName, 'CARD / PREPAID');
        expect(result.authorizationNumber, '123456');
        expect(result.cardExpirationDate, '2409');
        expect(result.cardEntryMode, 'CC');

        // Verify parsed receipts
        expect(result.merchantReceipt, isNotNull);
        expect(result.merchantReceipt!.lines.first.text, 'MERCHANT');
        expect(result.customerReceipt, isNotNull);
        expect(result.customerReceipt!.lines.first.text, 'CUSTOMER');

        // Verify message exchange sequences
        expect(connection.sentMessages.length, 2);

        // Payment Request
        expect(connection.sentMessages[0].messageType, '001');
        expect(connection.sentMessages[0].sequenceNumber, 101);

        // Confirmation Request - MUST use same sequence number (101)
        expect(connection.sentMessages[1].messageType, '002');
        expect(connection.sentMessages[1].sequenceNumber, 101);
        expect(connection.sentMessages[1].stan, '000098');
        expect(connection.sentMessages[1].cardNumber, '533576******8237');
      },
    );

    test('onApproved callback fires before TM=002 is sent', () async {
      // Queue approved payment response
      connection.queueResponse(
        NapsMessage.fromElements([
          TlvElement('001', '101'),
          TlvElement('003', posId),
          TlvElement('004', '000101'),
          TlvElement('013', '000'),
          TlvElement('008', '000098'),
          TlvElement('007', '533576******8237'),
          TlvElement('017', '2409'),
          TlvElement('016', 'CARD / PREPAID'),
          TlvElement('009', '123456'),
          TlvElement('040', 'SC'),
          TlvElement('010', '03000201031001S032001C033008MERCHANT?'),
          TlvElement('014', '14072026'),
          TlvElement('015', '120000'),
        ]),
      );

      // Queue confirmation response
      connection.queueResponse(
        NapsMessage.fromElements([
          TlvElement('001', '102'),
          TlvElement('003', posId),
          TlvElement('004', '000101'),
          TlvElement('013', '000'),
          TlvElement('010', '03000201031001S032001C033008CUSTOMER?'),
          TlvElement('014', '14072026'),
          TlvElement('015', '120005'),
        ]),
      );

      final events = <String>[];

      final result = await sdk.pay(
        amountInCents: 200,
        autoConfirm: true,
        onApproved: (intermediate) async {
          events.add('callback');
          // At this point only TM=001 should have been sent
          expect(connection.sentMessages.length, 1);
          expect(connection.sentMessages[0].messageType, '001');

          // Verify intermediate result has all fields
          expect(intermediate.stan, '000098');
          expect(intermediate.authorizationNumber, '123456');
          expect(intermediate.cardExpirationDate, '2409');
          expect(intermediate.cardEntryMode, 'SC');
          expect(intermediate.merchantReceipt, isNotNull);
        },
      );
      events.add('pay_returned');

      // Verify ordering: callback happened first
      expect(events[0], 'callback');
      expect(events[1], 'pay_returned');

      // TM=002 was sent after callback
      expect(connection.sentMessages.length, 2);
      expect(connection.sentMessages[1].messageType, '002');
      expect(result.isSuccess, isTrue);
    });

    test('onApproved is NOT called when payment is declined', () async {
      // Queue declined payment response (CR = 117 = insufficient funds)
      connection.queueResponse(
        NapsMessage.fromElements([
          TlvElement('001', '101'),
          TlvElement('003', posId),
          TlvElement('004', '000101'),
          TlvElement('013', '117'),
          TlvElement('014', '14072026'),
          TlvElement('015', '120000'),
        ]),
      );

      bool callbackInvoked = false;

      final result = await sdk.pay(
        amountInCents: 200,
        autoConfirm: true,
        onApproved: (intermediate) async {
          callbackInvoked = true;
        },
      );

      expect(callbackInvoked, isFalse);
      expect(result.isSuccess, isFalse);
      // Only TM=001 sent; no TM=002 since payment was declined
      expect(connection.sentMessages.length, 1);
    });

    test(
      'onApproved failure is reported but does not fail an approved payment',
      () async {
        // Queue approved payment response
        connection.queueResponse(
          NapsMessage.fromElements([
            TlvElement('001', '101'),
            TlvElement('003', posId),
            TlvElement('004', '000101'),
            TlvElement('013', '000'),
            TlvElement('008', '000098'),
            TlvElement('007', '533576******8237'),
            TlvElement('017', '2409'),
            TlvElement('009', '123456'),
            TlvElement('040', 'CC'),
            TlvElement('010', '03000201031001S032001C033008MERCHANT?'),
            TlvElement('014', '14072026'),
            TlvElement('015', '120000'),
          ]),
        );

        // Queue confirmation response
        connection.queueResponse(
          NapsMessage.fromElements([
            TlvElement('001', '102'),
            TlvElement('003', posId),
            TlvElement('004', '000101'),
            TlvElement('013', '000'),
            TlvElement('010', '03000201031001S032001C033008CUSTOMER?'),
            TlvElement('014', '14072026'),
            TlvElement('015', '120005'),
          ]),
        );

        final result = await sdk.pay(
          amountInCents: 200,
          autoConfirm: true,
          onApproved: (intermediate) async {
            throw Exception('Printer unavailable');
          },
        );

        // TM=002 is still sent despite the callback failure.
        expect(connection.sentMessages.length, 2);
        expect(connection.sentMessages[1].messageType, '002');

        // The payment itself completed: the terminal approved the card and
        // recorded it. A printer fault is reported alongside, not instead.
        expect(result.isSuccess, isTrue);
        expect(result.source, NapsResultSource.terminal);
        expect(result.callbackError, isNotNull);
        expect(result.failureReason, NapsFailureReason.callbackFailed);
        expect(result.stan, '000098');
      },
    );

    test('initiate and confirm cancellation 2-step flow works', () async {
      // 1. Queue EPT's response to cancel initiate (TM 103)
      connection.queueResponse(
        NapsMessage.fromElements([
          TlvElement('001', '103'),
          TlvElement('003', posId),
          TlvElement('004', '000101'),
          TlvElement('008', '000098'),
          TlvElement('013', '000'),
          TlvElement('002', '000000000200'),
          TlvElement('012', '504'),
          TlvElement('018', '14072026'),
          TlvElement('019', '120000'),
          TlvElement('007', '533576******8237'),
          TlvElement('017', '2409'),
          TlvElement('014', '14072026'),
          TlvElement('015', '120002'),
        ]),
      );

      // Initiate cancellation
      final cancelInfo = await sdk.initiateCancellation(stan: '000098');

      expect(cancelInfo.isFound, isTrue);
      expect(cancelInfo.amountInCents, 200);
      expect(cancelInfo.currencyCode, '504');
      expect(cancelInfo.sequenceNumber, 101);

      // 2. Queue EPT's response to cancel confirmation (TM 104)
      connection.queueResponse(
        NapsMessage.fromElements([
          TlvElement('001', '104'),
          TlvElement('003', posId),
          TlvElement('004', '000101'),
          TlvElement('008', '000098'),
          TlvElement('013', '000'),
          TlvElement('010', '03000201031001S032001C033009CANCELLED?'),
          TlvElement('014', '14072026'),
          TlvElement('015', '120003'),
        ]),
      );

      // Confirm cancellation
      final cancelResult = await sdk.confirmCancellation(info: cancelInfo);

      expect(cancelResult.isSuccess, isTrue);
      expect(cancelResult.responseCode, '000');
      expect(cancelResult.cancellationReceipt, isNotNull);
      expect(cancelResult.cancellationReceipt!.lines.first.text, 'CANCELLED');

      expect(connection.sentMessages.length, 2);
      expect(connection.sentMessages[0].messageType, '003');
      expect(connection.sentMessages[0].sequenceNumber, 101);

      expect(connection.sentMessages[1].messageType, '004');
      expect(
        connection.sentMessages[1].sequenceNumber,
        101,
      ); // Identical to TM 003
    });

    test('extractFields() extracts named fields from receipt lines', () {
      final rawData =
          '03000201031001S032001G033018Merchant ID: 20000'
          '*03000202031001S032001G033021Terminal ID: 88398363'
          '*03000203031001S032001G033012STAN: 000098?';

      final receipt = NapsReceipt.parse(rawData);
      final fields = receipt.extractFields();

      expect(fields['merchant id'], '20000');
      expect(fields['terminal id'], '88398363');
      expect(fields['stan'], '000098');
    });

    test('extractFields() returns empty map when no key:value lines exist', () {
      final rawData = '03000201031001S032001C033008APPROVED?';
      final receipt = NapsReceipt.parse(rawData);
      expect(receipt.extractFields(), isEmpty);
    });
  });

  // ════════════════════════════════════════════════════════════════════════
  // NEW TEST GROUPS — added per integration update plan
  // ════════════════════════════════════════════════════════════════════════

  group('Response Code Mapping Tests', () {
    test(
      'response code 480 (cancellation already done) is properly mapped',
      () {
        final metadata = NapsResponseCodes.lookup('480');
        expect(metadata.code, '480');
        expect(metadata.status, NapsResponseStatus.error);
        expect(metadata.description, contains('already done'));
        expect(metadata.isSuccess, isFalse);
      },
    );

    test('response code 000 (success) is properly mapped', () {
      final metadata = NapsResponseCodes.lookup('000');
      expect(metadata.isSuccess, isTrue);
      expect(metadata.status, NapsResponseStatus.approved);
    });

    test('response code 302 (transaction not found) is properly mapped', () {
      final metadata = NapsResponseCodes.lookup('302');
      expect(metadata.isSuccess, isFalse);
      expect(metadata.status, NapsResponseStatus.declined);
      expect(metadata.description, contains('not found'));
    });

    test('response code 482 (already cancelled) is properly mapped', () {
      final metadata = NapsResponseCodes.lookup('482');
      expect(metadata.isSuccess, isFalse);
      expect(metadata.description, contains('cancelled'));
    });

    test('response code 909 (server unavailable) is properly mapped', () {
      final metadata = NapsResponseCodes.lookup('909');
      expect(metadata.isSuccess, isFalse);
      expect(metadata.status, NapsResponseStatus.error);
    });

    test(
      'response code 995 (undocumented) falls back to generic declined status',
      () {
        final meta995 = NapsResponseCodes.lookup('995');
        expect(meta995.isSuccess, isFalse);
        expect(meta995.status, NapsResponseStatus.declined);
        expect(meta995.description, contains('not completed'));
      },
    );

    test(
      'response code 280 (undocumented) falls back to generic declined status',
      () {
        final meta280 = NapsResponseCodes.lookup('280');
        expect(meta280.isSuccess, isFalse);
        expect(meta280.status, NapsResponseStatus.declined);
        expect(meta280.description, contains('not completed'));
      },
    );
  });

  group('NS echo Tests', () {
    late MockNapsConnection connection;
    late NapsSdk sdk;
    const posId = '0100001';

    setUp(() {
      connection = MockNapsConnection();
      sdk = NapsSdk(
        connection: connection,
        posId: posId,
        initialSequenceNumber: 100,
      );
      connection.connect();
    });

    NapsMessage tm109({required String ns}) => NapsMessage.fromElements([
      TlvElement('001', '109'),
      TlvElement('003', posId),
      TlvElement('004', ns),
      TlvElement('013', '000'),
      TlvElement('014', '14072026'),
      TlvElement('015', '120000'),
    ]);

    test('an echoed NS is accepted', () {
      connection.queueResponse(tm109(ns: '000101'));
      return sdk.networkTest().then((result) {
        expect(result.isSuccess, isTrue, reason: result.description);
        expect(result.responseCode, '000');
      });
    });

    // Spec III.2.3.1-III.2.3.6: every response carries "NS - same value as
    // sent", and III.2.3.2 has the terminal correlate on TM, NCAI and NS. A
    // response bearing someone else's NS is not the answer to this request.
    test('a response with a different NS is rejected', () async {
      connection.queueResponse(tm109(ns: '000002'));
      final result = await sdk.networkTest();
      expect(result.isSuccess, isFalse);
      expect(result.failureReason, NapsFailureReason.protocolMismatch);
      expect(result.description, contains('NS'));
    });

    test('a wrong message type is rejected', () async {
      connection.queueResponse(
        NapsMessage.fromElements([
          TlvElement('001', '102'),
          TlvElement('003', posId),
          TlvElement('004', '000101'),
          TlvElement('013', '000'),
          TlvElement('014', '14072026'),
          TlvElement('015', '120000'),
        ]),
      );
      final result = await sdk.networkTest();
      expect(result.isSuccess, isFalse);
      expect(result.failureReason, NapsFailureReason.protocolMismatch);
    });
  });

  group('Cancel Token Tests', () {
    late MockNapsConnection connection;
    late NapsSdk sdk;
    const posId = '1234567';

    setUp(() {
      connection = MockNapsConnection();
      sdk = NapsSdk(
        connection: connection,
        posId: posId,
        initialSequenceNumber: 100,
        cancelGraceWindow: const Duration(milliseconds: 400),
      );
      connection.connect();
    });

    test('NapsCancelToken cancel() sets isCancelled to true', () {
      final token = NapsCancelToken();
      expect(token.isCancelled, isFalse);
      token.cancel();
      expect(token.isCancelled, isTrue);
    });

    test('NapsCancelToken cancel() is safe to call multiple times', () {
      final token = NapsCancelToken();
      token.cancel();
      token.cancel(); // Should not throw
      expect(token.isCancelled, isTrue);
    });

    test('abort via CancelToken returns NapsResultSource.cancelled', () async {
      // Don't queue any response — the EPT never responds.
      // The cancel token will fire before the 2-minute timeout.
      final cancelToken = NapsCancelToken();

      // Cancel after a short delay
      Future.delayed(const Duration(milliseconds: 50), () {
        cancelToken.cancel();
      });

      final result = await sdk.pay(
        amountInCents: 200,
        cancelToken: cancelToken,
      );

      expect(result.isSuccess, isFalse);
      expect(result.source, NapsResultSource.cancelled);
      expect(result.responseCode, isEmpty);
      expect(result.description, contains('cancelled'));
    });

    test(
      'a token cancelled before pay() stops TM 001 being sent at all',
      () async {
        final cancelToken = NapsCancelToken()..cancel();

        final result = await sdk.pay(
          amountInCents: 200,
          cancelToken: cancelToken,
        );

        expect(result.source, NapsResultSource.cancelled);
        // Starting a transaction the terminal would then have to time out of
        // is worse than not starting one.
        expect(connection.sentMessages, isEmpty);
      },
    );

    test(
      'an approval landing after the cancel is preserved, not discarded',
      () async {
        // The terminal answers 250ms after TM 001; the user cancels at 50ms.
        // Cancelling aborts our wait, not the card read that is already running.
        connection.responseDelay = const Duration(milliseconds: 250);
        connection.queueResponse(
          NapsMessage.fromElements([
            TlvElement('001', '101'),
            TlvElement('003', posId),
            TlvElement('004', '000101'),
            TlvElement('013', '000'),
            TlvElement('008', '000098'),
            TlvElement('007', '533576******8237'),
            TlvElement('017', '2409'),
            TlvElement('009', '123456'),
            TlvElement('040', 'CC'),
            TlvElement('010', '03000201031001S032001C033008MERCHANT?'),
            TlvElement('014', '14072026'),
            TlvElement('015', '120000'),
          ]),
        );

        final cancelToken = NapsCancelToken();
        Future.delayed(const Duration(milliseconds: 50), cancelToken.cancel);

        final result = await sdk.pay(
          amountInCents: 200,
          cancelToken: cancelToken,
        );

        // Not a clean cancellation: the card really was approved.
        expect(result.isSuccess, isFalse);
        expect(result.source, NapsResultSource.approvedNotConfirmed);
        expect(result.failureReason, NapsFailureReason.cancelledByUser);
        expect(result.wasApproved, isTrue);
        expect(result.requiresReconciliation, isTrue);

        // The evidence survives so the reversal can be checked against the batch.
        expect(result.stan, '000098');
        expect(result.sequenceNumber, 101);
        expect(result.cardNumber, '533576******8237');
        expect(result.merchantReceipt?.lines.single.text, 'MERCHANT');

        // TM 002 must NOT be sent: withholding it is what makes the terminal
        // reverse the transaction.
        expect(connection.sentMessages.length, 1);
        expect(connection.sentMessages.single.messageType, '001');
      },
    );

    test(
      'a decline landing after the cancel is reported as cancelled',
      () async {
        connection.responseDelay = const Duration(milliseconds: 250);
        connection.queueResponse(
          NapsMessage.fromElements([
            TlvElement('001', '101'),
            TlvElement('003', posId),
            TlvElement('004', '000101'),
            TlvElement('013', '117'),
            TlvElement('014', '14072026'),
            TlvElement('015', '120000'),
          ]),
        );

        final cancelToken = NapsCancelToken();
        Future.delayed(const Duration(milliseconds: 50), cancelToken.cancel);

        final result = await sdk.pay(
          amountInCents: 200,
          cancelToken: cancelToken,
        );

        // Nothing was charged, so the user's intent is the honest answer.
        expect(result.source, NapsResultSource.cancelled);
        expect(result.requiresReconciliation, isFalse);
        expect(result.description, contains('117'));
        expect(connection.sentMessages.length, 1);
      },
    );

    test(
      'nothing arriving in the grace window is a clean cancellation',
      () async {
        final cancelToken = NapsCancelToken();
        Future.delayed(const Duration(milliseconds: 50), cancelToken.cancel);

        final result = await sdk.pay(
          amountInCents: 200,
          cancelToken: cancelToken,
        );

        expect(result.source, NapsResultSource.cancelled);
        expect(result.wasApproved, isFalse);
        expect(result.requiresReconciliation, isFalse);
        expect(result.stan, isNull);
      },
    );

    test(
      'cancel token does NOT interfere when EPT responds before cancel',
      () async {
        // Queue immediate response
        connection.queueResponse(
          NapsMessage.fromElements([
            TlvElement('001', '101'),
            TlvElement('003', posId),
            TlvElement('004', '000101'),
            TlvElement('013', '000'),
            TlvElement('008', '000098'),
            TlvElement('007', '533576******8237'),
            TlvElement('017', '2409'),
            TlvElement('009', '123456'),
            TlvElement('040', 'CC'),
            TlvElement('010', '03000201031001S032001C033008MERCHANT?'),
            TlvElement('014', '14072026'),
            TlvElement('015', '120000'),
          ]),
        );

        connection.queueResponse(
          NapsMessage.fromElements([
            TlvElement('001', '102'),
            TlvElement('003', posId),
            TlvElement('004', '000101'),
            TlvElement('013', '000'),
            TlvElement('010', '03000201031001S032001C033008CUSTOMER?'),
            TlvElement('014', '14072026'),
            TlvElement('015', '120005'),
          ]),
        );

        final cancelToken = NapsCancelToken();
        // Don't cancel — let the normal flow proceed

        final result = await sdk.pay(
          amountInCents: 200,
          cancelToken: cancelToken,
          autoConfirm: true,
        );

        expect(result.isSuccess, isTrue);
        expect(result.responseCode, '000');
        expect(cancelToken.isCancelled, isFalse);
      },
    );
  });

  group('Enriched Transaction Result Fields Tests', () {
    late MockNapsConnection connection;
    late NapsSdk sdk;
    const posId = '1234567';

    setUp(() {
      connection = MockNapsConnection();
      sdk = NapsSdk(
        connection: connection,
        posId: posId,
        initialSequenceNumber: 100,
      );
      connection.connect();
    });

    test('successful payment carries all §10 persisted fields', () async {
      // Queue full payment response with all fields
      connection.queueResponse(
        NapsMessage.fromElements([
          TlvElement('001', '101'),
          TlvElement('003', posId),
          TlvElement('004', '000101'),
          TlvElement('013', '000'),
          TlvElement('008', '000081'),
          TlvElement('007', '5321****5556'),
          TlvElement('017', '2810'),
          TlvElement('016', 'NAPS'),
          TlvElement('009', '748120'),
          TlvElement('040', 'SC'),
          TlvElement('021', 'PREPAID'),
          TlvElement('002', '000000022000'),
          TlvElement('012', '504'),
          TlvElement('010', '03000201031001S032001C033004Naps?'),
          TlvElement('014', '23032026'),
          TlvElement('015', '141447'),
        ]),
      );

      connection.queueResponse(
        NapsMessage.fromElements([
          TlvElement('001', '102'),
          TlvElement('003', posId),
          TlvElement('004', '000101'),
          TlvElement('013', '000'),
          TlvElement('010', '03000201031001S032001C033008CUSTOMER?'),
          TlvElement('014', '23032026'),
          TlvElement('015', '141456'),
        ]),
      );

      final result = await sdk.pay(amountInCents: 22000, autoConfirm: true);

      // All §10 fields present
      expect(result.isSuccess, isTrue);
      expect(result.stan, '000081');
      expect(result.authorizationNumber, '748120');
      expect(result.cardNumber, '5321****5556');
      expect(result.cardExpirationDate, '2810');
      expect(result.cardEntryMode, 'SC');
      expect(result.paymentType, 'PREPAID');
      expect(result.amountInCents, 22000);
      expect(result.currencyCode, '504');
      expect(result.transactionDate, '23032026');
      expect(result.transactionTime, '141447');
      expect(result.cardholderName, 'NAPS');
      expect(result.merchantReceipt, isNotNull);
      expect(result.customerReceipt, isNotNull);
    });
  });

  group('Reconnect During TM=002 Tests', () {
    late MockNapsConnection connection;
    late NapsSdk sdk;
    const posId = '1234567';

    setUp(() {
      connection = MockNapsConnection();
      sdk = NapsSdk(
        connection: connection,
        posId: posId,
        initialSequenceNumber: 100,
      );
      connection.connect();
    });

    test(
      'reconnect is attempted when send fails during TM=002 confirmation',
      () async {
        // Queue approved payment response (TM=101)
        connection.queueResponse(
          NapsMessage.fromElements([
            TlvElement('001', '101'),
            TlvElement('003', posId),
            TlvElement('004', '000101'),
            TlvElement('013', '000'),
            TlvElement('008', '000098'),
            TlvElement('007', '533576******8237'),
            TlvElement('017', '2409'),
            TlvElement('009', '123456'),
            TlvElement('040', 'CC'),
            TlvElement('010', '03000201031001S032001C033008MERCHANT?'),
            TlvElement('014', '14072026'),
            TlvElement('015', '120000'),
          ]),
        );

        // Simulate connection drop: TM=002 send (index 1) fails, then reconnect succeeds
        // and the retry attempt delivers the confirmation response.
        connection.failOnSendIndex = 1; // Fail on second send (TM=002)
        connection.reconnectSuccess = true;

        // Queue the confirmation response for after reconnect
        connection.queueResponse(
          NapsMessage.fromElements([
            TlvElement('001', '102'),
            TlvElement('003', posId),
            TlvElement('004', '000101'),
            TlvElement('013', '000'),
            TlvElement('010', '03000201031001S032001C033008CUSTOMER?'),
            TlvElement('014', '14072026'),
            TlvElement('015', '120005'),
          ]),
        );

        final result = await sdk.pay(amountInCents: 200, autoConfirm: true);

        expect(result.isSuccess, isTrue);
        expect(connection.reconnectCallCount, 1);
        // TM=001 sent + TM=002 sent (after reconnect)
        expect(connection.sentMessages.length, 2);
        expect(connection.sentMessages[0].messageType, '001');
        expect(connection.sentMessages[1].messageType, '002');
      },
    );

    test(
      'reconnect failure during TM=002 preserves the approved payment',
      () async {
        // Queue approved payment response (TM=101)
        connection.queueResponse(
          NapsMessage.fromElements([
            TlvElement('001', '101'),
            TlvElement('003', posId),
            TlvElement('004', '000101'),
            TlvElement('013', '000'),
            TlvElement('008', '000098'),
            TlvElement('007', '533576******8237'),
            TlvElement('017', '2409'),
            TlvElement('009', '123456'),
            TlvElement('040', 'CC'),
            TlvElement('010', '03000201031001S032001C033008MERCHANT?'),
            TlvElement('014', '14072026'),
            TlvElement('015', '120000'),
          ]),
        );

        // Simulate connection drop + reconnect failure
        connection.failOnSendIndex = 1; // Fail on second send (TM=002)
        connection.reconnectSuccess = false;

        final result = await sdk.pay(amountInCents: 200, autoConfirm: true);

        expect(result.isSuccess, isFalse);
        // The card was approved. Losing the socket afterwards must not throw
        // that away: this is an unresolved transaction, not a decline.
        expect(result.source, NapsResultSource.approvedNotConfirmed);
        expect(result.requiresReconciliation, isTrue);
        expect(result.wasApproved, isTrue);
        expect(result.failureReason, NapsFailureReason.connectionLost);
        // Everything needed to settle it by hand survives.
        expect(result.sequenceNumber, 101);
        expect(result.stan, '000098');
        expect(result.amountInCents, isNull);
        expect(result.cardNumber, '533576******8237');
        expect(result.cardExpirationDate, '2409');
        expect(result.authorizationNumber, '123456');
        expect(result.merchantReceipt, isNotNull);
        expect(result.merchantReceipt!.lines.single.text, 'MERCHANT');
        expect(connection.reconnectCallCount, 1);
      },
    );
  });

  group('Cancellation Response Code 480 Tests', () {
    late MockNapsConnection connection;
    late NapsSdk sdk;
    const posId = '1234567';

    setUp(() {
      connection = MockNapsConnection();
      sdk = NapsSdk(
        connection: connection,
        posId: posId,
        initialSequenceNumber: 100,
      );
      connection.connect();
    });

    test(
      'cancellation confirmation with CR=480 ("already done") is treated as success',
      () async {
        // Initiate
        connection.queueResponse(
          NapsMessage.fromElements([
            TlvElement('001', '103'),
            TlvElement('003', posId),
            TlvElement('004', '000101'),
            TlvElement('008', '000098'),
            TlvElement('013', '000'),
            TlvElement('002', '000000000200'),
            TlvElement('012', '504'),
            TlvElement('018', '14072026'),
            TlvElement('019', '120000'),
            TlvElement('007', '533576******8237'),
            TlvElement('017', '2409'),
            TlvElement('014', '14072026'),
            TlvElement('015', '120002'),
          ]),
        );

        final cancelInfo = await sdk.initiateCancellation(stan: '000098');
        expect(cancelInfo.isFound, isTrue);

        // Confirm — EPT returns 480 (cancellation already done)
        connection.queueResponse(
          NapsMessage.fromElements([
            TlvElement('001', '104'),
            TlvElement('003', posId),
            TlvElement('004', '000101'),
            TlvElement('008', '000098'),
            TlvElement('013', '480'),
            TlvElement('014', '14072026'),
            TlvElement('015', '120003'),
          ]),
        );

        final cancelResult = await sdk.confirmCancellation(info: cancelInfo);

        // CR=480 should be treated as success per integration reference
        expect(cancelResult.isSuccess, isTrue);
        expect(cancelResult.responseCode, '480');
      },
    );
  });

  group('Timeout Tests', () {
    late MockNapsConnection connection;
    late NapsSdk sdk;
    const posId = '1234567';

    setUp(() {
      connection = MockNapsConnection();
      sdk = NapsSdk(
        connection: connection,
        posId: posId,
        initialSequenceNumber: 100,
      );
      connection.connect();
    });

    test(
      'payment timeout is reported as a typed timeout failure',
      () async {
        // Don't queue any response — let it time out.
        // Set a short mock timeout to avoid waiting 2 minutes in the test.
        connection.mockReceiveTimeout = const Duration(seconds: 1);

        final result = await sdk.pay(amountInCents: 200);

        expect(result.isSuccess, isFalse);
        expect(result.source, NapsResultSource.sdkError);
        expect(result.responseCode, isEmpty);
        // Callers must not have to string-match the exception text.
        expect(result.failureReason, NapsFailureReason.timeout);
        expect(result.wasApproved, isFalse);
        expect(result.sequenceNumber, 101);
      },
      timeout: const Timeout(Duration(seconds: 10)),
    );
  });

  group('TYPA (Payment Type) Getter Tests', () {
    test('paymentType getter returns TYPA tag value', () {
      final msg = NapsMessage.fromElements([
        TlvElement('001', '101'),
        TlvElement('003', '1234567'),
        TlvElement('004', '000001'),
        TlvElement('014', '14072026'),
        TlvElement('015', '120000'),
        TlvElement('021', 'PREPAID'),
      ]);

      expect(msg.paymentType, 'PREPAID');
    });

    test('paymentType getter returns empty string when TYPA is absent', () {
      final msg = NapsMessage.fromElements([
        TlvElement('001', '101'),
        TlvElement('003', '1234567'),
        TlvElement('004', '000001'),
        TlvElement('014', '14072026'),
        TlvElement('015', '120000'),
      ]);

      expect(msg.paymentType, '');
    });
  });
}
