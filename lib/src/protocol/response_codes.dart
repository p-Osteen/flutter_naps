enum NapsResponseStatus { approved, declined, error }

class NapsResponseMetadata {
  final String code;
  final NapsResponseStatus status;
  final String description;
  final String userMessage;

  const NapsResponseMetadata({
    required this.code,
    required this.status,
    required this.description,
    required this.userMessage,
  });

  bool get isSuccess => status == NapsResponseStatus.approved;
}

class NapsResponseCodes {
  /// Response codes defined in the NAPS Integration Guide §7.
  ///
  /// Success codes: 000, 001, 003, 007
  /// All other codes indicate failure.
  static const Map<String, NapsResponseMetadata> _codes = {
    // ── Success codes (§7.1) ──────────────────────────────────────────────
    '000': NapsResponseMetadata(
      code: '000',
      status: NapsResponseStatus.approved,
      description: 'Transaction approved',
      userMessage: 'Transaction approved.',
    ),
    '001': NapsResponseMetadata(
      code: '001',
      status: NapsResponseStatus.approved,
      description: 'Approved with identification',
      userMessage: 'Transaction approved.',
    ),
    '003': NapsResponseMetadata(
      code: '003',
      status: NapsResponseStatus.approved,
      description: 'Approved (VIP)',
      userMessage: 'Transaction approved.',
    ),
    '007': NapsResponseMetadata(
      code: '007',
      status: NapsResponseStatus.approved,
      description: 'Approved, microcircuit update',
      userMessage: 'Transaction approved.',
    ),

    // ── Common failure codes (§7.2) ───────────────────────────────────────
    '100': NapsResponseMetadata(
      code: '100',
      status: NapsResponseStatus.declined,
      description: 'Do not honor',
      userMessage: 'Transaction declined.',
    ),
    '101': NapsResponseMetadata(
      code: '101',
      status: NapsResponseStatus.declined,
      description: 'Expired card',
      userMessage: 'Card expired.',
    ),
    '106': NapsResponseMetadata(
      code: '106',
      status: NapsResponseStatus.declined,
      description: 'Number of PIN attempts exceeded',
      userMessage: 'Maximum PIN attempts exceeded.',
    ),
    '117': NapsResponseMetadata(
      code: '117',
      status: NapsResponseStatus.declined,
      description: 'Insufficient funds',
      userMessage: 'Insufficient balance.',
    ),
    '118': NapsResponseMetadata(
      code: '118',
      status: NapsResponseStatus.declined,
      description: 'Incorrect PIN',
      userMessage: 'Incorrect PIN.',
    ),
    '120': NapsResponseMetadata(
      code: '120',
      status: NapsResponseStatus.declined,
      description: 'Transaction not authorized to cardholder',
      userMessage: 'Transaction declined by the bank.',
    ),
    '121': NapsResponseMetadata(
      code: '121',
      status: NapsResponseStatus.declined,
      description: 'Transaction not allowed at terminal',
      userMessage: 'Transaction declined at this terminal.',
    ),
    '302': NapsResponseMetadata(
      code: '302',
      status: NapsResponseStatus.declined,
      description: 'Record not found',
      userMessage: 'Transaction not found.',
    ),
    '480': NapsResponseMetadata(
      code: '480',
      status: NapsResponseStatus.error,
      description: 'Cancellation already done',
      userMessage: 'This transaction has already been cancelled.',
    ),
    '482': NapsResponseMetadata(
      code: '482',
      status: NapsResponseStatus.declined,
      description: 'Transaction already cancelled',
      userMessage: 'Transaction already cancelled.',
    ),
    '700': NapsResponseMetadata(
      code: '700',
      status: NapsResponseStatus.error,
      description: 'POS not authorized by the center',
      userMessage: 'Terminal not authorized — contact support.',
    ),
    '800': NapsResponseMetadata(
      code: '800',
      status: NapsResponseStatus.error,
      description: 'Cut-off in progress',
      userMessage: 'Cut-off in progress, please retry.',
    ),
    '880': NapsResponseMetadata(
      code: '880',
      status: NapsResponseStatus.error,
      description: 'Connection not accepted',
      userMessage: 'Connection refused — check the network.',
    ),
    '909': NapsResponseMetadata(
      code: '909',
      status: NapsResponseStatus.error,
      description: 'System failure',
      userMessage: 'Service temporarily unavailable.',
    ),
    '992': NapsResponseMetadata(
      code: '992',
      status: NapsResponseStatus.error,
      description: 'Authorization server unreachable',
      userMessage: 'Service temporarily unavailable.',
    ),
    '993': NapsResponseMetadata(
      code: '993',
      status: NapsResponseStatus.error,
      description: 'Authorization server unreachable',
      userMessage: 'Service temporarily unavailable.',
    ),
  };

  /// True when this code has a documented meaning in the NAPS Integration
  /// Guide §7.
  ///
  /// NAPS confirmed in writing (KioskServe, 3 September 2026) that codes
  /// outside the documented cases must be "logged and returned as received by
  /// the terminal rather than assigned an assumed meaning at application
  /// level". Callers use this to tell the two apart rather than guessing.
  static bool isDocumented(String code) => _codes.containsKey(code);

  /// Looks up metadata for a response code.
  /// Per NAPS Integration Guide §7: "Code 000 (and its variants 001/003/007)
  /// always signifies success; any other code should be treated as a failure."
  ///
  /// Codes NOT in this map (e.g. 995, 280, 328) are **intentionally absent**
  /// because they are not documented in the NAPS Integration Guide §7. They
  /// have been observed in production terminal responses but have no official
  /// meaning from NAPS. The SDK treats them as generic `declined` via the
  /// fallback below. The app layer handles user-facing messages for these codes
  /// in `PaymentController._getMappedErrorMessage()`.
  static NapsResponseMetadata lookup(String code) {
    final metadata = _codes[code];
    if (metadata != null) {
      return metadata;
    }

    // Generic fallback for any response code not in the NAPS Integration Guide.
    return NapsResponseMetadata(
      code: code,
      status: NapsResponseStatus.declined,
      description: 'Transaction not completed',
      userMessage: 'Transaction not completed, please retry.',
    );
  }
}
