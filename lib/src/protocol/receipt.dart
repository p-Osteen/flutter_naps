import 'tlv.dart';

enum NapsPrintFormat {
  simple,
  bold,
}

enum NapsAlignment {
  left,
  center,
  right,
}

class NapsReceiptLine {
  final int lineNumber;
  final NapsPrintFormat format;
  final NapsAlignment alignment;
  final String text;

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
      lineNumber.hashCode ^ format.hashCode ^ alignment.hashCode ^ text.hashCode;
}

class NapsReceipt {
  final List<NapsReceiptLine> lines;

  NapsReceipt(this.lines);

  /// Extracts named fields from receipt text lines.
  ///
  /// Scans each line for `Key: Value` or `Key : Value` patterns and returns
  /// a map of lowercase-normalised keys to their values. Common fields
  /// include `"merchant id"`, `"terminal id"`, `"stan"`, etc.
  ///
  /// Example:
  /// ```dart
  /// final fields = receipt.extractFields();
  /// final merchantId = fields['merchant id'];
  /// final terminalId = fields['terminal id'];
  /// ```
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

  /// Parses raw receipt data (Tag 010) into a [NapsReceipt].
  /// Format is: line1*line2*line3?
  /// Each line is a concatenated TLV stream of sub-tags:
  /// - Tag 030 (DP1): line number
  /// - Tag 031 (DP2): format ('S' or 'G')
  /// - Tag 032 (DP3): alignment ('G' = left, 'C' = center, 'D' = right)
  /// - Tag 033 (DP4): text
  factory NapsReceipt.parse(String rawData) {
    if (rawData.isEmpty) {
      return NapsReceipt([]);
    }

    final lines = <NapsReceiptLine>[];
    
    // Split the raw string by '*'
    final segments = rawData.split('*');

    for (var i = 0; i < segments.length; i++) {
      var segment = segments[i].trim();
      if (segment.isEmpty) continue;

      bool isLast = false;
      
      final questionMarkIdx = segment.indexOf('?');
      if (questionMarkIdx != -1) {
        isLast = true;
        segment = segment.substring(0, questionMarkIdx);
      }

      if (segment.isEmpty) {
        if (isLast) break;
        continue;
      }

      try {
        final elements = NapsTlv.decode(segment);
        final map = {for (var e in elements) e.tag: e.value};

        final lineNumStr = map['030'] ?? '0';
        final lineNum = int.tryParse(lineNumStr) ?? 0;

        final formatChar = map['031'] ?? 'S';
        final format = formatChar == 'G' ? NapsPrintFormat.bold : NapsPrintFormat.simple;

        final alignChar = map['032'] ?? 'G';
        final alignment = alignChar == 'C'
            ? NapsAlignment.center
            : alignChar == 'D'
                ? NapsAlignment.right
                : NapsAlignment.left;

        final text = map['033'] ?? '';

        lines.add(NapsReceiptLine(
          lineNumber: lineNum,
          format: format,
          alignment: alignment,
          text: text,
        ));
      } catch (e) {
        // Skip or rethrow on individual malformed line parsing errors
        // We log and skip to be robust, but we can throw if formatting is strictly verified
      }

      if (isLast) {
        break;
      }
    }

    return NapsReceipt(lines);
  }
}
