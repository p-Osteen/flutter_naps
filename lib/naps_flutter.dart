/// A Flutter package for integrating NAPS SUNMI P2 payment terminals using the M2M TLV protocol.
///
/// This library provides the necessary components to connect, send requests,
/// and parse responses from SUNMI P2 terminals using TCP/IP or Serial.
library;

export 'src/protocol/tlv.dart';
export 'src/protocol/message.dart';
export 'src/protocol/receipt.dart';
export 'src/protocol/response_codes.dart';
export 'src/cancel_token.dart';
export 'src/connection/connection.dart';
export 'src/connection/tcp_connection.dart';
export 'src/connection/serial_connection.dart';
export 'src/sdk.dart';
