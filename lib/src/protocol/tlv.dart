import 'dart:convert';
import 'dart:typed_data';

/// Byte value of the DP line separator `*` (spec §III.2.4).
const int kDpSeparator = 0x2A;

/// Byte value of the DP end-of-receipt marker `?` (spec §III.2.4).
const int kDpTerminator = 0x3F;

/// Tag carrying printable receipt data (DP).
const String kTagDp = '010';

/// Sub-tags that make up one printable receipt line: DP1..DP4.
const Set<String> kDpSubTags = {'030', '031', '032', '033'};

/// The largest value a 3-character LENGTH field can express.
///
/// This matters: tag 010 receipts routinely exceed it. The terminal pins
/// LENGTH at 999 and keeps writing, so a decoder that trusts the declared
/// length silently drops the tail of every receipt. Observed in the reference
/// exchange log: an TM 101 frame of 1309 bytes whose scalar fields occupy 140
/// bytes, leaving a DP of 1163 bytes declared as 999.
const int kMaxDeclaredLength = 999;

/// Outcome of scanning a byte buffer for one complete NAPS frame.
enum NapsScanStatus {
  /// Every buffered byte parsed as a well-formed TLV chain.
  ///
  /// This means the bytes are *self-consistent*, not that the frame is
  /// finished: a NAPS frame carries no length prefix and no delimiter, so a
  /// buffer that happens to stop on a field boundary looks exactly like a
  /// finished message. Deciding that is the caller's job — see
  /// `NapsFrameBuffer.peekFrame`, which applies the envelope policy.
  complete,

  /// The buffer holds a valid prefix. Wait for more bytes.
  needMoreData,

  /// The buffer does not begin with a decodable TLV. Discard it.
  malformed,
}

/// The result of [NapsTlv.scanFrame].
class NapsFrameScan {
  final NapsScanStatus status;
  final List<TlvElement> elements;

  /// Exclusive end offset of the frame within the scanned buffer.
  /// Only meaningful when [status] is [NapsScanStatus.complete].
  final int end;

  /// True when the DP value was closed by the end of the buffer rather than by
  /// a `?` terminator. Only ever set when the caller passed
  /// `allowUnterminatedDp: true`, i.e. as a last resort after a timeout.
  final bool dpTruncated;

  /// True when a DP field was present and closed by its `?` terminator.
  ///
  /// This is the only point in a NAPS frame where the wire format states
  /// "this is the end". The frame itself carries no length prefix and no
  /// delimiter, so for every other message the end has to be inferred.
  final bool dpTerminated;

  const NapsFrameScan(
    this.status,
    this.elements,
    this.end, {
    this.dpTruncated = false,
    this.dpTerminated = false,
  });
}

/// A single Tag-Length-Value element.
///
/// NAPS encodes LENGTH as a 3-digit **byte** count. [valueBytes] is therefore
/// the authoritative representation; [value] is a UTF-8 view of it. Using a
/// Dart `String` as the source of truth is wrong for any frame containing the
/// accented characters that appear throughout the French receipt text, because
/// String indices are UTF-16 code units, not bytes.
class TlvElement {
  final String tag;
  final Uint8List valueBytes;
  String? _decoded;

  TlvElement(this.tag, String value)
    : valueBytes = Uint8List.fromList(utf8.encode(value)),
      _decoded = value;

  TlvElement.fromBytes(this.tag, this.valueBytes);

  /// The value decoded as UTF-8. Malformed sequences are replaced rather than
  /// thrown on, so one bad byte never destroys an otherwise usable response.
  String get value =>
      _decoded ??= utf8.decode(valueBytes, allowMalformed: true);

  /// LENGTH as the terminal counts it: bytes.
  int get length => valueBytes.length;

  /// Serialises to `TAG(3) + LENGTH(3, zero-padded) + VALUE`.
  ///
  /// A value longer than [kMaxDeclaredLength] cannot express its own length;
  /// the field is emitted saturated at 999, matching terminal behaviour. The
  /// SDK never builds such a field itself — only DP, which is inbound only.
  String encode() {
    final declared = length > kMaxDeclaredLength ? kMaxDeclaredLength : length;
    return '${tag.padLeft(3, '0')}${declared.toString().padLeft(3, '0')}$value';
  }

  @override
  String toString() => 'TlvElement(tag: $tag, length: $length, value: $value)';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TlvElement && tag == other.tag && value == other.value;

  @override
  int get hashCode => tag.hashCode ^ value.hashCode;
}

class NapsTlv {
  // Sentinels for the DP structural scan.
  static const int _dpNeedMore = -1;
  static const int _dpMalformed = -2;

  /// Encodes a list of TLV elements into a single concatenated frame.
  static String encode(List<TlvElement> elements) {
    final sb = StringBuffer();
    for (final element in elements) {
      sb.write(element.encode());
    }
    return sb.toString();
  }

  /// Encodes to the bytes actually put on the wire.
  static Uint8List encodeBytes(List<TlvElement> elements) =>
      Uint8List.fromList(utf8.encode(encode(elements)));

  /// Scans [bytes] from [start] for exactly one complete frame.
  ///
  /// Unlike a naive TLV walk this understands two things the terminal does:
  ///
  ///  * tag 010 saturates its LENGTH at 999 and keeps writing, so its true
  ///    extent has to be recovered from the DP structure itself; and
  ///  * a frame is only complete once that structure reaches its `?`
  ///    terminator — a buffer that merely ends at a DP line boundary is a
  ///    partially arrived frame, not a short one.
  ///
  /// Pass [allowUnterminatedDp] only as a last resort (e.g. after a receive
  /// timeout) to accept the end of the buffer as the end of the DP. The
  /// resulting scan is flagged with [NapsFrameScan.dpTruncated].
  static NapsFrameScan scanFrame(
    Uint8List bytes, {
    int start = 0,
    bool allowUnterminatedDp = false,
  }) {
    final elements = <TlvElement>[];
    var i = start;
    var truncated = false;
    var terminated = false;

    while (i < bytes.length) {
      if (i + 6 > bytes.length) {
        // A header has begun but not fully arrived. Never treat this as the
        // end of a frame: doing so delivers a message with fields missing.
        return NapsFrameScan(NapsScanStatus.needMoreData, elements, -1);
      }

      final tag = _tagAt(bytes, i);
      final declared = _int3(bytes, i + 3);

      if (!_isNumeric(tag) || declared == null) {
        if (elements.isEmpty) {
          return const NapsFrameScan(NapsScanStatus.malformed, [], 0);
        }
        // Trailing bytes that are not a TLV: the frame ended here.
        return NapsFrameScan(
          NapsScanStatus.complete,
          elements,
          i,
          dpTruncated: truncated,
          dpTerminated: terminated,
        );
      }

      final valueStart = i + 6;
      int valueEnd;

      if (tag == kTagDp && declared >= kMaxDeclaredLength) {
        final scanned = _scanDpEnd(
          bytes,
          valueStart,
          allowUnterminated: allowUnterminatedDp,
        );
        if (scanned == _dpNeedMore) {
          return NapsFrameScan(NapsScanStatus.needMoreData, elements, -1);
        }
        if (scanned == _dpMalformed) {
          // Fall back to the declared length rather than losing the field.
          valueEnd = valueStart + declared;
          if (valueEnd > bytes.length) {
            return NapsFrameScan(NapsScanStatus.needMoreData, elements, -1);
          }
        } else {
          valueEnd = scanned;
          if (bytes[valueEnd - 1] == kDpTerminator) {
            terminated = true;
          } else if (valueEnd == bytes.length) {
            truncated = true;
          }
        }
      } else {
        valueEnd = valueStart + declared;
        if (valueEnd > bytes.length) {
          return NapsFrameScan(NapsScanStatus.needMoreData, elements, -1);
        }
        if (tag == kTagDp &&
            declared > 0 &&
            bytes[valueEnd - 1] == kDpTerminator) {
          terminated = true;
        }
      }

      elements.add(
        TlvElement.fromBytes(tag, _slice(bytes, valueStart, valueEnd)),
      );
      i = valueEnd;

      if (terminated) {
        // DP is the last field of a frame and its '?' is the only explicit
        // end-of-message marker the protocol has. Stop here rather than
        // running on into whatever arrived next, which would merge two
        // responses into one message and silently drop the first one's
        // duplicate tags.
        return NapsFrameScan(
          NapsScanStatus.complete,
          elements,
          i,
          dpTruncated: truncated,
          dpTerminated: true,
        );
      }
    }

    if (elements.isEmpty) {
      return const NapsFrameScan(NapsScanStatus.malformed, [], 0);
    }
    return NapsFrameScan(
      NapsScanStatus.complete,
      elements,
      i,
      dpTruncated: truncated,
      dpTerminated: terminated,
    );
  }

  /// Walks the DP structure from [start] and returns the exclusive end offset
  /// of the receipt, including its `?` terminator.
  ///
  /// Returns [_dpNeedMore] when the buffer runs out mid-receipt, or
  /// [_dpMalformed] when the bytes at [start] are not a DP line.
  static int _scanDpEnd(
    Uint8List bytes,
    int start, {
    bool allowUnterminated = false,
  }) {
    var p = start;

    while (true) {
      // One printable line is DP1+DP2+DP3+DP4 (tags 030..033), each carrying
      // its own explicit length. Reading them by length — rather than
      // splitting the payload on '*' — is what makes an asterisk inside the
      // line text (a masked PAN, a rule of stars) harmless.
      var read = 0;
      while (read < kDpSubTags.length) {
        if (p < bytes.length &&
            (bytes[p] == kDpSeparator || bytes[p] == kDpTerminator)) {
          break;
        }
        if (p + 6 > bytes.length) {
          return allowUnterminated && read == 0 && p >= bytes.length
              ? p
              : _dpNeedMore;
        }
        final tag = _tagAt(bytes, p);
        if (!kDpSubTags.contains(tag)) break;
        final len = _int3(bytes, p + 3);
        if (len == null) return read == 0 ? _dpMalformed : _dpNeedMore;
        if (p + 6 + len > bytes.length) return _dpNeedMore;
        p += 6 + len;
        read++;
      }

      if (read == 0) {
        if (p == start) return _dpMalformed;
        return allowUnterminated ? p : _dpMalformed;
      }

      if (p >= bytes.length) {
        // The receipt is structurally sound but its terminator has not
        // arrived. Waiting is correct; accepting is a deliberate last resort.
        return allowUnterminated ? p : _dpNeedMore;
      }

      final sep = bytes[p];
      p++;
      if (sep == kDpTerminator) return p;
      if (sep != kDpSeparator) return p - 1;
    }
  }

  /// Decodes a raw frame string into TLV elements.
  ///
  /// Kept for callers that already hold a decoded string. Prefer
  /// [scanFrame] on the wire, which is byte-accurate and understands DP.
  ///
  /// When [strict] is true (default) any malformed data throws a
  /// [FormatException].
  static List<TlvElement> decode(String frame, {bool strict = true}) {
    final bytes = Uint8List.fromList(utf8.encode(frame));
    final elements = <TlvElement>[];
    var index = 0;

    while (index < bytes.length) {
      if (index + 6 > bytes.length) {
        if (!strict) break;
        throw FormatException(
          'Malformed TLV frame: incomplete header at index $index. Frame: "$frame"',
        );
      }

      final tag = _tagAt(bytes, index);
      final length = _int3(bytes, index + 3);

      if (length == null) {
        if (!strict) break;
        throw FormatException(
          'Malformed TLV frame: invalid length at index ${index + 3}',
        );
      }

      if (index + 6 + length > bytes.length) {
        if (!strict) break;
        throw FormatException(
          'Malformed TLV frame: expected value of length $length at index ${index + 6}, but reached end of frame',
        );
      }

      elements.add(
        TlvElement.fromBytes(tag, _slice(bytes, index + 6, index + 6 + length)),
      );
      index += 6 + length;
    }

    return elements;
  }

  static String _tagAt(Uint8List b, int i) => String.fromCharCodes(b, i, i + 3);

  static bool _isNumeric(String tag) {
    for (var i = 0; i < tag.length; i++) {
      final c = tag.codeUnitAt(i);
      if (c < 0x30 || c > 0x39) return false;
    }
    return tag.length == 3;
  }

  static int? _int3(Uint8List b, int i) {
    var n = 0;
    for (var k = i; k < i + 3; k++) {
      final c = b[k];
      if (c < 0x30 || c > 0x39) return null;
      n = n * 10 + (c - 0x30);
    }
    return n;
  }

  static Uint8List _slice(Uint8List b, int from, int to) =>
      Uint8List.fromList(b.sublist(from, to));
}
