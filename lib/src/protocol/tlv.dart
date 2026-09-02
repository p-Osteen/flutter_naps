class TlvElement {
  final String tag;
  final String value;

  TlvElement(this.tag, this.value);

  int get length => value.length;

  /// Serializes the TLV element to its string representation.
  /// Tag (3 chars) + Length (3 chars, zero-padded) + Value
  String encode() {
    final formattedTag = tag.padLeft(3, '0');
    final formattedLength = length.toString().padLeft(3, '0');
    return '$formattedTag$formattedLength$value';
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
  /// Encodes a list of TLV elements into a single concatenated string.
  static String encode(List<TlvElement> elements) {
    final sb = StringBuffer();
    for (final element in elements) {
      sb.write(element.encode());
    }
    return sb.toString();
  }

  /// Decodes a raw frame string into a list of TLV elements.
  ///
  /// When [strict] is true (default), throws a [FormatException] on any
  /// malformed data. Real EPT hardware sometimes appends trailing garbage
  /// after the last valid field (observed in production exchange logs), so
  /// incoming frames should be decoded with [strict] set to false: parsing
  /// then stops and returns the elements found so far instead of throwing.
  static List<TlvElement> decode(String frame, {bool strict = true}) {
    final elements = <TlvElement>[];
    int index = 0;

    while (index < frame.length) {
      if (index + 6 > frame.length) {
        if (!strict) break;
        throw FormatException(
            'Malformed TLV frame: incomplete header at index $index. Frame: "$frame"');
      }

      final tag = frame.substring(index, index + 3);
      final lengthStr = frame.substring(index + 3, index + 6);
      final length = int.tryParse(lengthStr);

      if (length == null) {
        if (!strict) break;
        throw FormatException(
            'Malformed TLV frame: invalid length "$lengthStr" at index ${index + 3}');
      }

      if (index + 6 + length > frame.length) {
        if (!strict) break;
        throw FormatException(
            'Malformed TLV frame: expected value of length $length at index ${index + 6}, but reached end of string');
      }

      final value = frame.substring(index + 6, index + 6 + length);
      elements.add(TlvElement(tag, value));
      index += 6 + length;
    }

    return elements;
  }
}
