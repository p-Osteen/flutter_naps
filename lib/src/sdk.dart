import 'dart:async';
import 'dart:io';

import 'cancel_token.dart';
import 'connection/connection.dart';
import 'protocol/message.dart';
import 'protocol/receipt.dart';
import 'protocol/redaction.dart';
import 'protocol/response_codes.dart';
import 'sequence.dart';

/// Indicates where a transaction result originated.
enum NapsResultSource {
  /// Result carries a real NAPS terminal response code.
  terminal,

  /// The terminal approved the payment (TM 101, CR 000) but the confirmation
  /// leg did not complete.
  ///
  /// This is neither a success nor a decline. The card has been debited, or is
  /// about to be auto-cancelled by the terminal at the end of its 40-second
  /// window, and the POS cannot tell which. Every field needed to reconcile —
  /// NS, STAN, amount, masked PAN, expiry, the merchant receipt — is present
  /// on the result. Persist them; never show the customer a plain decline.
  approvedNotConfirmed,

  /// Payment was cancelled by the user before the terminal responded.
  cancelled,

  /// An SDK-level error occurred (connection failure, timeout, bad frame).
  sdkError,
}

/// Why an operation failed, as a value rather than as prose.
///
/// Callers previously had to string-match on the exception text to tell a
/// timeout from a socket error.
enum NapsFailureReason {
  none,
  timeout,
  connectionLost,
  protocolMismatch,
  cancelledByUser,
  terminalDeclined,
  confirmationFailed,
  callbackFailed,
  unknown,
}

/// Result of a NAPS transaction attempt (payment or confirmation).
class NapsTransactionResult {
  final bool isSuccess;
  final NapsResultSource source;
  final String responseCode;
  final String description;
  final String userMessage;
  final NapsFailureReason failureReason;

  /// NS used for this transaction. Required to correlate a confirmation,
  /// a duplicate lookup or a manual reconciliation back to this payment.
  final int? sequenceNumber;

  final String? stan;
  final String? cardNumber;
  final String? cardholderName;
  final String? authorizationNumber; // Tag 009 — NA
  final String? cardExpirationDate; // Tag 017 — DAEX
  final String? cardEntryMode; // Tag 040 — EM
  final String? paymentType; // Tag 021 — TYPA
  final int? amountInCents; // Tag 002 — MT
  final String? currencyCode; // Tag 012 — DE
  final String? transactionDate; // Tag 014 — DA (from TM=101)
  final String? transactionTime; // Tag 015 — HE (from TM=101)
  final NapsReceipt? merchantReceipt;
  final NapsReceipt? customerReceipt;
  final NapsMessage? paymentResponse;
  final NapsMessage? confirmationResponse;

  /// CR returned by the confirmation leg, when one was received.
  final String? confirmationResponseCode;

  /// Time between receiving TM 101 and putting TM 002 on the wire.
  /// The terminal cancels the transaction if this exceeds 40 seconds.
  final Duration? confirmationElapsed;

  /// True when [confirmationElapsed] exceeded the terminal's window.
  final bool confirmationWindowExceeded;

  /// Error thrown by the `onApproved` callback, if any. Reported rather than
  /// rethrown so a printer fault cannot take down a completed payment.
  final Object? callbackError;

  NapsTransactionResult({
    required this.isSuccess,
    required this.source,
    required this.responseCode,
    required this.description,
    required this.userMessage,
    this.failureReason = NapsFailureReason.none,
    this.sequenceNumber,
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
    this.confirmationResponseCode,
    this.confirmationElapsed,
    this.confirmationWindowExceeded = false,
    this.callbackError,
  });

  /// [cardNumber] with the middle digits masked, in the same form the
  /// terminal prints on its own receipt.
  ///
  /// Use this for anything that leaves the payment path — storage, logs, an
  /// order payload, another system's API. [cardNumber] itself is the complete
  /// number the terminal returned in tag 007; it is required verbatim in
  /// TM 002 and must not be persisted or forwarded.
  String? get maskedCardNumber => NapsPan.mask(cardNumber);

  /// The last four digits of the card, for display.
  String? get cardLast4 => NapsPan.last4(cardNumber);

  /// Merchant number as printed on the receipt.
  ///
  /// The terminal returns no TLV field for this, but it identifies the
  /// merchant to the acquirer and is what reconciliation queries are made
  /// against, so it is worth keeping with the transaction.
  String? get merchantNumber => merchantReceipt?.merchantNumber;

  /// Terminal number as printed on the receipt. As above, receipt only.
  String? get terminalNumber => merchantReceipt?.terminalNumber;

  /// True when the card was approved, whether or not the confirmation landed.
  bool get wasApproved =>
      isSuccess || source == NapsResultSource.approvedNotConfirmed;

  /// True when the outcome is genuinely unknown and a human must reconcile.
  bool get requiresReconciliation =>
      source == NapsResultSource.approvedNotConfirmed;

  @override
  String toString() =>
      'NapsTransactionResult(success: $isSuccess, source: $source, code: $responseCode, '
      'reason: $failureReason, ns: $sequenceNumber, stan: $stan, '
      'confirmCode: $confirmationResponseCode, elapsed: $confirmationElapsed)';
}

/// Result of a non-payment operation (duplicate, totals, print, reset...).
///
/// Replaces the previous `null`-on-anything-went-wrong signature, which left
/// callers unable to tell "the terminal says no such transaction" from "the
/// socket died" — a distinction that decides whether a timed-out payment can
/// be treated as recovered.
class NapsOperationResult {
  final bool isSuccess;
  final NapsResultSource source;
  final String responseCode;
  final String description;
  final String userMessage;
  final NapsFailureReason failureReason;
  final NapsReceipt? receipt;
  final NapsMessage? response;

  const NapsOperationResult({
    required this.isSuccess,
    required this.source,
    required this.responseCode,
    required this.description,
    required this.userMessage,
    this.failureReason = NapsFailureReason.none,
    this.receipt,
    this.response,
  });

  factory NapsOperationResult.failure(
    NapsFailureReason reason,
    String description, {
    NapsResultSource source = NapsResultSource.sdkError,
    String responseCode = '',
  }) => NapsOperationResult(
    isSuccess: false,
    source: source,
    responseCode: responseCode,
    description: description,
    userMessage: 'The operation could not be completed.',
    failureReason: reason,
  );

  String? get stan => response?.stan;

  @override
  String toString() =>
      'NapsOperationResult(success: $isSuccess, source: $source, '
      'code: $responseCode, reason: $failureReason)';
}

/// Intermediate information retrieved from the terminal before a cancellation
/// is confirmed.
class NapsCancellationInfo {
  final bool isFound;
  final NapsResultSource source;
  final String responseCode;
  final String userMessage;
  final NapsFailureReason failureReason;
  final int sequenceNumber; // Reused verbatim in TM 004
  final String stan;
  final int amountInCents;
  final String currencyCode;
  final String transactionDate;
  final String transactionTime;
  final String cardNumber;
  final String expirationDate;
  final NapsMessage? originalResponse;

  /// [cardNumber] masked, for anything outside the protocol path.
  String? get maskedCardNumber => NapsPan.mask(cardNumber);

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
    this.failureReason = NapsFailureReason.none,
    this.originalResponse,
  });
}

/// Final result of a cancellation.
class NapsCancellationResult {
  final bool isSuccess;
  final NapsResultSource source;
  final String responseCode;
  final String userMessage;
  final NapsFailureReason failureReason;
  final NapsReceipt? cancellationReceipt;
  final NapsMessage? confirmationResponse;

  NapsCancellationResult({
    required this.isSuccess,
    required this.source,
    required this.responseCode,
    required this.userMessage,
    this.failureReason = NapsFailureReason.none,
    this.cancellationReceipt,
    this.confirmationResponse,
  });
}

/// Everything known about an approved payment, captured the moment TM 101
/// lands so that no later failure can lose it.
class _ApprovedPayment {
  final int sequenceNumber;
  final String responseCode;
  final NapsResponseMetadata metadata;
  final String stan;
  final String cardMasked;
  final String expirationDate;
  final String cardholder;
  final String authNumber;
  final String entryMode;
  final String paymentType;
  final int? amountInCents;
  final String currencyCode;
  final String date;
  final String time;
  final NapsReceipt merchantReceipt;
  final NapsMessage response;
  final DateTime approvedAt;

  _ApprovedPayment({
    required this.sequenceNumber,
    required this.responseCode,
    required this.metadata,
    required this.stan,
    required this.cardMasked,
    required this.expirationDate,
    required this.cardholder,
    required this.authNumber,
    required this.entryMode,
    required this.paymentType,
    required this.amountInCents,
    required this.currencyCode,
    required this.date,
    required this.time,
    required this.merchantReceipt,
    required this.response,
    required this.approvedAt,
  });

  NapsTransactionResult toResult({
    required bool isSuccess,
    required NapsResultSource source,
    String? responseCodeOverride,
    String? descriptionOverride,
    String? userMessageOverride,
    NapsFailureReason failureReason = NapsFailureReason.none,
    NapsReceipt? customerReceipt,
    NapsMessage? confirmationResponse,
    String? confirmationResponseCode,
    Duration? confirmationElapsed,
    bool confirmationWindowExceeded = false,
    Object? callbackError,
  }) => NapsTransactionResult(
    isSuccess: isSuccess,
    source: source,
    responseCode: responseCodeOverride ?? responseCode,
    description: descriptionOverride ?? metadata.description,
    userMessage: userMessageOverride ?? metadata.userMessage,
    failureReason: failureReason,
    sequenceNumber: sequenceNumber,
    stan: stan,
    cardNumber: cardMasked,
    cardholderName: cardholder,
    authorizationNumber: authNumber,
    cardExpirationDate: expirationDate,
    cardEntryMode: entryMode,
    paymentType: paymentType,
    amountInCents: amountInCents,
    currencyCode: currencyCode,
    transactionDate: date,
    transactionTime: time,
    merchantReceipt: merchantReceipt,
    customerReceipt: customerReceipt,
    paymentResponse: response,
    confirmationResponse: confirmationResponse,
    confirmationResponseCode: confirmationResponseCode,
    confirmationElapsed: confirmationElapsed,
    confirmationWindowExceeded: confirmationWindowExceeded,
    callbackError: callbackError,
  );
}

/// Interacts with a NAPS SUNMI P2 terminal over the M2M TLV protocol.
class NapsSdk {
  final NapsConnection connection;
  final String posId;

  /// Where NS comes from. Defaults to a non-persistent counter, which is fine
  /// for tests and wrong for a kiosk — pass a durable store in production.
  final NapsSequenceStore sequenceStore;

  /// How long the terminal waits for TM 002 before auto-cancelling
  /// (spec §III.2.3.2).
  final Duration confirmationWindow;

  /// Hard ceiling on the `onApproved` callback. Whatever the host does in
  /// there — printing, most likely — must not be able to push TM 002 past
  /// [confirmationWindow].
  final Duration approvedCallbackTimeout;

  /// How long to keep listening after the user cancels, in case the terminal
  /// had already approved the card and its answer is still in flight.
  ///
  /// Cancelling aborts *our wait*, not the terminal's transaction. Walking
  /// away the instant the button is pressed can therefore discard a real
  /// approval, leaving a card that was charged with no record of it anywhere.
  final Duration cancelGraceWindow;

  /// Default per-message timeout (spec §III.2.5).
  static const Duration defaultTimeout = Duration(seconds: 30);

  /// Timeout for messages that require a card read (spec §III.2.5).
  static const Duration cardReadTimeout = Duration(minutes: 2);

  NapsSdk({
    required this.connection,
    required this.posId,
    NapsSequenceStore? sequenceStore,
    int initialSequenceNumber = 0,
    this.confirmationWindow = const Duration(seconds: 40),
    this.approvedCallbackTimeout = const Duration(seconds: 10),
    this.cancelGraceWindow = const Duration(seconds: 3),
  }) : sequenceStore =
           sequenceStore ?? InMemoryNapsSequenceStore(initialSequenceNumber) {
    // An empty or non-numeric NCAI is a configuration bug the terminal cannot
    // recover from, so fail loudly. Length is not checked: the field is
    // left-padded when the frame is built, and refusing a value on length
    // alone would strand kiosks already configured that way.
    //
    // The condition must stay in step with [posIdIssue], which supplies the
    // message - a condition that rejects something posIdIssue accepts throws
    // an ArgumentError with a null message and no way to tell what was wrong.
    if (posIdIssue(posId) != null) {
      throw ArgumentError.value(posId, 'posId', posIdIssue(posId));
    }
  }

  static bool _isNumeric(String value) {
    for (var i = 0; i < value.length; i++) {
      final c = value.codeUnitAt(i);
      if (c < 0x30 || c > 0x39) return false;
    }
    return value.isNotEmpty;
  }

  /// Describes what is wrong with an NCAI value, or null when it is valid.
  ///
  /// Only two things make an NCAI unusable: it has to be present, and it has
  /// to be digits that fit the seven-character field on the wire. A shorter
  /// value is accepted and left-padded with zeroes when the frame is built
  /// (see [NapsMessage]), which is how the field is defined - so a value such
  /// as `12345` is a legitimate configuration and no longer reported here.
  static String? posIdIssue(String value) {
    if (value.isEmpty) return 'NCAI (POS ID) is required.';
    if (!_isNumeric(value)) return 'NCAI (POS ID) must contain digits only.';
    return null;
  }

  Future<int> _nextSequence() => sequenceStore.next();

  /// Validates that a response is the answer to the request just sent.
  bool _validateResponse(
    NapsMessage response,
    String expectedTm,
    int expectedNs,
  ) =>
      response.messageType == expectedTm &&
      response.sequenceNumber == expectedNs;

  NapsFailureReason _reasonFor(Object error) {
    if (error is TimeoutException) return NapsFailureReason.timeout;
    if (error is SocketException || error is IOException) {
      return NapsFailureReason.connectionLost;
    }
    if (error is FormatException) return NapsFailureReason.protocolMismatch;
    if (error is StateError) return NapsFailureReason.protocolMismatch;
    return NapsFailureReason.unknown;
  }

  /// Verifies the POS <-> EPT link with a Network Test message (TM 009).
  ///
  /// Unlike opening a socket, this proves the NAPS PAY application is running
  /// and answering, which is what guide §10.1.8 asks for at kiosk startup.
  Future<NapsOperationResult> networkTest() async {
    try {
      final seqNum = await _nextSequence();
      final request = NapsMessage.networkTestRequest(
        posId: posId,
        sequenceNumber: seqNum,
      );

      await connection.send(request);
      final response = await connection.receive(timeout: defaultTimeout);

      if (!_validateResponse(response, '109', seqNum)) {
        return NapsOperationResult.failure(
          NapsFailureReason.protocolMismatch,
          'Expected TM 109 and NS $seqNum, got TM ${response.messageType} '
          'and NS ${response.sequenceNumber}',
        );
      }

      final metadata = NapsResponseCodes.lookup(response.responseCode);
      return NapsOperationResult(
        isSuccess: metadata.isSuccess,
        source: NapsResultSource.terminal,
        responseCode: response.responseCode,
        description: metadata.description,
        userMessage: metadata.userMessage,
        failureReason: metadata.isSuccess
            ? NapsFailureReason.none
            : NapsFailureReason.terminalDeclined,
        response: response,
      );
    } catch (e) {
      return NapsOperationResult.failure(
        _reasonFor(e),
        'Network test failed: $e',
      );
    }
  }

  /// Executes a payment transaction (TM 001 -> 101, then TM 002 -> 102).
  ///
  /// If [autoConfirm] is true the confirmation is sent automatically, reusing
  /// the payment's NS as the specification requires.
  ///
  /// [onApproved] runs after the approval and before TM 002, for work that
  /// must happen while the transaction is still open. It is bounded by
  /// [approvedCallbackTimeout] and its failures are reported on the result
  /// rather than thrown, because nothing a host does in a callback should be
  /// able to delay or fail the confirmation of an approved card.
  ///
  /// Printing does not belong in [onApproved]. The merchant receipt is on the
  /// result either way, and a printer that is slow to enumerate will otherwise
  /// eat into the terminal's 40-second window.
  ///
  /// Once the terminal has approved, every return path carries the full
  /// payment context and is either a success or
  /// [NapsResultSource.approvedNotConfirmed] — never a bare error.
  Future<NapsTransactionResult> pay({
    required int amountInCents,
    String currencyCode = '504',
    bool autoConfirm = true,
    Future<void> Function(NapsTransactionResult intermediateResult)? onApproved,
    NapsCancelToken? cancelToken,
  }) async {
    final seqNum = await _nextSequence();

    // Cancelled before we even asked: never start a transaction the terminal
    // would then have to time out of.
    if (cancelToken != null && cancelToken.isCancelled) {
      return _cancelledResult(seqNum, detail: 'before TM 001 was sent');
    }

    // ── TM 001: payment request ──────────────────────────────────────────
    final _ReceiveOutcome outcome;
    try {
      final request = NapsMessage.paymentRequest(
        amountInCents: amountInCents,
        posId: posId,
        sequenceNumber: seqNum,
        currencyCode: currencyCode,
      );
      await connection.send(request);

      outcome = await _receiveRacingCancel(
        timeout: cardReadTimeout,
        cancelToken: cancelToken,
      );
    } catch (e) {
      // Nothing was approved: no card context exists to preserve.
      return NapsTransactionResult(
        isSuccess: false,
        source: NapsResultSource.sdkError,
        responseCode: '',
        description: 'Payment request failed: $e',
        userMessage:
            'The payment service is temporarily unavailable. Please ask for assistance.',
        failureReason: _reasonFor(e),
        sequenceNumber: seqNum,
      );
    }

    final response = outcome.message;

    // Cancelled, and nothing arrived in the grace window. The terminal has
    // been sent TM 001 but will receive no TM 002, so it reverses the
    // transaction itself after 40 seconds.
    if (response == null) {
      return _cancelledResult(seqNum);
    }

    if (!_validateResponse(response, '101', seqNum)) {
      if (outcome.cancelled) {
        return _cancelledResult(seqNum, detail: 'unmatched response discarded');
      }
      // A synthetic condition, so it must not masquerade as a terminal CR.
      return NapsTransactionResult(
        isSuccess: false,
        source: NapsResultSource.sdkError,
        responseCode: '',
        description:
            'Protocol mismatch: expected TM 101 and NS $seqNum, got TM '
            '${response.messageType} and NS ${response.sequenceNumber}',
        userMessage: 'The payment terminal is not responding correctly.',
        failureReason: NapsFailureReason.protocolMismatch,
        sequenceNumber: seqNum,
        paymentResponse: response,
      );
    }

    final metadata = NapsResponseCodes.lookup(response.responseCode);
    if (!metadata.isSuccess) {
      // The user asked to cancel and the card was refused anyway: nothing was
      // charged, so honour the intent rather than reporting a decline.
      if (outcome.cancelled) {
        return _cancelledResult(
          seqNum,
          detail: 'terminal returned CR ${response.responseCode}',
        );
      }
      return NapsTransactionResult(
        isSuccess: false,
        source: NapsResultSource.terminal,
        responseCode: response.responseCode,
        description: metadata.description,
        userMessage: metadata.userMessage,
        failureReason: NapsFailureReason.terminalDeclined,
        sequenceNumber: seqNum,
        amountInCents: response.amountInCents,
        currencyCode: response.currencyCode,
        transactionDate: response.dateStr,
        transactionTime: response.timeStr,
        paymentResponse: response,
      );
    }

    // ── Approved. Capture everything before anything else can fail. ──────
    final merchantReceipt = NapsReceipt.parseBytes(response.receiptDataBytes);

    // The terminal does not reliably return tag 009. On 3 September 2026 the
    // authorisation number appeared only on the printed receipt, so a POS
    // reading tag 009 alone stored nothing for it. Prefer the field, fall
    // back to the receipt.
    final authNumber = response.authorizationNumber.isNotEmpty
        ? response.authorizationNumber
        : (merchantReceipt.authorisationNumber ?? '');

    final approved = _ApprovedPayment(
      sequenceNumber: seqNum,
      responseCode: response.responseCode,
      metadata: metadata,
      stan: response.stan,
      cardMasked: response.cardNumber,
      expirationDate: response.cardExpirationDate,
      cardholder: response.cardholderName,
      authNumber: authNumber,
      entryMode: response.cardEntryMode,
      paymentType: response.paymentType,
      amountInCents: response.amountInCents,
      currencyCode: response.currencyCode,
      date: response.dateStr,
      time: response.timeStr,
      merchantReceipt: merchantReceipt,
      response: response,
      approvedAt: DateTime.now(),
    );

    // The card was approved after the user pressed cancel. Confirming now
    // would take their money against their instruction, so TM 002 is withheld
    // deliberately — that omission is what makes the terminal reverse the
    // transaction at the end of its 40-second window. It is still recorded as
    // an approval that was never confirmed, so the reversal can be verified.
    if (outcome.cancelled) {
      return approved.toResult(
        isSuccess: false,
        source: NapsResultSource.approvedNotConfirmed,
        failureReason: NapsFailureReason.cancelledByUser,
        descriptionOverride:
            'Card approved (CR ${approved.responseCode}, STAN ${approved.stan}) '
            'after the user cancelled. TM 002 withheld; the terminal reverses '
            'the transaction automatically after $confirmationWindow.',
        userMessageOverride:
            'Payment was cancelled. If your card was charged it will be '
            'reversed automatically — please ask a member of staff to check.',
      );
    }

    if (!autoConfirm) {
      return approved.toResult(
        isSuccess: true,
        source: NapsResultSource.terminal,
      );
    }

    // ── Optional host callback, hard-bounded ─────────────────────────────
    Object? callbackError;
    if (onApproved != null) {
      try {
        await onApproved(
          approved.toResult(isSuccess: true, source: NapsResultSource.terminal),
        ).timeout(approvedCallbackTimeout);
      } catch (e) {
        callbackError = e;
      }
    }

    // ── TM 002: confirmation, reusing the payment's NS ───────────────────
    return _confirm(
      approved,
      amountInCents: amountInCents,
      currencyCode: currencyCode,
      callbackError: callbackError,
    );
  }

  Future<NapsTransactionResult> _confirm(
    _ApprovedPayment approved, {
    required int amountInCents,
    required String currencyCode,
    Object? callbackError,
  }) async {
    final confirmRequest = NapsMessage.paymentConfirmationRequest(
      amountInCents: amountInCents,
      posId: posId,
      sequenceNumber: approved.sequenceNumber,
      stan: approved.stan,
      cardMasked: approved.cardMasked,
      expirationDate: approved.expirationDate,
      currencyCode: currencyCode,
    );

    Duration elapsed = Duration.zero;
    try {
      try {
        await connection.send(confirmRequest);
      } on IOException {
        if (!await connection.reconnect()) rethrow;
        await connection.send(confirmRequest);
      }
      elapsed = DateTime.now().difference(approved.approvedAt);

      final confirmResponse = await connection.receive(timeout: defaultTimeout);
      final exceeded = elapsed > confirmationWindow;

      if (!_validateResponse(confirmResponse, '102', approved.sequenceNumber)) {
        return approved.toResult(
          isSuccess: false,
          source: NapsResultSource.approvedNotConfirmed,
          descriptionOverride:
              'Card approved, but the confirmation response did not match: '
              'expected TM 102 and NS ${approved.sequenceNumber}, got TM '
              '${confirmResponse.messageType} and NS '
              '${confirmResponse.sequenceNumber}',
          userMessageOverride:
              'Payment status could not be confirmed. Please ask for assistance.',
          failureReason: NapsFailureReason.protocolMismatch,
          confirmationResponse: confirmResponse,
          confirmationElapsed: elapsed,
          confirmationWindowExceeded: exceeded,
          callbackError: callbackError,
        );
      }

      final confirmMetadata = NapsResponseCodes.lookup(
        confirmResponse.responseCode,
      );

      if (!confirmMetadata.isSuccess) {
        // The card was approved and the record was not written. 482 means the
        // terminal already cancelled it, 302 that it cannot find it. Either
        // way this is an unresolved transaction, not a refusal.
        return approved.toResult(
          isSuccess: false,
          source: NapsResultSource.approvedNotConfirmed,
          descriptionOverride:
              'Card approved (CR ${approved.responseCode}) but confirmation '
              'returned CR ${confirmResponse.responseCode}: '
              '${confirmMetadata.description}',
          userMessageOverride:
              'Payment status could not be confirmed. Please ask for assistance.',
          failureReason: NapsFailureReason.confirmationFailed,
          customerReceipt: NapsReceipt.parseBytes(
            confirmResponse.receiptDataBytes,
          ),
          confirmationResponse: confirmResponse,
          confirmationResponseCode: confirmResponse.responseCode,
          confirmationElapsed: elapsed,
          confirmationWindowExceeded: exceeded,
          callbackError: callbackError,
        );
      }

      return approved.toResult(
        isSuccess: true,
        source: NapsResultSource.terminal,
        responseCodeOverride: confirmResponse.responseCode,
        descriptionOverride: confirmMetadata.description,
        userMessageOverride: confirmMetadata.userMessage,
        failureReason: callbackError == null
            ? NapsFailureReason.none
            : NapsFailureReason.callbackFailed,
        customerReceipt: NapsReceipt.parseBytes(
          confirmResponse.receiptDataBytes,
        ),
        confirmationResponse: confirmResponse,
        confirmationResponseCode: confirmResponse.responseCode,
        confirmationElapsed: elapsed,
        confirmationWindowExceeded: exceeded,
        callbackError: callbackError,
      );
    } catch (e) {
      // The confirmation never completed. The approval still happened.
      return approved.toResult(
        isSuccess: false,
        source: NapsResultSource.approvedNotConfirmed,
        descriptionOverride:
            'Card approved (CR ${approved.responseCode}) but confirmation '
            'did not complete: $e',
        userMessageOverride:
            'Payment status could not be confirmed. Please ask for assistance.',
        failureReason: _reasonFor(e),
        confirmationElapsed: elapsed == Duration.zero ? null : elapsed,
        confirmationWindowExceeded: elapsed > confirmationWindow,
        callbackError: callbackError,
      );
    }
  }

  /// Races [connection.receive] against a [NapsCancelToken].
  ///
  /// On cancellation the pending receive is *not* abandoned: the terminal may
  /// already have approved the card and be milliseconds from answering, and
  /// that answer is the only evidence the approval ever happened.
  Future<_ReceiveOutcome> _receiveRacingCancel({
    required Duration timeout,
    required NapsCancelToken? cancelToken,
  }) async {
    final receiveFuture = connection.receive(timeout: timeout);

    if (cancelToken == null) {
      return _ReceiveOutcome(await receiveFuture, cancelled: false);
    }

    try {
      final message = await Future.any<NapsMessage>([
        receiveFuture,
        cancelToken.onCancel.then<NapsMessage>(
          (_) => throw _CancelledByTokenException(),
        ),
      ]);
      return _ReceiveOutcome(message, cancelled: false);
    } on _CancelledByTokenException {
      try {
        return _ReceiveOutcome(
          await receiveFuture.timeout(cancelGraceWindow),
          cancelled: true,
        );
      } catch (_) {
        return const _ReceiveOutcome(null, cancelled: true);
      }
    }
  }

  NapsTransactionResult _cancelledResult(int seqNum, {String? detail}) =>
      NapsTransactionResult(
        isSuccess: false,
        source: NapsResultSource.cancelled,
        responseCode: '',
        description: detail == null
            ? 'Payment cancelled by user'
            : 'Payment cancelled by user ($detail)',
        userMessage: 'Payment cancelled.',
        failureReason: NapsFailureReason.cancelledByUser,
        sequenceNumber: seqNum,
      );

  /// Sends a manual Payment Confirmation (TM 002) for a previously approved
  /// payment. Must reach the terminal within 40 seconds of the approval.
  Future<NapsTransactionResult> confirmPayment({
    required int amountInCents,
    required int sequenceNumber, // Must match the original TM 001 NS
    required String stan,
    required String cardMasked,
    required String expirationDate,
    String currencyCode = '504',
    DateTime? approvedAt,
  }) async {
    final approved = _ApprovedPayment(
      sequenceNumber: sequenceNumber,
      responseCode: '000',
      metadata: NapsResponseCodes.lookup('000'),
      stan: stan,
      cardMasked: cardMasked,
      expirationDate: expirationDate,
      cardholder: '',
      authNumber: '',
      entryMode: '',
      paymentType: '',
      amountInCents: amountInCents,
      currencyCode: currencyCode,
      date: '',
      time: '',
      merchantReceipt: NapsReceipt(const []),
      response: NapsMessage(const {}),
      approvedAt: approvedAt ?? DateTime.now(),
    );

    return _confirm(
      approved,
      amountInCents: amountInCents,
      currencyCode: currencyCode,
    );
  }

  /// Step 1 of cancellation (TM 003): ask the server for the transaction, so
  /// the cashier can confirm amount, date and time before it is reversed.
  Future<NapsCancellationInfo> initiateCancellation({
    required String stan,
  }) async {
    final seqNum = await _nextSequence();

    NapsCancellationInfo notFound(
      String code,
      String message,
      NapsFailureReason reason, {
      NapsResultSource source = NapsResultSource.terminal,
      NapsMessage? response,
    }) => NapsCancellationInfo(
      isFound: false,
      source: source,
      responseCode: code,
      userMessage: message,
      failureReason: reason,
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

    try {
      await connection.send(
        NapsMessage.paymentCancellationRequest(
          posId: posId,
          sequenceNumber: seqNum,
          stan: stan,
        ),
      );
      final response = await connection.receive(timeout: defaultTimeout);

      if (!_validateResponse(response, '103', seqNum)) {
        return notFound(
          '',
          'The payment terminal is not responding correctly.',
          NapsFailureReason.protocolMismatch,
          source: NapsResultSource.sdkError,
          response: response,
        );
      }

      final metadata = NapsResponseCodes.lookup(response.responseCode);
      if (!metadata.isSuccess) {
        return notFound(
          response.responseCode,
          metadata.userMessage,
          NapsFailureReason.terminalDeclined,
          response: response,
        );
      }

      return NapsCancellationInfo(
        isFound: true,
        source: NapsResultSource.terminal,
        responseCode: response.responseCode,
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
      return notFound(
        '',
        'The payment service is temporarily unavailable.',
        _reasonFor(e),
        source: NapsResultSource.sdkError,
      );
    }
  }

  /// Step 2 of cancellation (TM 004): execute it, reusing the TM 003 NS.
  Future<NapsCancellationResult> confirmCancellation({
    required NapsCancellationInfo info,
  }) async {
    if (!info.isFound) {
      return NapsCancellationResult(
        isSuccess: false,
        source: info.source,
        responseCode: info.responseCode,
        userMessage: info.userMessage,
        failureReason: info.failureReason,
      );
    }

    try {
      await connection.send(
        NapsMessage.cancellationConfirmationRequest(
          posId: posId,
          sequenceNumber: info.sequenceNumber,
          stan: info.stan,
          amountInCents: info.amountInCents,
          currencyCode: info.currencyCode,
          transactionDate: info.transactionDate,
          transactionTime: info.transactionTime,
        ),
      );
      final response = await connection.receive(timeout: defaultTimeout);

      if (!_validateResponse(response, '104', info.sequenceNumber)) {
        return NapsCancellationResult(
          isSuccess: false,
          source: NapsResultSource.sdkError,
          responseCode: '',
          userMessage: 'The payment terminal is not responding correctly.',
          failureReason: NapsFailureReason.protocolMismatch,
          confirmationResponse: response,
        );
      }

      final responseCode = response.responseCode;
      final metadata = NapsResponseCodes.lookup(responseCode);
      // Spec TM 104: CR 480 (or 000) means the cancellation was performed.
      final isSuccess = metadata.isSuccess || responseCode == '480';

      return NapsCancellationResult(
        isSuccess: isSuccess,
        source: NapsResultSource.terminal,
        responseCode: responseCode,
        userMessage: isSuccess
            ? 'Cancellation completed.'
            : metadata.userMessage,
        failureReason: isSuccess
            ? NapsFailureReason.none
            : NapsFailureReason.terminalDeclined,
        cancellationReceipt: NapsReceipt.parseBytes(response.receiptDataBytes),
        confirmationResponse: response,
      );
    } catch (e) {
      return NapsCancellationResult(
        isSuccess: false,
        source: NapsResultSource.sdkError,
        responseCode: '',
        userMessage:
            'The payment service is temporarily unavailable. Please ask for assistance.',
        failureReason: _reasonFor(e),
      );
    }
  }

  /// Requests a receipt reprint (TM 008).
  ///
  /// With no [stan] the terminal returns its **latest** record, which is not
  /// necessarily this POS's last transaction. Callers reconciling an
  /// ambiguous payment must correlate the answer before trusting it.
  Future<NapsOperationResult> getDuplicate({String? stan}) => _receiptOperation(
    expectedTm: '108',
    build: (seq) => NapsMessage.duplicateRequest(
      posId: posId,
      sequenceNumber: seq,
      stan: stan,
    ),
  );

  /// Requests the day's payment totals (TM 010).
  Future<NapsOperationResult> getTotals() => _receiptOperation(
    expectedTm: '110',
    build: (seq) =>
        NapsMessage.totalsRequest(posId: posId, sequenceNumber: seq),
  );

  /// Requests a configuration ticket (TM 011).
  Future<NapsOperationResult> getPrintInfo({required String ticketType}) =>
      _receiptOperation(
        expectedTm: '111',
        build: (seq) => NapsMessage.printInfoRequest(
          posId: posId,
          sequenceNumber: seq,
          ticketType: ticketType,
        ),
      );

  /// Requests parameter loading / referencing (TM 013). Setup only; the
  /// terminal can take longer than the usual card-read timeout to answer.
  Future<NapsOperationResult> referencingOrder({required String ticketType}) =>
      _receiptOperation(
        expectedTm: '113',
        timeout: const Duration(minutes: 3),
        build: (seq) => NapsMessage.referencingRequest(
          posId: posId,
          sequenceNumber: seq,
          ticketType: ticketType,
        ),
      );

  /// Requests an EPT parameter reset (TM 012).
  Future<NapsOperationResult> resetEpt() => _receiptOperation(
    expectedTm: '112',
    requireReceipt: false,
    build: (seq) => NapsMessage.resetRequest(posId: posId, sequenceNumber: seq),
  );

  Future<NapsOperationResult> _receiptOperation({
    required String expectedTm,
    required NapsMessage Function(int sequenceNumber) build,
    Duration timeout = defaultTimeout,
    bool requireReceipt = true,
  }) async {
    try {
      final seqNum = await _nextSequence();
      await connection.send(build(seqNum));
      final response = await connection.receive(timeout: timeout);

      if (!_validateResponse(response, expectedTm, seqNum)) {
        return NapsOperationResult.failure(
          NapsFailureReason.protocolMismatch,
          'Expected TM $expectedTm and NS $seqNum, got TM '
          '${response.messageType} and NS ${response.sequenceNumber}',
        );
      }

      final metadata = NapsResponseCodes.lookup(response.responseCode);
      if (!metadata.isSuccess) {
        return NapsOperationResult(
          isSuccess: false,
          source: NapsResultSource.terminal,
          responseCode: response.responseCode,
          description: metadata.description,
          userMessage: metadata.userMessage,
          failureReason: NapsFailureReason.terminalDeclined,
          response: response,
        );
      }

      if (requireReceipt && !response.hasReceipt) {
        return NapsOperationResult(
          isSuccess: false,
          source: NapsResultSource.terminal,
          responseCode: response.responseCode,
          description:
              'TM $expectedTm returned CR ${response.responseCode} '
              'but carried no printable data',
          userMessage: 'No receipt was returned.',
          failureReason: NapsFailureReason.protocolMismatch,
          response: response,
        );
      }

      return NapsOperationResult(
        isSuccess: true,
        source: NapsResultSource.terminal,
        responseCode: response.responseCode,
        description: metadata.description,
        userMessage: metadata.userMessage,
        receipt: response.hasReceipt
            ? NapsReceipt.parseBytes(response.receiptDataBytes)
            : null,
        response: response,
      );
    } catch (e) {
      return NapsOperationResult.failure(
        _reasonFor(e),
        'TM $expectedTm failed: $e',
      );
    }
  }
}

/// Internal exception used to signal cancellation via [NapsCancelToken].
class _CancelledByTokenException implements Exception {}

/// What came back from racing a receive against the cancel token.
class _ReceiveOutcome {
  /// The terminal's response, if one arrived at all.
  final NapsMessage? message;

  /// True when the user cancelled — whether or not [message] then arrived.
  final bool cancelled;

  const _ReceiveOutcome(this.message, {required this.cancelled});
}
