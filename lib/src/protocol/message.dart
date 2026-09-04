import 'dart:convert';
import 'dart:typed_data';

import 'tlv.dart';

class NapsMessage {
  final Map<String, TlvElement> elements;

  /// True when the DP field was closed by the end of the buffer rather than by
  /// its `?` terminator, i.e. the receipt is known to be short.
  final bool dpTruncated;

  /// The bytes this message was decoded from, when it came off the wire.
  /// Retained so diagnostics can log what actually arrived rather than a
  /// re-encoding of what was understood.
  final Uint8List? rawFrame;

  NapsMessage(this.elements, {this.dpTruncated = false, this.rawFrame});

  /// Creates a [NapsMessage] from a list of TLV elements.
  factory NapsMessage.fromElements(
    List<TlvElement> list, {
    bool dpTruncated = false,
    Uint8List? rawFrame,
  }) {
    final map = <String, TlvElement>{};
    for (final elem in list) {
      map[elem.tag] = elem;
    }
    return NapsMessage(map, dpTruncated: dpTruncated, rawFrame: rawFrame);
  }

  /// Builds a [NapsMessage] from a completed frame scan.
  factory NapsMessage.fromScan(NapsFrameScan scan, Uint8List rawFrame) =>
      NapsMessage.fromElements(
        scan.elements,
        dpTruncated: scan.dpTruncated,
        rawFrame: rawFrame,
      );

  /// Parses a raw TLV frame held as a string.
  ///
  /// Prefer [NapsMessage.fromScan] for anything that came off the wire: TLV
  /// lengths are byte counts and receipt text is accented, so decoding to a
  /// string before measuring shifts every offset after the first accent.
  factory NapsMessage.fromFrame(String frame) {
    final bytes = Uint8List.fromList(utf8.encode(frame));
    final scan = NapsTlv.scanFrame(bytes);
    if (scan.status == NapsScanStatus.malformed) {
      return NapsMessage(const {});
    }
    return NapsMessage.fromElements(
      scan.elements,
      dpTruncated: scan.dpTruncated,
      rawFrame: bytes,
    );
  }

  /// Encodes this message into a raw TLV frame.
  ///
  /// Only ever call this on a message you built. Calling it on a *response*
  /// re-encodes what was understood rather than what arrived, and the
  /// mandatory-field check below will throw on a response that legitimately
  /// omits DA or HE. Use [rawFrame] to see what the terminal actually sent.
  String toFrame() {
    validateMandatoryFields();
    // Return sorted elements by tag for consistency, though order doesn't matter
    final sortedList = elements.values.toList()
      ..sort((a, b) => a.tag.compareTo(b.tag));
    return NapsTlv.encode(sortedList);
  }

  /// The bytes to put on the wire.
  Uint8List toFrameBytes() => Uint8List.fromList(utf8.encode(toFrame()));

  /// Validates that the 5 mandatory fields are present: TM, NCAI, NS, DA, HE.
  void validateMandatoryFields() {
    const mandatoryTags = {
      '001': 'TM (Message Type)',
      '003': 'NCAI (POS Identifier)',
      '004': 'NS (Sequence Number)',
      '014': 'DA (Date)',
      '015': 'HE (Time)',
    };

    for (final entry in mandatoryTags.entries) {
      if (!elements.containsKey(entry.key)) {
        throw FormatException(
          'Missing mandatory NAPS field: ${entry.value} (Tag ${entry.key})',
        );
      }
    }
  }

  // --- Helper Getters and Seters for standard tags ---

  /// TM (Tag 001) - Message type (e.g. "001", "101")
  String get messageType => elements['001']?.value ?? '';

  /// MT (Tag 002) - Payment amount in cents (12 chars, e.g. "000000000200")
  int? get amountInCents {
    final val = elements['002']?.value;
    return val != null ? int.tryParse(val) : null;
  }

  /// NCAI (Tag 003) - POS identifier (7 chars: POS number [2] + cashier station number [5])
  String get posId => elements['003']?.value ?? '';

  /// NS (Tag 004) - Sequence number (6 chars, e.g. "159159")
  int? get sequenceNumber {
    final val = elements['004']?.value;
    return val != null ? int.tryParse(val) : null;
  }

  /// NSA (Tag 005) - Sequence number to cancel (6 chars)
  int? get sequenceNumberToCancel {
    final val = elements['005']?.value;
    return val != null ? int.tryParse(val) : null;
  }

  /// NHC (Tag 006) - Cashier station number (2 chars)
  String get cashierStationNumber => elements['006']?.value ?? '';

  /// NCAR (Tag 007) - Bank card number (16 to 19 chars, masked in response)
  String get cardNumber => elements['007']?.value ?? '';

  /// STAN (Tag 008) - System Trace Audit Number (6 chars)
  String get stan => elements['008']?.value ?? '';

  /// NA (Tag 009) - Bank authorization number (6 chars)
  String get authorizationNumber => elements['009']?.value ?? '';

  /// DP (Tag 010) - Printable receipt data.
  ///
  /// Prefer [receiptDataBytes]: DP sub-tag lengths are byte counts.
  String get receiptData => elements['010']?.value ?? '';

  /// DP (Tag 010) as the bytes the terminal sent.
  Uint8List get receiptDataBytes => elements['010']?.valueBytes ?? Uint8List(0);

  /// True when tag 010 is present and non-empty.
  bool get hasReceipt => receiptDataBytes.isNotEmpty;

  /// CB (Tag 011) - Barcode
  String get barcode => elements['011']?.value ?? '';

  /// DE (Tag 012) - Currency code (3 chars, e.g. "504" = MAD)
  String get currencyCode => elements['012']?.value ?? '';

  /// CR (Tag 013) - Response code (3 chars, e.g. "000" = approved)
  String get responseCode => elements['013']?.value ?? '';

  /// DA (Tag 014) - Exchange date, format DDMMYYYY
  String get dateStr => elements['014']?.value ?? '';

  /// HE (Tag 015) - Exchange time, format HHMMSS
  String get timeStr => elements['015']?.value ?? '';

  /// NPRT (Tag 016) - Cardholder name
  String get cardholderName => elements['016']?.value ?? '';

  /// DAEX (Tag 017) - Card expiration date, format YYMM
  String get cardExpirationDate => elements['017']?.value ?? '';

  /// DATR (Tag 018) - Transaction date, format DDMMYYYY
  String get transactionDate => elements['018']?.value ?? '';

  /// HETR (Tag 019) - Transaction time, format HHMMSS
  String get transactionTime => elements['019']?.value ?? '';

  /// TIDE (Tag 020) - Ticket requested for printing (e.g. "01")
  String get ticketRequested => elements['020']?.value ?? '';

  /// TYPA (Tag 021) - Payment type string (e.g. "PREPAID", "DEBIT")
  String get paymentType => elements['021']?.value ?? '';

  /// EM (Tag 040) - Card entry mode (CC = contact, SC = contactless)
  String get cardEntryMode => elements['040']?.value ?? '';

  // --- Factory Builders for Request Messages ---

  /// Helper to create base elements map with mandatory tags
  static Map<String, TlvElement> _createBaseElements({
    required String messageType,
    required String posId,
    required int sequenceNumber,
    required DateTime timestamp,
  }) {
    final dateVal = _formatDate(timestamp);
    final timeVal = _formatTime(timestamp);

    return {
      '001': TlvElement('001', messageType.padLeft(3, '0')),
      '003': TlvElement('003', posId.padLeft(7, '0')),
      '004': TlvElement('004', sequenceNumber.toString().padLeft(6, '0')),
      '014': TlvElement('014', dateVal),
      '015': TlvElement('015', timeVal),
    };
  }

  /// Formats Date as DDMMYYYY
  static String _formatDate(DateTime dt) {
    final d = dt.day.toString().padLeft(2, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final y = dt.year.toString().padLeft(4, '0');
    return '$d$m$y';
  }

  /// Formats Time as HHMMSS
  static String _formatTime(DateTime dt) {
    final h = dt.hour.toString().padLeft(2, '0');
    final m = dt.minute.toString().padLeft(2, '0');
    final s = dt.second.toString().padLeft(2, '0');
    return '$h$m$s';
  }

  /// TM 001 - Payment Request
  factory NapsMessage.paymentRequest({
    required int amountInCents,
    required String posId,
    required int sequenceNumber,
    String currencyCode = '504', // MAD default
    int? sequenceNumberToCancel,
    DateTime? timestamp,
  }) {
    final elements = _createBaseElements(
      messageType: '001',
      posId: posId,
      sequenceNumber: sequenceNumber,
      timestamp: timestamp ?? DateTime.now(),
    );

    elements['002'] = TlvElement(
      '002',
      amountInCents.toString().padLeft(12, '0'),
    );
    elements['012'] = TlvElement('012', currencyCode.padLeft(3, '0'));

    if (sequenceNumberToCancel != null) {
      elements['005'] = TlvElement(
        '005',
        sequenceNumberToCancel.toString().padLeft(6, '0'),
      );
    }

    return NapsMessage(elements);
  }

  /// TM 002 - Payment Confirmation Request
  factory NapsMessage.paymentConfirmationRequest({
    required int amountInCents,
    required String posId,
    required int sequenceNumber,
    required String stan,
    required String cardMasked,
    required String expirationDate,
    String currencyCode = '504',
    DateTime? timestamp,
  }) {
    final elements = _createBaseElements(
      messageType: '002',
      posId: posId,
      sequenceNumber:
          sequenceNumber, // Must be identical to the NS of the payment request
      timestamp: timestamp ?? DateTime.now(),
    );

    elements['002'] = TlvElement(
      '002',
      amountInCents.toString().padLeft(12, '0'),
    );
    elements['012'] = TlvElement('012', currencyCode.padLeft(3, '0'));
    elements['008'] = TlvElement('008', stan.padLeft(6, '0'));
    elements['007'] = TlvElement('007', cardMasked);
    elements['017'] = TlvElement('017', expirationDate.padLeft(4, '0'));

    return NapsMessage(elements);
  }

  /// TM 003 - Payment Cancellation Request
  factory NapsMessage.paymentCancellationRequest({
    required String posId,
    required int sequenceNumber,
    required String stan,
    DateTime? timestamp,
  }) {
    final elements = _createBaseElements(
      messageType: '003',
      posId: posId,
      sequenceNumber: sequenceNumber,
      timestamp: timestamp ?? DateTime.now(),
    );

    elements['008'] = TlvElement('008', stan.padLeft(6, '0'));

    return NapsMessage(elements);
  }

  /// TM 004 - Cancellation Confirmation Request
  factory NapsMessage.cancellationConfirmationRequest({
    required String posId,
    required int
    sequenceNumber, // Identical to the NS of the cancellation request (TM 003)
    required String stan,
    required int amountInCents,
    required String currencyCode,
    required String transactionDate,
    required String transactionTime,
    DateTime? timestamp,
  }) {
    final elements = _createBaseElements(
      messageType: '004',
      posId: posId,
      sequenceNumber: sequenceNumber,
      timestamp: timestamp ?? DateTime.now(),
    );

    elements['008'] = TlvElement('008', stan.padLeft(6, '0'));
    elements['002'] = TlvElement(
      '002',
      amountInCents.toString().padLeft(12, '0'),
    );
    elements['012'] = TlvElement('012', currencyCode.padLeft(3, '0'));
    elements['018'] = TlvElement('018', transactionDate);
    elements['019'] = TlvElement('019', transactionTime);

    return NapsMessage(elements);
  }

  /// TM 008 - Duplicate Request (Receipt Reprint)
  factory NapsMessage.duplicateRequest({
    required String posId,
    required int sequenceNumber,
    String? stan, // If null or "000000" => duplicate of last payment
    DateTime? timestamp,
  }) {
    final elements = _createBaseElements(
      messageType: '008',
      posId: posId,
      sequenceNumber: sequenceNumber,
      timestamp: timestamp ?? DateTime.now(),
    );

    elements['008'] = TlvElement('008', (stan ?? '000000').padLeft(6, '0'));

    return NapsMessage(elements);
  }

  /// TM 009 - Network Test Request
  factory NapsMessage.networkTestRequest({
    required String posId,
    required int sequenceNumber,
    DateTime? timestamp,
  }) {
    return NapsMessage(
      _createBaseElements(
        messageType: '009',
        posId: posId,
        sequenceNumber: sequenceNumber,
        timestamp: timestamp ?? DateTime.now(),
      ),
    );
  }

  /// TM 010 - Payment Totals Statement Request
  factory NapsMessage.totalsRequest({
    required String posId,
    required int sequenceNumber,
    DateTime? timestamp,
  }) {
    return NapsMessage(
      _createBaseElements(
        messageType: '010',
        posId: posId,
        sequenceNumber: sequenceNumber,
        timestamp: timestamp ?? DateTime.now(),
      ),
    );
  }

  /// TM 011 - Print Information Request
  factory NapsMessage.printInfoRequest({
    required String posId,
    required int sequenceNumber,
    required String ticketType, // e.g. "01"
    DateTime? timestamp,
  }) {
    final elements = _createBaseElements(
      messageType: '011',
      posId: posId,
      sequenceNumber: sequenceNumber,
      timestamp: timestamp ?? DateTime.now(),
    );

    elements['020'] = TlvElement('020', ticketType.padLeft(2, '0'));

    return NapsMessage(elements);
  }

  /// TM 012 - EPT Reset Request
  factory NapsMessage.resetRequest({
    required String posId,
    required int sequenceNumber,
    DateTime? timestamp,
  }) {
    return NapsMessage(
      _createBaseElements(
        messageType: '012',
        posId: posId,
        sequenceNumber: sequenceNumber,
        timestamp: timestamp ?? DateTime.now(),
      ),
    );
  }

  /// TM 013 - Referencing Order Request (Merchant Parameters Load)
  factory NapsMessage.referencingRequest({
    required String posId,
    required int sequenceNumber,
    required String ticketType,
    DateTime? timestamp,
  }) {
    final elements = _createBaseElements(
      messageType: '013',
      posId: posId,
      sequenceNumber: sequenceNumber,
      timestamp: timestamp ?? DateTime.now(),
    );

    elements['020'] = TlvElement('020', ticketType.padLeft(2, '0'));

    return NapsMessage(elements);
  }
}
