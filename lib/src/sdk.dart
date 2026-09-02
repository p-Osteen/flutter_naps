import 'dart:async';
import 'dart:io';
import 'cancel_token.dart';
import 'connection/connection.dart';
import 'protocol/message.dart';
import 'protocol/receipt.dart';
import 'protocol/response_codes.dart';

/// Indicates where a transaction result originated.
enum NapsResultSource {
  /// Result contains a real NAPS terminal response code.
  terminal,

  /// Payment was cancelled by the user (CancelToken) before the terminal responded.
  cancelled,

  /// An SDK-level error occurred (connection failure, timeout, etc.).
  sdkError,
}

/// Represents the result of a NAPS transaction attempt (payment or confirmation).
class NapsTransactionResult {
  final bool isSuccess;
  final NapsResultSource source;
  final String responseCode;
  final String description;
  final String userMessage;
  final String? stan;
  final String? cardNumber;
  final String? cardholderName;
  final String? authorizationNumber;  // Tag 009 — NA
  final String? cardExpirationDate;   // Tag 017 — DAEX
  final String? cardEntryMode;        // Tag 040 — EM
  final String? paymentType;          // Tag 021 — TYPA
  final int? amountInCents;           // Tag 002 — MT
  final String? currencyCode;         // Tag 012 — DE
  final String? transactionDate;      // Tag 014 — DA (from TM=101)
  final String? transactionTime;      // Tag 015 — HE (from TM=101)
  final NapsReceipt? merchantReceipt;
  final NapsReceipt? customerReceipt;
  final NapsMessage? paymentResponse;
  final NapsMessage? confirmationResponse;

  NapsTransactionResult({
    required this.isSuccess,
    required this.source,
    required this.responseCode,
    required this.description,
    required this.userMessage,
    this.stan,
    this.cardNumber,
    this.cardholderName,
    this.authorizationNumber,
    this.cardExpirationDate,
    this.cardEntryMode,
    this.paymentType,
    this.amountInCents,
    this.currencyCode,
    this.transactionDate,
    this.transactionTime,
    this.merchantReceipt,
    this.customerReceipt,
    this.paymentResponse,
    this.confirmationResponse,
  });

  @override
  String toString() =>
      'NapsTransactionResult(success: $isSuccess, source: $source, code: $responseCode, msg: "$userMessage", '
      'desc: "$description", stan: $stan, authNum: $authorizationNumber, '
      'entryMode: $cardEntryMode, expiry: $cardExpirationDate, '
      'paymentType: $paymentType, amount: $amountInCents, currency: $currencyCode)';
}

/// Represents intermediate information retrieved from the terminal before cancellation is confirmed.
class NapsCancellationInfo {
  final bool isFound;
  final NapsResultSource source;
  final String responseCode;
  final String userMessage;
  final int sequenceNumber; // Stored to reuse in confirmation (TM 004)
  final String stan;
  final int amountInCents;
  final String currencyCode;
  final String transactionDate;
  final String transactionTime;
  final String cardNumber;
  final String expirationDate;
  final NapsMessage? originalResponse;

  NapsCancellationInfo({
    required this.isFound,
    required this.source,
    required this.responseCode,
    required this.userMessage,
    required this.sequenceNumber,
    required this.stan,
    required this.amountInCents,
    required this.currencyCode,
    required this.transactionDate,
    required this.transactionTime,
    required this.cardNumber,
    required this.expirationDate,
    this.originalResponse,
  });
}

/// Represents the final result of a cancellation request.
class NapsCancellationResult {
  final bool isSuccess;
  final NapsResultSource source;
  final String responseCode;
  final String userMessage;
  final NapsReceipt? cancellationReceipt;
  final NapsMessage? confirmationResponse;

  NapsCancellationResult({
    required this.isSuccess,
    required this.source,
    required this.responseCode,
    required this.userMessage,
    this.cancellationReceipt,
    this.confirmationResponse,
  });
}

/// The main SDK class used for interacting with a NAPS SUNMI P2 terminal over the M2M TLV protocol.
class NapsSdk {
  final NapsConnection connection;
  final String posId;
  
  int _sequenceNumber;

  NapsSdk({
    required this.connection,
    required this.posId,
    int initialSequenceNumber = 1,
  }) : _sequenceNumber = initialSequenceNumber {
    if (posId.length > 7) {
      throw ArgumentError('posId must be at most 7 characters long.');
    }
  }

  /// Increments and returns the next sequence number (NS).
  /// Resets to 1 if it exceeds 999999.
  int _getNextSequenceNumber() {
    _sequenceNumber = (_sequenceNumber + 1) % 1000000;
    if (_sequenceNumber == 0) {
      _sequenceNumber = 1;
    }
    return _sequenceNumber;
  }

  /// Verifies connectivity to the EPT using a Network Test message (TM 009).
  Future<bool> networkTest() async {
    try {
      final seqNum = _getNextSequenceNumber();
      final request = NapsMessage.networkTestRequest(
        posId: posId,
        sequenceNumber: seqNum,
      );

      await connection.send(request);
      final response = await connection.receive(timeout: const Duration(seconds: 30));

      final metadata = NapsResponseCodes.lookup(response.responseCode);
      return metadata.isSuccess && response.messageType == '109';
    } catch (_) {
      return false;
    }
  }

  /// Executes a payment transaction.
  ///
  /// If [autoConfirm] is true, the SDK automatically executes the confirmation step
  /// within the mandatory 40-second window if the payment is approved.
  ///
  /// If [onApproved] is provided and [autoConfirm] is true, the callback is invoked
  /// with the intermediate result (containing the merchant receipt and all payment
  /// fields) **before** the confirmation (TM 002) is sent. This gives the caller a
  /// window to print the merchant receipt as required by the NAPS integration guide.
  ///
  /// If [cancelToken] is provided, the caller can abort the 2-minute card-read wait
  /// by calling [NapsCancelToken.cancel]. The method returns a failure result with
  /// `source: NapsResultSource.cancelled`.
  ///
  /// **Important:** TM 002 is always sent regardless of whether [onApproved] throws.
  /// If the callback fails (e.g. printer unavailable), the error is returned as a
  /// `source: NapsResultSource.sdkError` failure result after the confirmation
  /// completes so the terminal is never left in a pending state.
  Future<NapsTransactionResult> pay({
    required int amountInCents,
    String currencyCode = '504',
    bool autoConfirm = true,
    Future<void> Function(NapsTransactionResult intermediateResult)? onApproved,
    NapsCancelToken? cancelToken,
  }) async {
    final seqNum = _getNextSequenceNumber();

    // Step 1: Send Payment Request (TM 001)
    final request = NapsMessage.paymentRequest(
      amountInCents: amountInCents,
      posId: posId,
      sequenceNumber: seqNum,
      currencyCode: currencyCode,
    );

    try {
      await connection.send(request);

      // Payment request involves user interaction (PIN entry), timeout is 2 minutes.
      // If a cancelToken is provided, race the receive against the cancel signal.
      final NapsMessage response;
      if (cancelToken != null) {
        response = await _receiveWithCancel(
          timeout: const Duration(minutes: 2),
          cancelToken: cancelToken,
        );
      } else {
        response = await connection.receive(timeout: const Duration(minutes: 2));
      }

      final responseCode = response.responseCode;
      final metadata = NapsResponseCodes.lookup(responseCode);

      if (!metadata.isSuccess) {
        return NapsTransactionResult(
          isSuccess: false,
          source: NapsResultSource.terminal,
          responseCode: responseCode,
          description: metadata.description,
          userMessage: metadata.userMessage,
          paymentResponse: response,
        );
      }

      final stan = response.stan;
      final cardMasked = response.cardNumber;
      final expirationDate = response.cardExpirationDate;
      final cardholder = response.cardholderName;
      final authNum = response.authorizationNumber;
      final entryMode = response.cardEntryMode;
      final pType = response.paymentType;
      final respAmount = response.amountInCents;
      final respCurrency = response.currencyCode;
      final respDate = response.dateStr;
      final respTime = response.timeStr;
      final merchantReceipt = NapsReceipt.parse(response.receiptData);

      // Step 2: Auto-confirm if requested
      if (autoConfirm) {
        // Build intermediate result so onApproved can use it for receipt printing
        final intermediateResult = NapsTransactionResult(
          isSuccess: true,
          source: NapsResultSource.terminal,
          responseCode: responseCode,
          description: metadata.description,
          userMessage: metadata.userMessage,
          stan: stan,
          cardNumber: cardMasked,
          cardholderName: cardholder,
          authorizationNumber: authNum,
          cardExpirationDate: expirationDate,
          cardEntryMode: entryMode,
          paymentType: pType,
          amountInCents: respAmount,
          currencyCode: respCurrency,
          transactionDate: respDate,
          transactionTime: respTime,
          merchantReceipt: merchantReceipt,
          paymentResponse: response,
        );

        // Invoke onApproved (e.g. print receipt) before sending TM 002.
        // TM 002 is always sent regardless of whether onApproved throws,
        // to avoid leaving the terminal in a pending state.
        Object? callbackError;
        StackTrace? callbackStack;
        if (onApproved != null) {
          try {
            await onApproved(intermediateResult);
          } catch (e, st) {
            callbackError = e;
            callbackStack = st;
          }
        }

        // Confirmation (TM 002) must use the SAME sequence number as the initial payment request (TM 001)
        final confirmRequest = NapsMessage.paymentConfirmationRequest(
          amountInCents: amountInCents,
          posId: posId,
          sequenceNumber: seqNum,
          stan: stan,
          cardMasked: cardMasked,
          expirationDate: expirationDate,
          currencyCode: currencyCode,
        );

        // Attempt to send TM=002. If the connection dropped after TM=101,
        // try reconnecting with exponential backoff before giving up.
        try {
          await connection.send(confirmRequest);
        } on IOException catch (_) {
          final reconnected = await connection.reconnect();
          if (!reconnected) {
            rethrow;
          }
          await connection.send(confirmRequest);
        }

        final confirmResponse = await connection.receive(timeout: const Duration(seconds: 30));

        final confirmMetadata = NapsResponseCodes.lookup(confirmResponse.responseCode);
        final customerReceipt = NapsReceipt.parse(confirmResponse.receiptData);

        // Re-throw callback error after confirmation so the caller knows printing failed
        if (callbackError != null) {
          Error.throwWithStackTrace(callbackError, callbackStack!);
        }

        return NapsTransactionResult(
          isSuccess: confirmMetadata.isSuccess,
          source: NapsResultSource.terminal,
          responseCode: confirmResponse.responseCode,
          description: confirmMetadata.description,
          userMessage: confirmMetadata.userMessage,
          stan: stan,
          cardNumber: cardMasked,
          cardholderName: cardholder,
          authorizationNumber: authNum,
          cardExpirationDate: expirationDate,
          cardEntryMode: entryMode,
          paymentType: pType,
          amountInCents: respAmount,
          currencyCode: respCurrency,
          transactionDate: respDate,
          transactionTime: respTime,
          merchantReceipt: merchantReceipt,
          customerReceipt: customerReceipt,
          paymentResponse: response,
          confirmationResponse: confirmResponse,
        );
      } else {
        // If not auto-confirming, return the intermediate success result.
        // The host application is responsible for manual confirmation.
        return NapsTransactionResult(
          isSuccess: true,
          source: NapsResultSource.terminal,
          responseCode: responseCode,
          description: metadata.description,
          userMessage: metadata.userMessage,
          stan: stan,
          cardNumber: cardMasked,
          cardholderName: cardholder,
          authorizationNumber: authNum,
          cardExpirationDate: expirationDate,
          cardEntryMode: entryMode,
          paymentType: pType,
          amountInCents: respAmount,
          currencyCode: respCurrency,
          transactionDate: respDate,
          transactionTime: respTime,
          merchantReceipt: merchantReceipt,
          paymentResponse: response,
        );
      }
    } on _CancelledByTokenException {
      return NapsTransactionResult(
        isSuccess: false,
        source: NapsResultSource.cancelled,
        responseCode: '',
        description: 'Payment cancelled by user',
        userMessage: 'Payment cancelled.',
      );
    } catch (e) {
      return NapsTransactionResult(
        isSuccess: false,
        source: NapsResultSource.sdkError,
        responseCode: '',
        description: 'SDK Exception occurred: $e',
        userMessage: 'Service temporarily unavailable.',
      );
    }
  }

  /// Races [connection.receive] against a [NapsCancelToken].
  /// Throws [_CancelledByTokenException] if the token fires first.
  Future<NapsMessage> _receiveWithCancel({
    required Duration timeout,
    required NapsCancelToken cancelToken,
  }) async {
    final receiveFuture = connection.receive(timeout: timeout);
    final cancelFuture = cancelToken.onCancel.then((_) => throw _CancelledByTokenException());

    // The first future to complete wins.
    return await Future.any<NapsMessage>([receiveFuture, cancelFuture]);
  }

  /// Sends a manual Payment Confirmation (TM 002) for a previously approved payment.
  /// This must be called within 40 seconds of receiving the payment response.
  Future<NapsTransactionResult> confirmPayment({
    required int amountInCents,
    required int sequenceNumber, // Must match the original payment request NS
    required String stan,
    required String cardMasked,
    required String expirationDate,
    String currencyCode = '504',
  }) async {
    final confirmRequest = NapsMessage.paymentConfirmationRequest(
      amountInCents: amountInCents,
      posId: posId,
      sequenceNumber: sequenceNumber,
      stan: stan,
      cardMasked: cardMasked,
      expirationDate: expirationDate,
      currencyCode: currencyCode,
    );

    try {
      await connection.send(confirmRequest);
      final response = await connection.receive(timeout: const Duration(seconds: 30));

      final metadata = NapsResponseCodes.lookup(response.responseCode);
      final customerReceipt = NapsReceipt.parse(response.receiptData);

      return NapsTransactionResult(
        isSuccess: metadata.isSuccess,
        source: NapsResultSource.terminal,
        responseCode: response.responseCode,
        description: metadata.description,
        userMessage: metadata.userMessage,
        stan: stan,
        cardNumber: cardMasked,
        customerReceipt: customerReceipt,
        confirmationResponse: response,
      );
    } catch (e) {
      return NapsTransactionResult(
        isSuccess: false,
        source: NapsResultSource.sdkError,
        responseCode: '',
        description: 'SDK Exception occurred during confirmation: $e',
        userMessage: 'Service temporarily unavailable.',
      );
    }
  }

  /// Step 1 of Cancellation: Query the XPOS server for the transaction to cancel.
  /// Returns transaction metadata (amount, date, time) to show to the cashier.
  Future<NapsCancellationInfo> initiateCancellation({
    required String stan,
  }) async {
    final seqNum = _getNextSequenceNumber();
    final request = NapsMessage.paymentCancellationRequest(
      posId: posId,
      sequenceNumber: seqNum,
      stan: stan,
    );

    try {
      await connection.send(request);
      final response = await connection.receive(timeout: const Duration(seconds: 30));

      final responseCode = response.responseCode;
      final metadata = NapsResponseCodes.lookup(responseCode);

      if (!metadata.isSuccess || response.messageType != '103') {
        return NapsCancellationInfo(
          isFound: false,
          source: NapsResultSource.terminal,
          responseCode: responseCode,
          userMessage: metadata.userMessage,
          sequenceNumber: seqNum,
          stan: stan,
          amountInCents: 0,
          currencyCode: '',
          transactionDate: '',
          transactionTime: '',
          cardNumber: '',
          expirationDate: '',
          originalResponse: response,
        );
      }

      return NapsCancellationInfo(
        isFound: true,
        source: NapsResultSource.terminal,
        responseCode: responseCode,
        userMessage: metadata.userMessage,
        sequenceNumber: seqNum,
        stan: stan,
        amountInCents: response.amountInCents ?? 0,
        currencyCode: response.currencyCode,
        transactionDate: response.transactionDate,
        transactionTime: response.transactionTime,
        cardNumber: response.cardNumber,
        expirationDate: response.cardExpirationDate,
        originalResponse: response,
      );
    } catch (e) {
      return NapsCancellationInfo(
        isFound: false,
        source: NapsResultSource.sdkError,
        responseCode: '',
        userMessage: 'SDK Exception: $e',
        sequenceNumber: seqNum,
        stan: stan,
        amountInCents: 0,
        currencyCode: '',
        transactionDate: '',
        transactionTime: '',
        cardNumber: '',
        expirationDate: '',
      );
    }
  }

  /// Step 2 of Cancellation: Confirm and execute the cancellation on the EPT.
  Future<NapsCancellationResult> confirmCancellation({
    required NapsCancellationInfo info,
  }) async {
    if (!info.isFound) {
      return NapsCancellationResult(
        isSuccess: false,
        source: info.source,
        responseCode: info.responseCode,
        userMessage: info.userMessage,
      );
    }

    final request = NapsMessage.cancellationConfirmationRequest(
      posId: posId,
      sequenceNumber: info.sequenceNumber, // Must be identical to the TM 003 sequence number
      stan: info.stan,
      amountInCents: info.amountInCents,
      currencyCode: info.currencyCode,
      transactionDate: info.transactionDate,
      transactionTime: info.transactionTime,
    );

    try {
      await connection.send(request);
      final response = await connection.receive(timeout: const Duration(seconds: 30));

      final responseCode = response.responseCode;
      final metadata = NapsResponseCodes.lookup(responseCode);

      // CR = 000 or 480 signifies cancellation completed
      final isSuccess = metadata.isSuccess || responseCode == '480';
      final receipt = NapsReceipt.parse(response.receiptData);

      return NapsCancellationResult(
        isSuccess: isSuccess,
        source: NapsResultSource.terminal,
        responseCode: responseCode,
        userMessage: isSuccess ? 'Cancellation completed.' : metadata.userMessage,
        cancellationReceipt: receipt,
        confirmationResponse: response,
      );
    } catch (e) {
      return NapsCancellationResult(
        isSuccess: false,
        source: NapsResultSource.sdkError,
        responseCode: '',
        userMessage: 'Service temporarily unavailable.',
      );
    }
  }

  /// Requests a reprint of a receipt (TM 008).
  /// If [stan] is null or "000000", EPT returns the duplicate of the last payment.
  Future<NapsMessage?> getDuplicate({String? stan}) async {
    try {
      final seqNum = _getNextSequenceNumber();
      final request = NapsMessage.duplicateRequest(
        posId: posId,
        sequenceNumber: seqNum,
        stan: stan,
      );

      await connection.send(request);
      final response = await connection.receive(timeout: const Duration(seconds: 30));

      final metadata = NapsResponseCodes.lookup(response.responseCode);
      if (metadata.isSuccess && response.receiptData.isNotEmpty) {
        return response;
      }
    } catch (_) {}
    return null;
  }

  /// Requests the end-of-day payment totals statement (TM 010).
  Future<NapsReceipt?> getTotals() async {
    try {
      final seqNum = _getNextSequenceNumber();
      final request = NapsMessage.totalsRequest(
        posId: posId,
        sequenceNumber: seqNum,
      );

      await connection.send(request);
      final response = await connection.receive(timeout: const Duration(seconds: 30));

      final metadata = NapsResponseCodes.lookup(response.responseCode);
      if (metadata.isSuccess && response.receiptData.isNotEmpty) {
        return NapsReceipt.parse(response.receiptData);
      }
    } catch (_) {}
    return null;
  }

  /// Requests a reset of the EPT parameters (TM 012).
  Future<bool> resetEpt() async {
    try {
      final seqNum = _getNextSequenceNumber();
      final request = NapsMessage.resetRequest(
        posId: posId,
        sequenceNumber: seqNum,
      );

      await connection.send(request);
      final response = await connection.receive(timeout: const Duration(seconds: 30));

      final metadata = NapsResponseCodes.lookup(response.responseCode);
      return metadata.isSuccess;
    } catch (_) {
      return false;
    }
  }

  /// Requests configuration ticket print information (TM 011).
  Future<NapsReceipt?> getPrintInfo({required String ticketType}) async {
    try {
      final seqNum = _getNextSequenceNumber();
      final request = NapsMessage.printInfoRequest(
        posId: posId,
        sequenceNumber: seqNum,
        ticketType: ticketType,
      );

      await connection.send(request);
      final response = await connection.receive(timeout: const Duration(seconds: 30));

      final metadata = NapsResponseCodes.lookup(response.responseCode);
      if (metadata.isSuccess && response.receiptData.isNotEmpty) {
        return NapsReceipt.parse(response.receiptData);
      }
    } catch (_) {}
    return null;
  }

  /// Requests order referencing / parameter loading (TM 013).
  /// Note: This operation can take up to 2 minutes or more depending on connection speed.
  Future<NapsReceipt?> referencingOrder({required String ticketType}) async {
    try {
      final seqNum = _getNextSequenceNumber();
      final request = NapsMessage.referencingRequest(
        posId: posId,
        sequenceNumber: seqNum,
        ticketType: ticketType,
      );

      await connection.send(request);
      final response = await connection.receive(timeout: const Duration(minutes: 3));

      final metadata = NapsResponseCodes.lookup(response.responseCode);
      if (metadata.isSuccess && response.receiptData.isNotEmpty) {
        return NapsReceipt.parse(response.receiptData);
      }
    } catch (_) {}
    return null;
  }
}

/// Internal exception used to signal cancellation via [NapsCancelToken].
/// Not exposed to callers — the SDK catches this and returns a
/// `source: NapsResultSource.cancelled` result.
class _CancelledByTokenException implements Exception {}
