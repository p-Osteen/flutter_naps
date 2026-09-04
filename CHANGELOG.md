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
* **All framing and length arithmetic moved to bytes.** TLV LENGTH counts
  bytes; Dart string indices are UTF-16 code units, so every accent in the
  French receipt text shifted subsequent offsets.
* **Raw socket chunks are no longer UTF-8 decoded.** A multi-byte character
  split across a TCP segment threw and tore down the connection
  mid-transaction.
* **Partial frames are never delivered.** A NAPS frame carries no length
  prefix or delimiter, so "every buffered byte parsed" is not "the message is
  complete". Completion is now decided by the message envelope plus the DP
  terminator, with a short settle for undelimited responses.
* Back-to-back frames in one buffer no longer merge.
* Receipt line text is no longer trimmed; padding is how the terminal aligns
  a 24-column line.

### Transaction safety

* **`NapsResultSource.approvedNotConfirmed`** — an approval whose confirmation
  did not complete now returns the full payment context (NS, STAN, amount,
  masked PAN, expiry, merchant receipt) instead of a bare error. A non-000
  TM 102 is reported here too, rather than as a plain decline.
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
* Synthetic SDK conditions no longer masquerade as terminal response codes;
  a protocol mismatch reports `sdkError` with an empty CR.

### API changes

* `networkTest()`, `getDuplicate()`, `getTotals()`, `getPrintInfo()`,
  `referencingOrder()` and `resetEpt()` return `NapsOperationResult` instead
  of `bool`/`null`.
* `NapsConnection` gains `transportDescription`; connections take `onFrame`.
* `NapsReceipt.parseBytes` is the primary parser; `parse(String)` delegates.
* `NapsSdk` validates NCAI and exposes `NapsSdk.posIdIssue` for setup screens.
* Serial baud rate is configurable.

## 1.0.0

* Initial stable release of the NAPS Flutter SDK for SUNMI P2.
* Full support for TCP/IP and Serial connectivity.
* Implementation of M2M TLV protocol (Payment, Confirmation, Cancellation, Duplicates, Totals).
