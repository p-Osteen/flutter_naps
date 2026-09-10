## 2.1.2

### Documentation & Dartdoc Score
* **Constructor Documentation**: Added explicit dartdoc comments to constructors across instantiable and abstract classes (`NapsCancelToken`, `NapsFrameBuffer`, `NapsConnection`, `NapsSequenceStore`), resolving missing constructor documentation warnings in `pana`.
* **Utility Constructors**: Added private constructors (`._()`) with doc comments to static utility classes (`NapsResponseCodes`, `NapsTlv`, `NapsLogRedactor`, `NapsPan`, `NapsSequence`) to prevent instantiation and achieve 100% dartdoc coverage.

## 2.1.1

### Documentation & Public API Coverage
* **100% Public Member Documentation**: Added comprehensive dartdoc comments (`///`) across all public symbols, constructors, models, enums, protocol encoders, and connection interfaces (achieving 100% Pana documentation score).
* **Hardware Integration Notice**: Clarified and emphasized in `README.md` that the package is designed exclusively for on-premise hardware-level integration with physical POS payment terminals (SUNMI P2) over local Wi-Fi or USB-C serial, rather than an in-app software payment gateway (such as Stripe or Razorpay).
* **Documentation References**: Cleaned up unescaped doc bracket references in `NapsMessage.posId` to ensure clean documentation compilation with zero warnings.
* **Linter Quality Assurance**: Added `public_member_api_docs` to `analysis_options.yaml` to enforce documentation standards for future contributions.

## 2.1.0

### Hardware Discovery
* **`NapsSerialConnection.availablePorts`**: Added static getter returning all available system serial and USB COM port names (e.g., `COM1`, `COM3`, `/dev/ttyUSB0`).
* **`NapsSerialConnection.availableDevices`**: Added static getter querying connected serial devices with rich hardware attributes (`name`, `description`, `manufacturer`, `vendorId`, `productId`).
* **`NapsSerialPortInfo`**: Introduced data class representing an enumerated serial/USB port on the host system.

### Example Application & Workbench
* **Modular Architecture**: Refactored monolithic example application into decoupled components (`pages/`, `widgets/`, `dialogs/`, `models/`, `constants/`).
* **Tab-Based Navigation**: Added a dark fintech Material 3 bottom navigation bar with 5 isolated tabs (Payment Desk, Receipt Studio, Admin Services, Wire Telemetry, Link Config).
* **USB Auto-Discovery Dropdown**: Link configuration dynamically detects and lists plugged-in USB terminals with rescan and manual entry options.
* **Locked Protocol Configuration**: Enforced fixed `4444` TCP Port and `0030007` POS Identifier (Tag 003 NCAI) as read-only fields with lock indicators.
* **Responsive Layout**: Resolved mobile AppBar overflow by implementing adaptive title text and compact action tooltips.
* **Comprehensive Documentation**: Added a full-featured `README.md` covering architecture, protocol reference, response codes, and setup workflows.

## 2.0.0

Conformance pass against the NAPS PAY SUNMI P2 M2M TLV v1.1 specification.
Contains breaking API changes; see README for the new shapes.

### Wire format (correctness)

* **Tag 010 is no longer truncated at 999 bytes.** LENGTH is a 3-character
  field, so the terminal saturates it and keeps writing. Every receipt was
  losing its last few lines. The true extent is now recovered from the DP
  structure.
* **DP is parsed by declared length, not by splitting on `*`.** Line text
  legitimately contains asterisks (masked PANs, rules of stars); splitting
  first fabricated one segment per asterisk and destroyed the real line.
* **TLV and DP LENGTH count characters (runes).** Confirmed against the NAPS
  v1.1 specification: LENGTH is a character count for the transmitted VALUE
  across all TLV tags and DP sub-tags. Counting bytes caused readers to stop
  short on non-ASCII characters, truncating French receipts at accented lines
  (e.g., `N° Commerçant`, `Opération réussie`).
* **Fields after the receipt DP terminator are captured.** The terminal can
  place tags—such as response code `013` (CR) or timestamps (`014`, `015`)—after
  the receipt. The parser now consumes trailing tags rather than halting at
  `?`, ensuring approved payments with trailing CRs are correctly recognized.
* **Partial frames are never delivered.** A NAPS frame carries no length
  prefix or delimiter. Completion is decided by the message envelope, the DP
  terminator, and detection of the next frame's tag `001` or settle window.
* **Raw socket chunks are no longer UTF-8 decoded.** A multi-byte character
  split across a TCP segment threw and tore down the connection
  mid-transaction.
* Back-to-back frames in one buffer no longer merge.
* Receipt line text is no longer trimmed; padding is how the terminal aligns
  a 24-column line.

### Transaction safety

* **`NapsResultSource.approvedNotConfirmed`** — an approval whose confirmation
  did not complete now returns the full payment context (NS, STAN, amount,
  masked PAN, expiry, merchant receipt) instead of a bare error. A non-000
  TM 102 is reported here too, rather than as a plain decline.
* **Strict NS correlation restored.** Validates that the terminal echoes the
  request sequence number (NS) per NAPS specification sections III.2.3.1–III.2.3.6.
* **`NapsSequenceStore`** — NS is now supplied by an injectable, persistable
  store. Previously an SDK constructed per transaction reissued the same NS
  every time.
* **`onApproved` is bounded** by `approvedCallbackTimeout` and its errors are
  reported on the result rather than thrown, so nothing a host does in the
  callback can delay or fail the confirmation of an approved card.
* `confirmationElapsed` and `confirmationWindowExceeded` expose the terminal's
  40-second budget.
* `NapsFailureReason` replaces string-matching on exception text.

### Diagnostics

* **`NapsFrameLog`** — connections emit the actual wire frame, as hex and as a
  TLV summary, with tags 007 (NCAR) and 016 (NPRT) masked before the callback
  can see them.
* **`NapsFrameLog.bufferedAfter`** — reports unconsumed buffer bytes when a
  frame is dispatched, distinguishing parser issues from network delays.
* Synthetic SDK conditions no longer masquerade as terminal response codes;
  a protocol mismatch reports `sdkError` with an empty CR.

### API changes

* `networkTest()`, `getDuplicate()`, `getTotals()`, `getPrintInfo()`,
  `referencingOrder()` and `resetEpt()` return `NapsOperationResult` instead
  of `bool`/`null`.
* `NapsConnection` gains `transportDescription`; connections take `onFrame`.
* `NapsReceipt.parseBytes` is the primary parser; `parse(String)` delegates.
* `TlvElement` exposes `byteLength` alongside `length` (character count).
* `NapsSdk` validates NCAI and exposes `NapsSdk.posIdIssue` for setup screens.
* Serial baud rate is configurable.


## 1.0.0

* Initial stable release of the NAPS Flutter SDK for SUNMI P2.
* Full support for TCP/IP and Serial connectivity.
* Implementation of M2M TLV protocol (Payment, Confirmation, Cancellation, Duplicates, Totals).
