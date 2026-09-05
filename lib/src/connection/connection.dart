import 'dart:typed_data';

import '../protocol/message.dart';
import '../protocol/redaction.dart';

/// Which way a logged frame was travelling.
enum NapsFrameDirection { outbound, inbound }

/// One frame, rendered safe for logging.
///
/// The raw bytes are deliberately not exposed. A logger that receives this
/// object cannot leak cardholder data even by accident, which is the only way
/// to make guide §10.2 hold for a pipeline that ships logs off the device.
class NapsFrameLog {
  final NapsFrameDirection direction;

  /// Length of the frame as it appeared on the wire, in bytes.
  final int byteLength;

  /// Lowercase hex of the frame with tags 007 and 016 masked.
  final String hex;

  /// `tag(len)=value` breakdown with the same fields masked and DP summarised.
  final String tlv;

  /// Bytes still in the read buffer once this frame was taken.
  ///
  /// [byteLength] is where the PARSER stopped, not how much arrived. When a
  /// frame is reported truncated and this is greater than zero, the rest of
  /// the response was already in hand and the fault is on our side of the
  /// wire - which is precisely the distinction that took a 24.00 MAD
  /// transaction and two rounds with NAPS to establish.
  final int bufferedAfter;

  const NapsFrameLog({
    required this.direction,
    required this.byteLength,
    required this.hex,
    required this.tlv,
    this.bufferedAfter = 0,
  });

  factory NapsFrameLog.of(
    NapsFrameDirection direction,
    Uint8List frame, {
    int bufferedAfter = 0,
  }) => NapsFrameLog(
    direction: direction,
    byteLength: frame.length,
    hex: NapsLogRedactor.toHex(frame),
    tlv: NapsLogRedactor.toTlvSummary(frame),
    bufferedAfter: bufferedAfter,
  );

  @override
  String toString() =>
      '${direction == NapsFrameDirection.outbound ? '>>' : '<<'} ${byteLength}B $tlv';
}

typedef NapsFrameLogger = void Function(NapsFrameLog entry);

abstract class NapsConnection {
  /// Establish connection to the EPT terminal.
  Future<bool> connect();

  /// Terminate connection to the EPT terminal.
  Future<void> disconnect();

  /// Returns true if currently connected.
  bool get isConnected;

  /// Encodes and sends a [NapsMessage] to the EPT.
  Future<void> send(NapsMessage message);

  /// Waits for and receives a [NapsMessage] response from the EPT.
  /// An optional [timeout] can be specified to override default connection timeouts.
  Future<NapsMessage> receive({Duration? timeout});

  /// Attempts to re-establish the connection after a transient disconnect.
  /// Subclasses may override for reconnect-with-backoff behavior.
  /// Returns true if reconnection was successful within [maxAttempts].
  Future<bool> reconnect({int maxAttempts = 3});

  /// A short description of the transport, for diagnostics
  /// (e.g. `wifi 192.168.1.26:4444`, `usb COM3@9600`).
  String get transportDescription;
}
