import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:typed_data';

import 'tlv.dart';

/// Text print weight and formatting for a receipt line.
enum NapsPrintFormat {
  /// Normal standard weight text.
  simple,

  /// Emphasized bold text.
  bold,
}

/// Text alignment for a receipt line.
enum NapsAlignment {
  /// Left-aligned text.
  left,

  /// Centered text.
  center,

  /// Right-aligned text.
  right,
}

/// A parsed single line of a NAPS payment receipt.
class NapsReceiptLine {
  /// The 1-based sequential line number within the receipt.
  final int lineNumber;

  /// The formatting style (simple or bold) for this line.
  final NapsPrintFormat format;

  /// The horizontal text alignment for this line.
  final NapsAlignment alignment;

  /// The textual content of the receipt line.
  final String text;

  /// Creates a receipt line with the specified [lineNumber], [format], [alignment], and [text].
  NapsReceiptLine({
    required this.lineNumber,
    required this.format,
    required this.alignment,
    required this.text,
  });

  @override
  String toString() =>
      'NapsReceiptLine(line: $lineNumber, format: $format, align: $alignment, text: "$text")';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is NapsReceiptLine &&
          lineNumber == other.lineNumber &&
          format == other.format &&
          alignment == other.alignment &&
          text == other.text;

  @override
  int get hashCode =>
      lineNumber.hashCode ^
      format.hashCode ^
      alignment.hashCode ^
      text.hashCode;
}

/// A parsed NAPS transaction receipt containing sequential receipt lines.
class NapsReceipt {
  /// The ordered lines of this receipt.
  final List<NapsReceiptLine> lines;

  /// True when the DP payload ended without its `?` terminator, i.e. the
  /// receipt this object carries is known to be short. Callers that print
  /// legally significant copies should surface this rather than ignore it.
  final bool isTruncated;

  /// Creates a [NapsReceipt] with the given [lines] and truncation flag.
  NapsReceipt(this.lines, {this.isTruncated = false});

  /// Extracts named fields from receipt text lines.
  ///
  /// Scans each line for `Key: Value` or `Key : Value` patterns and returns
  /// a map of lowercase-normalised keys to their values.
  Map<String, String> extractFields() {
    final fields = <String, String>{};
    final pattern = RegExp(r'^(.+?)\s*:\s*(.+)$');
    for (final line in lines) {
      final match = pattern.firstMatch(line.text.trim());
      if (match != null) {
        fields[match.group(1)!.trim().toLowerCase()] = match.group(2)!.trim();
      }
    }
    return fields;
  }

  /// Values the terminal prints on the receipt but does not always return as
  /// a TLV field of its own.
  ///
  /// Observed on 3 September 2026: approved payments carried the
  /// authorisation number only on the printed receipt
  /// (`N° Autorisation : 854667`), so a POS relying on tag 009 alone records
  /// nothing. These lookups let a caller fall back to the receipt.
  ///
  /// Keys are matched case-insensitively and accent-insensitively against the
  /// start of the label, so both the French and English wordings resolve.
  static const Map<String, List<String>> _fieldAliases = {
    'authorisationNumber': [
      'n autorisation',
      'no autorisation',
      'authorization',
      'authorisation',
      'auth',
    ],
    'merchantNumber': [
      'n commercant',
      'no commercant',
      'merchant id',
      'merchant',
    ],
    'terminalNumber': ['n terminal', 'no terminal', 'terminal id', 'terminal'],
    'transactionNumber': ['n transaction', 'no transaction', 'transaction'],
    'stan': ['n stan', 'stan'],
    'amount': ['montant', 'amount', 'total'],
  };

  static String _normaliseKey(String raw) {
    const from = 'àâäçéèêëîïôöùûüÿ°';
    const to = 'aaaceeeeiioouuuy ';
    final buffer = StringBuffer();
    for (final rune in raw.toLowerCase().runes) {
      final ch = String.fromCharCode(rune);
      final i = from.indexOf(ch);
      buffer.write(i >= 0 ? to[i] : ch);
    }
    return buffer
        .toString()
        .replaceAll(RegExp(r'[^a-z0-9 ]'), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /// Looks up one of [_fieldAliases] in the receipt text.
  ///
  /// Returns null when the receipt does not carry it, so a caller can prefer
  /// a TLV field when present and fall back to this when it is not.
  String? field(String name) {
    final aliases = _fieldAliases[name];
    if (aliases == null) return null;
    for (final entry in extractFields().entries) {
      final key = _normaliseKey(entry.key);
      for (final alias in aliases) {
        if (key == alias ||
            key.startsWith('$alias ') ||
            key.startsWith(alias)) {
          final value = entry.value.trim();
          if (value.isNotEmpty) return value;
        }
      }
    }
    return null;
  }

  /// Authorisation number as printed on the receipt, when present.
  String? get authorisationNumber => field('authorisationNumber');

  /// Merchant number as printed on the receipt, when present.
  String? get merchantNumber => field('merchantNumber');

  /// Terminal number as printed on the receipt, when present.
  String? get terminalNumber => field('terminalNumber');

  /// Parses raw receipt data (tag 010) held as a string.
  ///
  /// Prefer [NapsReceipt.parseBytes]: DP sub-tag lengths are byte counts, and
  /// the receipt text is accented French, so string offsets drift.
  factory NapsReceipt.parse(String rawData) =>
      NapsReceipt.parseBytes(Uint8List.fromList(utf8.encode(rawData)));

  /// Parses raw receipt data (tag 010) from the bytes the terminal sent.
  ///
  /// The payload is a chain of printable lines, each built from four
  /// sub-TLVs — DP1 (030, line number), DP2 (031, format), DP3 (032,
  /// alignment) and DP4 (033, text) — separated by `*`, the last one closed
  /// by `?`.
  ///
  /// The parse is driven entirely by the declared sub-tag lengths. It never
  /// splits the payload on `*` first, because DP4 *content* legitimately
  /// contains asterisks — masked PANs such as `5321****5556`, rules of stars,
  /// decorative banners — and splitting on them fabricates one segment per
  /// asterisk while destroying the line each came from.
  factory NapsReceipt.parseBytes(Uint8List raw) {
    if (raw.isEmpty) return NapsReceipt(const []);

    final lines = <NapsReceiptLine>[];
    var p = 0;
    var terminated = false;

    while (p < raw.length) {
      final fields = <String, Uint8List>{};
      var read = 0;

      while (read < kDpSubTags.length) {
        if (p < raw.length &&
            (raw[p] == kDpSeparator || raw[p] == kDpTerminator)) {
          break;
        }
        if (p + 6 > raw.length) break;
        final tag = String.fromCharCodes(raw, p, p + 3);
        if (!kDpSubTags.contains(tag)) break;
        final len = _int3(raw, p + 3);
        if (len == null) break;
        // LENGTH is a character count, not a byte count: the terminal declares
        // 23 for "N° Commerçant : 2260292", which is 23 characters and 25
        // UTF-8 bytes. Reading it as bytes stopped every receipt at the first
        // accented line. Must stay in step with NapsTlv, which uses the same
        // rule to find the end of the DP field.
        final valueEnd = _advanceChars(raw, p + 6, len);
        if (valueEnd < 0) break;
        fields[tag] = Uint8List.fromList(raw.sublist(p + 6, valueEnd));
        p = valueEnd;
        read++;
      }

      if (read == 0) {
        developer.log(
          'Unparseable DP segment at offset $p; stopping receipt parse',
          name: 'NapsReceipt',
        );
        break;
      }

      lines.add(
        NapsReceiptLine(
          lineNumber: int.tryParse(_text(fields['030'])) ?? 0,
          format: _text(fields['031']) == 'G'
              ? NapsPrintFormat.bold
              : NapsPrintFormat.simple,
          alignment: _alignment(_text(fields['032'])),
          // Deliberately not trimmed: leading and trailing spaces are how the
          // terminal centres and pads a 24-column line.
          text: _text(fields['033']),
        ),
      );

      if (p >= raw.length) break;
      final sep = raw[p];
      p++;
      if (sep == kDpTerminator) {
        terminated = true;
        break;
      }
      if (sep != kDpSeparator) {
        developer.log(
          'Unexpected DP separator 0x${sep.toRadixString(16)} at offset ${p - 1}',
          name: 'NapsReceipt',
        );
        break;
      }
    }

    return NapsReceipt(lines, isTruncated: !terminated);
  }

  static NapsAlignment _alignment(String raw) {
    switch (raw) {
      case 'C':
        return NapsAlignment.center;
      case 'D':
        return NapsAlignment.right;
      default:
        return NapsAlignment.left;
    }
  }

  static String _text(Uint8List? bytes) =>
      bytes == null ? '' : utf8.decode(bytes, allowMalformed: true);

  /// Byte offset of the character [count] characters after [from], or -1 when
  /// those bytes have not all arrived. See the note in [parseBytes]: DP
  /// LENGTH counts characters, and this receipt's French text is not ASCII.
  static int _advanceChars(Uint8List bytes, int from, int count) {
    var p = from;
    var seen = 0;
    while (seen < count) {
      if (p >= bytes.length) return -1;
      final b = bytes[p];
      final width = b < 0x80
          ? 1
          : (b & 0xE0) == 0xC0
          ? 2
          : (b & 0xF0) == 0xE0
          ? 3
          : (b & 0xF8) == 0xF0
          ? 4
          : 1;
      if (p + width > bytes.length) return -1;
      p += width;
      seen++;
    }
    return p;
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
}
