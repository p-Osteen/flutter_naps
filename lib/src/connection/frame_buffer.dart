import 'dart:typed_data';

import '../protocol/message.dart';
import '../protocol/response_codes.dart';
import '../protocol/tlv.dart';

/// A frame the buffer believes is complete, not yet consumed.
class NapsFramePeek {
  /// The decoded message instance.
  final NapsMessage message;

  /// Exclusive end offset of the frame within the buffer.
  final int end;

  /// True when the frame ended at a DP `?` terminator — the one place the
  /// wire format actually says "this is the end".
  ///
  /// When false the boundary was inferred from the message envelope, and the
  /// caller should let the stream settle briefly before acting on it.
  final bool delimited;

  /// Creates a frame peek result with decoded message, end offset, and delimiter flag.
  const NapsFramePeek(this.message, this.end, this.delimited);
}

/// Accumulates bytes off a socket or serial port and hands back whole frames.
///
/// Everything here is byte-oriented on purpose. Decoding each arriving chunk
/// to a `String` — as this SDK previously did — fails two ways: a multi-byte
/// character split across a TCP segment boundary throws mid-transaction, and
/// TLV lengths are byte counts, so any accent in the French receipt text
/// shifts every subsequent offset.
///
/// The harder problem is knowing where a frame *ends*. A NAPS frame is a bare
/// chain of TLVs: no length prefix, no delimiter. "I parsed every byte I have"
/// is therefore not the same as "the message is complete" — a buffer that
/// stops on a field boundary is indistinguishable from a finished one. This
/// class closes that gap with the envelope rules from the specification.
class NapsFrameBuffer {
  /// Creates an empty [NapsFrameBuffer].
  NapsFrameBuffer();

  Uint8List _bytes = Uint8List(0);

  /// Tags every exchanged message must carry (guide §4.1, spec §III.2.1):
  /// TM, NCAI, NS, DA, HE.
  static const Set<String> _envelope = {'001', '003', '004', '014', '015'};

  /// Response message types that carry DP when the operation succeeded.
  static const Set<String> _dpBearingResponses = {
    '101',
    '102',
    '104',
    '108',
    '110',
    '111',
    '113',
  };

  /// The current number of bytes held in the buffer.
  int get length => _bytes.length;

  /// Whether the buffer currently contains no bytes.
  bool get isEmpty => _bytes.isEmpty;

  /// Returns a copy of the current buffered bytes.
  Uint8List snapshot() => Uint8List.fromList(_bytes);

  /// Clears all buffered bytes.
  void clear() => _bytes = Uint8List(0);

  /// Appends incoming raw byte chunks to the buffer.
  void add(List<int> chunk) {
    if (chunk.isEmpty) return;
    final merged = Uint8List(_bytes.length + chunk.length)
      ..setRange(0, _bytes.length, _bytes)
      ..setRange(_bytes.length, _bytes.length + chunk.length, chunk);
    _bytes = merged;
  }

  /// Looks for a complete frame without consuming it.
  ///
  /// Returns null while the frame is still arriving. A partial frame is never
  /// returned: handing back a buffer that merely stopped arriving produces a
  /// message with fields silently missing, and an absent tag 013 reads as an
  /// empty response code, which maps to a generic decline for a transaction
  /// the terminal may well have approved.
  ///
  /// [allowUnterminatedDp] is a last resort for the timeout path: it accepts
  /// the end of the buffer as the end of an unterminated DP, and relaxes the
  /// envelope rules so a late, odd-shaped response is surfaced rather than
  /// thrown away. The resulting message is flagged [NapsMessage.dpTruncated].
  NapsFramePeek? peekFrame({bool allowUnterminatedDp = false}) {
    if (_bytes.isEmpty) return null;

    final scan = NapsTlv.scanFrame(
      _bytes,
      allowUnterminatedDp: allowUnterminatedDp,
    );

    switch (scan.status) {
      case NapsScanStatus.needMoreData:
        return null;
      case NapsScanStatus.malformed:
        // Nothing at the head of the buffer is a TLV. Keeping it would block
        // every subsequent frame behind it.
        clear();
        return null;
      case NapsScanStatus.complete:
        break;
    }

    final frame = Uint8List.fromList(_bytes.sublist(0, scan.end));
    final message = NapsMessage.fromScan(scan, frame);

    if (!allowUnterminatedDp && !_envelopeSatisfied(message, scan)) return null;

    // "Delimited" means the boundary is certain, and the caller may act at
    // once. That is only true when the next frame's tag 001 has arrived: a DP
    // terminator ends the receipt, but fields can follow it, so a frame that
    // merely reaches the end of the buffer may still be growing. Anything
    // else goes through the caller's settle window.
    final delimited = scan.dpTerminated && scan.nextFrameStarts;
    return NapsFramePeek(message, scan.end, delimited);
  }

  /// Drops [end] bytes from the front of the buffer, after a peeked frame has
  /// been accepted.
  void commit(int end) {
    _bytes = end >= _bytes.length
        ? Uint8List(0)
        : Uint8List.fromList(_bytes.sublist(end));
  }

  /// True when the parsed fields amount to a message the terminal could
  /// actually have finished sending.
  bool _envelopeSatisfied(NapsMessage message, NapsFrameScan scan) {
    // A `?` terminator is the wire format's own end-of-message marker. Once
    // it has been seen the frame is whole by definition, so requiring DA/HE
    // or CR on top of it can only reject a message the terminal considers
    // finished - and the four days of logs cannot say whether this terminal
    // sends those tags on a receipt-bearing response, because the old logger
    // truncated every such frame before its tail.
    if (scan.dpTerminated) return true;

    for (final tag in _envelope) {
      if (!message.elements.containsKey(tag)) return false;
    }

    final tm = message.messageType;
    final tmValue = int.tryParse(tm);
    if (tmValue == null) return false;

    // Responses always carry CR; a frame without one has not finished
    // arriving, whatever else is present.
    final isResponse = tmValue >= 100;
    if (isResponse && !message.elements.containsKey('013')) return false;

    if (isResponse && _dpBearingResponses.contains(tm)) {
      final approved = NapsResponseCodes.lookup(message.responseCode).isSuccess;
      // Cancellation confirmation reports success as 480 as well as 000.
      final cancelled = tm == '104' && message.responseCode == '480';
      if (approved || cancelled) {
        // The receipt is mandatory here, and it is the last field on the
        // wire, so its terminator is the real end-of-frame marker.
        if (!message.hasReceipt) return false;
        if (!scan.dpTerminated) return false;
      }
    }

    return true;
  }
}
