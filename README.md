# NAPS Flutter SDK

This Flutter package connects your application to a SUNMI P2 payment terminal. It uses the M2M TLV protocol over a TCP/IP or Serial connection.

## Features

* **Connections**: Connect to a SUNMI P2 terminal by Wi-Fi (TCP/IP socket on port 4444) or by USB (Serial COM port).
* **Payments**: Start a payment and receive the terminal response.
* **Confirm and Cancel**: Confirm an approved payment. You can also cancel a payment manually from your POS application.
* **Duplicate Receipts**: Get a duplicate receipt with the transaction STAN.
* **Totals**: Get the statement of daily payment totals from the terminal.

## Getting Started

To use this package, you must put your POS device and the SUNMI P2 terminal on the same local network (for Wi-Fi). You can also connect them by USB Type-C.

### Wi-Fi Configuration
1. Open the SUNMI P2 terminal settings.
2. Open **About device** and read the IP address of the terminal.
3. The terminal listens on port `4444` by default.

## Usage

`pay()` runs the whole transaction: TM 001 out, TM 101 back, then TM 002 with
the **same NS**, as the specification requires. Do not call `confirmPayment()`
afterwards — that would confirm twice.

```dart
import 'package:naps_flutter/naps_flutter.dart';

final connection = NapsTcpConnection(
  host: '192.168.1.26',
  port: 4444,
  // Every frame in and out, with cardholder tags already masked.
  onFrame: (frame) => myLogger.log('$frame'),
);

final sdk = NapsSdk(
  connection: connection,
  posId: '0100001',            // NCAI: POS number (2) + cashier station (5)
  sequenceStore: myStore,      // see "Sequence numbers" below
);

if (!await connection.connect()) return;

final result = await sdk.pay(amountInCents: 3500, currencyCode: '504');

if (result.isSuccess) {
  // Approved and recorded. Print both copies now.
  printReceipt(result.merchantReceipt);
  printReceipt(result.customerReceipt);
} else if (result.requiresReconciliation) {
  // The card was approved but the confirmation did not complete. This is NOT
  // a decline: the money may have moved. Persist the context and get a human
  // to settle it against the NAPS batch. Never offer a retry here.
  await recordForReconciliation(
    ns: result.sequenceNumber,
    stan: result.stan,
    paymentCode: result.responseCode,
    confirmationCode: result.confirmationResponseCode,
  );
} else {
  showMessage(result.userMessage);   // declined, cancelled or unreachable
}
```

### Three outcomes, not two

`pay()` returns one of three things, and collapsing them into success/failure
is how a POS ends up billing a customer twice:

| `source`                | Meaning | What to do |
| --- | --- | --- |
| `terminal` + `isSuccess` | Approved and confirmed. | Complete the order. |
| `approvedNotConfirmed`   | Card approved, TM 002/102 did not complete. | Reconcile by hand. Do not retry. |
| `terminal` (not success) | Terminal refused the card. | Show the message; a retry is safe. |
| `cancelled` / `sdkError` | Nothing was approved. | Retry is safe, but see below. |

An `sdkError` with `failureReason == NapsFailureReason.timeout` is ambiguous,
not failed: the terminal may have approved a card whose response never
arrived. Use `getDuplicate()` to investigate, and correlate the answer on
STAN **and** timestamp **and** amount before treating it as this transaction.
With no STAN the terminal returns its own latest record, which at a busy
kiosk is frequently somebody else's payment.

### Sequence numbers

NS must advance across transactions, restarts and power cuts — not just
within one transaction. Back it with durable storage:

```dart
final store = CallbackNapsSequenceStore(
  read: () async => prefs.getInt('naps_ns'),
  write: (value) async => prefs.setInt('naps_ns', value),
);
```

`InMemoryNapsSequenceStore` is the default and is only correct for tests: an
SDK constructed per transaction with an in-memory store issues the same NS
every time.

### The 40-second window

The terminal cancels the transaction if TM 002 does not reach it within 40
seconds of the approval. Nothing slow belongs between the two — in particular
**do not print from `onApproved`**: a thermal printer that has to enumerate
USB, connect and stream a receipt can eat the whole budget. Receipts are on
the result; print after `pay()` returns. `onApproved` exists for work that
genuinely must happen while the transaction is open, and it is bounded by
`approvedCallbackTimeout` (default 10s) for that reason.

`result.confirmationElapsed` and `result.confirmationWindowExceeded` report
what actually happened, so the window can be monitored in production.

### Receipts (tag 010)

Receipt data is parsed from bytes, driven by the declared sub-tag lengths.
Two things about the wire format matter:

* **DP is often longer than its own LENGTH field.** LENGTH is three
  characters, so it saturates at 999 and the terminal keeps writing. The SDK
  recovers the true extent from the DP structure; a decoder that trusts the
  declared length silently drops the tail of every receipt.
* **`*` and `?` are separators, not delimiters to split on.** DP4 text
  legitimately contains asterisks — masked PANs, rules of stars — so the
  payload must never be split on `*` before it is decoded.

`NapsReceipt.isTruncated` is set when the payload ended without its `?`
terminator, i.e. the receipt is known to be short.

## Supported M2M TLV Commands

This SDK implements the full specifications for the M2M TLV API on the SUNMI P2 terminal:
* `001 / 101` - Payment Request / Response
* `002 / 102` - Payment Confirmation
* `003 / 103` - Cancellation Request
* `004 / 104` - Cancellation Confirmation
* `008 / 108` - Duplicate Request
* `009 / 109` - Network Test
* `010 / 110` - Totals Request
* `011 / 111` - Print Information Request
* `012 / 112` - EPT Reset
* `013 / 113` - Referencing Order (parameter load)