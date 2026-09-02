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

This example shows how to use the NAPS SDK to process a payment:

```dart
import 'package:naps_flutter/naps_flutter.dart';

void main() async {
  // 1. Start the Naps connection and SDK (example for Wi-Fi)
  final connection = NapsTcpConnection(host: '192.168.1.26', port: 4444);
  final napsSdk = NapsSdk(
    connection: connection,
    posId: '0030007', // 7 chars limit
  );

  // 2. Start a payment (for example, 35.00 MAD)
  final response = await napsSdk.pay(
    amountInCents: 3500, // 35.00 MAD
    currencyCode: '504', // 504 for MAD
  );

  if (response.isSuccess) {
    print('Payment Approved! STAN: ${response.stan}');
    
    // 3. Confirm the payment within 40 seconds
    final confirmationResponse = await napsSdk.confirmPayment(
      originalStan: response.stan!,
      amountInCents: 3500,
      currencyCode: '504',
      sequenceNumber: 1, // original sequence number
      cardMasked: response.cardNumber!,
      expirationDate: response.cardExpirationDate!,
    );
    
    if (confirmationResponse.isSuccess) {
      print('Payment confirmed successfully.');
      // Print the customer receipt with confirmationResponse.customerReceipt
    }
  } else {
    print('Payment Failed or Declined.');
  }
}
```

## Supported M2M TLV Commands

This SDK implements the full specifications for the M2M TLV API on the SUNMI P2 terminal:
* `001 / 101` - Payment Request / Response
* `002 / 102` - Payment Confirmation
* `003 / 103` - Cancellation Request
* `004 / 104` - Cancellation Confirmation
* `008 / 108` - Duplicate Request
* `010 / 110` - Totals Request