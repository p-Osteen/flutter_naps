import 'dart:typed_data';

import 'tlv.dart';

/// Tags whose value is cardholder data and must never leave the POS in the
/// clear. Guide §10.2: only masked or truncated data returned by the EPT may
/// be logged.
const Set<String> kCardholderTags = {
  '007', // NCAR - card number
  '016', // NPRT - cardholder name
};

/// Renders NAPS frames for logging with cardholder fields masked.
///
/// Redaction happens here, at the boundary, rather than being left to each
/// caller: the terminal currently returns an already-masked PAN, but nothing
/// in the protocol guarantees that, and a log pipeline is the wrong place to
/// discover otherwise.
class NapsLogRedactor {
  /// Private constructor to prevent instantiation of this utility class.
  NapsLogRedactor._();

  /// Returns [frame] with the value of every [kCardholderTags] field replaced
  /// by `X` of the same length, so offsets and lengths stay diagnosable.
  static Uint8List redact(Uint8List frame) {
    final out = Uint8List.fromList(frame);
    var i = 0;
    while (i + 6 <= out.length) {
      final tag = String.fromCharCodes(out, i, i + 3);
      var len = 0;
      var ok = true;
      for (var k = i + 3; k < i + 6; k++) {
        final c = out[k];
        if (c < 0x30 || c > 0x39) {
          ok = false;
          break;
        }
        len = len * 10 + (c - 0x30);
      }
      if (!ok) break;

      var end = i + 6 + len;
      if (tag == kTagDp && len >= kMaxDeclaredLength) {
        // DP may run past its declared length; it carries no PAN of its own
        // beyond what the terminal already masked, so skip to the end.
        end = out.length;
      }
      if (end > out.length) break;

      if (kCardholderTags.contains(tag)) {
        for (var k = i + 6; k < end; k++) {
          out[k] = 0x58; // 'X'
        }
      }
      i = end;
    }
    return out;
  }

  /// Lowercase hex of the redacted frame.
  static String toHex(Uint8List frame) {
    final safe = redact(frame);
    final sb = StringBuffer();
    for (final b in safe) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }

  /// A one-line `tag(len)=value` breakdown of the redacted frame, with DP
  /// summarised by length rather than dumped.
  static String toTlvSummary(Uint8List frame) {
    final scan = NapsTlv.scanFrame(redact(frame), allowUnterminatedDp: true);
    if (scan.elements.isEmpty) return '<unparseable ${frame.length}B>';
    return scan.elements
        .map(
          (e) => e.tag == kTagDp
              ? '010(${e.length})=<dp ${e.length}B>'
              : '${e.tag}(${e.length})=${e.value}',
        )
        .join(' ');
  }
}

/// Masks card numbers for anything outside the protocol itself.
///
/// The terminal returns the **complete** card number in tag 007 on an approved
/// payment, and TM 002 is required to echo it back verbatim, so the SDK has to
/// hold the unmasked value. Everywhere else — storage, logs, receipts, another
/// system's API — must use a masked form.
///
/// The chosen format matches what the terminal prints on its own receipt
/// (`455256******9866`), so a masked value here lines up with the paper copy.
class NapsPan {
  /// Private constructor to prevent instantiation of this utility class.
  NapsPan._();

  /// First six and last four digits retained, the middle replaced.
  ///
  /// A value that already contains non-digits is assumed to be masked already
  /// and is returned unchanged. A value too short to mask meaningfully is
  /// replaced entirely.
  static String? mask(String? pan) {
    if (pan == null || pan.isEmpty) return pan;
    final digitsOnly = RegExp(r'^[0-9]+$').hasMatch(pan);
    if (!digitsOnly) return pan;
    if (pan.length < 11) return '*' * pan.length;
    return '${pan.substring(0, 6)}'
        '${'*' * (pan.length - 10)}'
        '${pan.substring(pan.length - 4)}';
  }

  /// The last four digits only, for anywhere that needs no more than that.
  static String? last4(String? pan) {
    if (pan == null || pan.isEmpty) return pan;
    final digits = pan.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length < 4) return null;
    return digits.substring(digits.length - 4);
  }
}
