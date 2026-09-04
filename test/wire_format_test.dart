import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:naps_flutter/naps_flutter.dart';

/// Fixtures reconstructed from the reference exchange log in
/// `SDK/_logs des échanges 001_101_002_102.md`: a TM 101 response whose eleven
/// scalar fields occupy 140 bytes and whose tag 010 declares 999 while
/// carrying more, so that every parser in the estate stopped at offset 1145.
Uint8List _tlv(String tag, String value) {
  final v = utf8.encode(value);
  final declared = v.length > 999 ? 999 : v.length;
  return Uint8List.fromList([
    ...utf8.encode('$tag${declared.toString().padLeft(3, '0')}'),
    ...v,
  ]);
}

Uint8List _concat(List<Uint8List> parts) =>
    Uint8List.fromList(parts.expand((p) => p).toList());

Uint8List _dpLine(int n, String fmt, String align, String text) => _concat([
  _tlv('030', n.toString().padLeft(2, '0')),
  _tlv('031', fmt),
  _tlv('032', align),
  _tlv('033', text),
]);

/// Builds a DP payload: lines separated by '*', the last closed by '?'.
Uint8List _dpPayload(List<String> lines) {
  final parts = <Uint8List>[];
  for (var i = 0; i < lines.length; i++) {
    parts.add(_dpLine(i + 1, 'S', 'G', lines[i]));
    parts.add(
      Uint8List.fromList(utf8.encode(i == lines.length - 1 ? '?' : '*')),
    );
  }
  return _concat(parts);
}

/// Wraps a DP payload in tag 010, saturating LENGTH at 999 as the terminal does.
Uint8List _dpField(Uint8List payload) {
  final declared = payload.length > 999 ? 999 : payload.length;
  return _concat([
    Uint8List.fromList(
      utf8.encode('010${declared.toString().padLeft(3, '0')}'),
    ),
    payload,
  ]);
}

final Uint8List _scalars = _concat([
  _tlv('001', '101'),
  _tlv('003', '0100001'),
  _tlv('004', '000108'),
  _tlv('013', '000'),
  _tlv('002', '000000000022'),
  _tlv('012', '504'),
  _tlv('014', '23032026'),
  _tlv('015', '141456'),
  _tlv('007', '5321****5556'),
  _tlv('017', '2810'),
  _tlv('008', '000081'),
]);

/// Receipt content chosen to contain exactly what used to break the parser:
/// masked PANs, rules of asterisks, and accented French.
const List<String> _receiptLines = [
  'Naps',
  'CHICKET MOROCCO',
  '--------------------------------',
  'Merchant ID: 20000',
  'Terminal ID: 88398363',
  'CARTE: 5321****5556',
  'EXP: 28/10',
  'STAN: 000081',
  'AUTH: 74812',
  'MONTANT: 0,22 MAD',
  '********************************',
  'Paiement accepte a 14:14:56',
  'Opération réussie',
  'Merci de votre visite',
  'à bientôt chez Chicket',
  '--------------------------------',
  'Conservez-moi, je peux être',
  'utile en cas de réclamation !',
  'devenez commerçant partenaire',
  'www.naps.ma',
  'TICKET COMMERÇANT',
];

void main() {
  final payload = _dpPayload(_receiptLines);
  final frame101 = _concat([_scalars, _dpField(payload)]);

  group('Tag 010 length saturation', () {
    test('fixture reproduces the reference frame shape', () {
      expect(_scalars.length, 136);
      expect(
        payload.length,
        greaterThan(999),
        reason: 'the DP must exceed what a 3-digit LENGTH can express',
      );
    });

    test('DP is recovered in full, past its declared 999', () {
      final scan = NapsTlv.scanFrame(frame101);
      expect(scan.status, NapsScanStatus.complete);
      expect(scan.end, frame101.length);
      expect(scan.elements.length, 12);

      final dp = scan.elements.firstWhere((e) => e.tag == kTagDp);
      expect(dp.length, payload.length);
      expect(dp.length, greaterThan(kMaxDeclaredLength));
    });

    test('a parser that trusted LENGTH would stop at the observed offset', () {
      // 11 scalar fields (136 B) + 6 B header + 999 B = 1141, which is where
      // the production logs report "tag inconnu ... artefact".
      final naiveEnd = _scalars.length + 6 + kMaxDeclaredLength;
      expect(naiveEnd, lessThan(frame101.length));
      expect(frame101.length - naiveEnd, payload.length - kMaxDeclaredLength);
    });

    test('a DP under the ceiling still uses its declared length', () {
      final small = _dpPayload(['WELCOME', 'OK']);
      expect(small.length, lessThan(kMaxDeclaredLength));
      final frame = _concat([
        _tlv('001', '108'),
        _tlv('003', '0100001'),
        _tlv('004', '000109'),
        _tlv('013', '000'),
        _tlv('014', '23032026'),
        _tlv('015', '141456'),
        _dpField(small),
      ]);
      final scan = NapsTlv.scanFrame(frame);
      expect(scan.status, NapsScanStatus.complete);
      expect(scan.end, frame.length);
    });
  });

  group('DP structure', () {
    late NapsReceipt receipt;

    setUp(() {
      final scan = NapsTlv.scanFrame(frame101);
      receipt = NapsReceipt.parseBytes(
        scan.elements.firstWhere((e) => e.tag == kTagDp).valueBytes,
      );
    });

    test('every line is recovered', () {
      expect(receipt.lines.length, _receiptLines.length);
      expect(receipt.isTruncated, isFalse);
      expect(receipt.lines.map((l) => l.text).toList(), _receiptLines);
    });

    test('asterisks inside line text do not fabricate lines', () {
      final naiveSegments = utf8
          .decode(_dpPayload(_receiptLines), allowMalformed: true)
          .split('*')
          .length;
      expect(
        naiveSegments,
        greaterThan(_receiptLines.length),
        reason: 'the old split-first parser saw more segments than lines',
      );

      expect(
        receipt.lines.where((l) => l.text.contains('****')).length,
        2,
        reason: 'the masked PAN line and the rule of stars both survive',
      );
    });

    test('accented text decodes without shifting later fields', () {
      expect(receipt.lines[12].text, 'Opération réussie');
      expect(receipt.lines[16].text, 'Conservez-moi, je peux être');
      expect(receipt.lines[18].text, 'devenez commerçant partenaire');
      // The last line only lands correctly if no earlier accent drifted.
      expect(receipt.lines.last.text, 'TICKET COMMERÇANT');
    });
  });

  group('Framing across chunk boundaries', () {
    /// Feeds the frame to a buffer in fixed-size pieces and asserts that no
    /// prefix is ever mistaken for a whole message.
    void feed(int chunkSize) {
      final buffer = NapsFrameBuffer();
      var completedEarly = 0;
      NapsFramePeek? finished;

      for (var off = 0; off < frame101.length; off += chunkSize) {
        final end = (off + chunkSize).clamp(0, frame101.length);
        buffer.add(frame101.sublist(off, end));
        final peek = buffer.peekFrame();
        if (peek == null) continue;
        if (end < frame101.length) {
          completedEarly++;
        } else {
          finished = peek;
        }
      }

      expect(
        completedEarly,
        0,
        reason: 'a partial frame was accepted at chunk size $chunkSize',
      );
      expect(
        finished,
        isNotNull,
        reason:
            'the complete frame was not recognised at chunk size $chunkSize',
      );
      expect(finished!.end, frame101.length);
      // Not "delimited": the '?' ends the receipt, but tags can follow it, and
      // here the frame ends exactly at the end of the buffer - so the caller
      // must let the stream settle rather than act immediately. A terminator
      // only settles the boundary when more bytes are already behind it.
      expect(finished.delimited, isFalse);
    }

    for (final size in [1, 2, 7, 64, 137, 512, 1024, 4096]) {
      test('chunk size $size never yields a partial frame', () => feed(size));
    }

    test('a header split across chunks is not a frame', () {
      final buffer = NapsFrameBuffer()
        ..add(frame101.sublist(0, _scalars.length + 3));
      expect(buffer.peekFrame(), isNull);
    });

    test('scalars without their receipt are not a frame', () {
      // The envelope is complete but TM 101 with CR 000 must carry DP.
      final buffer = NapsFrameBuffer()..add(_scalars);
      expect(buffer.peekFrame(), isNull);
    });

    test('a declined response carries no DP and is still recognised', () {
      final declined = _concat([
        _tlv('001', '101'),
        _tlv('003', '0100001'),
        _tlv('004', '000108'),
        _tlv('013', '117'),
        _tlv('002', '000000000022'),
        _tlv('012', '504'),
        _tlv('014', '23032026'),
        _tlv('015', '141456'),
      ]);

      final buffer = NapsFrameBuffer();
      var early = 0;
      NapsFramePeek? done;
      for (var i = 0; i < declined.length; i++) {
        buffer.add(declined.sublist(i, i + 1));
        final peek = buffer.peekFrame();
        if (peek == null) continue;
        if (i < declined.length - 1) {
          early++;
        } else {
          done = peek;
        }
      }
      expect(early, 0);
      expect(done, isNotNull);
      expect(done!.message.responseCode, '117');
      // No DP terminator, so the boundary was inferred: callers should let
      // the stream settle before acting on it.
      expect(done.delimited, isFalse);
    });

    test('committing a frame leaves any following bytes buffered', () {
      final buffer = NapsFrameBuffer()
        ..add(frame101)
        ..add(utf8.encode('001003109'));
      final peek = buffer.peekFrame()!;
      buffer.commit(peek.end);
      expect(buffer.length, 9);
    });
  });

  group('Timeout salvage', () {
    test('an unterminated DP is not accepted by default', () {
      final noTerminator = _concat([
        _scalars,
        _dpField(payload.sublist(0, payload.length - 1)),
      ]);
      final buffer = NapsFrameBuffer()..add(noTerminator);
      expect(buffer.peekFrame(), isNull);
    });

    test('salvage returns the frame and flags it truncated', () {
      final noTerminator = _concat([
        _scalars,
        _dpField(payload.sublist(0, payload.length - 1)),
      ]);
      final buffer = NapsFrameBuffer()..add(noTerminator);
      final peek = buffer.peekFrame(allowUnterminatedDp: true);
      expect(peek, isNotNull);
      expect(peek!.message.dpTruncated, isTrue);
      expect(
        NapsReceipt.parseBytes(peek.message.receiptDataBytes).isTruncated,
        isTrue,
      );
    });
  });

  group('Request frame shapes match the reference log', () {
    test('TM 001 encodes to 87 bytes', () {
      final request = NapsMessage.paymentRequest(
        amountInCents: 22,
        posId: '0100001',
        sequenceNumber: 108,
        timestamp: DateTime(2026, 3, 23, 14, 14, 47),
      );
      expect(request.toFrameBytes().length, 87);
    });

    test('TM 002 encodes to 131 bytes with a 16-digit PAN', () {
      final request = NapsMessage.paymentConfirmationRequest(
        amountInCents: 22,
        posId: '0100001',
        sequenceNumber: 108,
        stan: '000081',
        cardMasked: '5321********5556',
        expirationDate: '2810',
        timestamp: DateTime(2026, 3, 23, 14, 14, 56),
      );
      expect(request.toFrameBytes().length, 131);
    });

    test('TLV LENGTH counts bytes, not UTF-16 code units', () {
      final element = TlvElement('033', 'Opération réussie');
      expect(element.value.length, 17);
      expect(element.length, 19);
      expect(element.encode().startsWith('033019'), isTrue);
    });
  });

  group('Log redaction', () {
    test('cardholder tags are masked before a frame can be logged', () {
      final frame = _concat([
        _tlv('001', '101'),
        _tlv('003', '0100001'),
        _tlv('004', '000108'),
        _tlv('013', '000'),
        _tlv('007', '5321987654325556'),
        _tlv('016', 'CARTE / PREPAYEE'),
        _tlv('014', '23032026'),
        _tlv('015', '141456'),
      ]);

      final entry = NapsFrameLog.of(NapsFrameDirection.inbound, frame);
      expect(entry.byteLength, frame.length);
      expect(entry.tlv, isNot(contains('5321987654325556')));
      expect(entry.tlv, isNot(contains('PREPAYEE')));
      expect(entry.tlv, contains('XXXXXXXXXXXXXXXX'));
      // Non-sensitive fields stay diagnosable.
      expect(entry.tlv, contains('004(6)=000108'));
      expect(entry.tlv, contains('013(3)=000'));
      // The hex is redacted too, not just the summary.
      expect(
        entry.hex,
        isNot(
          contains(
            utf8
                .encode('5321987654325556')
                .map((b) => b.toRadixString(16).padLeft(2, '0'))
                .join(),
          ),
        ),
      );
    });
  });

  group('Sequence numbers', () {
    test('a store advances across transactions', () async {
      final store = InMemoryNapsSequenceStore();
      expect(await store.next(), 1);
      expect(await store.next(), 2);
      expect(await store.next(), 3);
      expect(await store.current(), 3);
    });

    test('a callback store persists before handing a number out', () async {
      int? persisted;
      final store = CallbackNapsSequenceStore(
        read: () async => persisted,
        write: (v) async => persisted = v,
      );
      expect(await store.next(), 1);
      expect(persisted, 1);

      // A fresh store over the same storage continues rather than restarting —
      // this is the bug that made every payment go out as NS=000002.
      final reopened = CallbackNapsSequenceStore(
        read: () async => persisted,
        write: (v) async => persisted = v,
      );
      expect(await reopened.next(), 2);
      expect(await reopened.next(), 3);
    });

    test('NS wraps at six digits without ever reaching zero', () {
      expect(NapsSequence.advance(999998), 999999);
      expect(NapsSequence.advance(999999), 1);
      expect(NapsSequence.format(108), '000108');
    });
  });

  group('NCAI validation', () {
    test('a well-formed NCAI has no issue', () {
      expect(NapsSdk.posIdIssue('0100001'), isNull);
    });

    test('a short NCAI is accepted', () {
      // Shorter than seven is a legitimate configuration: the frame builder
      // left-pads it, which is how the field is defined.
      expect(NapsSdk.posIdIssue('12345'), isNull);
      expect(NapsSdk.posIdIssue('1'), isNull);
    });

    test('a short NCAI is left-padded on the wire, not at validation', () {
      final frame = NapsMessage.paymentRequest(
        amountInCents: 200,
        posId: '12345',
        sequenceNumber: 1,
      ).toFrameBytes();
      expect(utf8.decode(frame), contains('0030070012345'));
    });

    test('only empty and non-numeric NCAI are rejected', () {
      expect(NapsSdk.posIdIssue('12A4567'), contains('digits only'));
      expect(NapsSdk.posIdIssue(''), contains('required'));
      // Length is deliberately not validated - any numeric value is accepted.
      expect(NapsSdk.posIdIssue('12345678'), isNull);
    });
  });

  group('Fields after the receipt', () {
    // The terminal is not required to put every scalar ahead of DP. Tag 013
    // (CR) after the receipt used to be dropped, because scanning stopped at
    // the '?' - leaving an empty response code, which reads as a decline for
    // a payment that was approved.
    Uint8List frameWithTrailingTags() => _concat([
      _tlv('001', '101'),
      _tlv('003', '0100001'),
      _tlv('004', '000108'),
      _tlv('002', '000000000022'),
      _dpField(_dpPayload(const ['Naps', 'MERCHANT COPY'])),
      _tlv('013', '000'),
      _tlv('014', '23032026'),
      _tlv('015', '141456'),
    ]);

    test('a tag after the DP terminator is captured, not dropped', () {
      final scan = NapsTlv.scanFrame(frameWithTrailingTags());
      expect(scan.status, NapsScanStatus.complete);
      final msg = NapsMessage.fromScan(scan, frameWithTrailingTags());
      expect(msg.responseCode, '000', reason: 'CR followed the receipt');
      expect(msg.elements.containsKey('014'), isTrue);
      expect(msg.elements.containsKey('015'), isTrue);
    });

    test('the whole frame is consumed', () {
      final f = frameWithTrailingTags();
      expect(NapsTlv.scanFrame(f).end, f.length);
    });

    test('a following frame is still not merged in', () {
      final first = frameWithTrailingTags();
      final second = _concat([
        _tlv('001', '102'),
        _tlv('003', '0100001'),
        _tlv('004', '000109'),
      ]);
      final scan = NapsTlv.scanFrame(_concat([first, second]));
      expect(scan.status, NapsScanStatus.complete);
      expect(scan.end, first.length, reason: 'stops where tag 001 restarts');
      expect(scan.nextFrameStarts, isTrue);
      final msg = NapsMessage.fromScan(scan, first);
      expect(msg.messageType, '101');
      expect(msg.responseCode, '000');
    });

    test('a frame is delimited only once the next one has begun', () {
      final first = frameWithTrailingTags();
      final buffer = NapsFrameBuffer()..add(first);
      // Whole frame present, nothing after it: the boundary is not yet proven,
      // so the caller must let the stream settle.
      expect(buffer.peekFrame()!.delimited, isFalse);

      // Tag 001 of the next response proves the first one ended.
      buffer.add(_tlv('001', '102'));
      final peek = buffer.peekFrame()!;
      expect(peek.delimited, isTrue);
      expect(peek.end, first.length);
      expect(peek.message.responseCode, '000');
    });

    test('a receipt-bearing frame with no trailing tags still completes', () {
      final f = _concat([
        _tlv('001', '101'),
        _tlv('003', '0100001'),
        _tlv('004', '000108'),
        _dpField(_dpPayload(const ['Naps'])),
      ]);
      final scan = NapsTlv.scanFrame(f);
      expect(scan.status, NapsScanStatus.complete);
      expect(scan.dpTerminated, isTrue);
      expect(scan.end, f.length);
    });

    test('trailing tags arriving late are not lost', () {
      // Byte-at-a-time delivery. Once the '?' lands the buffer does report a
      // frame - it cannot know whether anything follows - but it must mark it
      // undelimited so the connection's settle window runs. By the time all
      // the bytes are in, the CR that followed the receipt must be present.
      final f = frameWithTrailingTags();
      final buf = NapsFrameBuffer();
      var earlyDelimited = 0;
      NapsFramePeek? done;
      for (var i = 0; i < f.length; i++) {
        buf.add([f[i]]);
        final peek = buf.peekFrame();
        if (peek == null) continue;
        if (buf.length < f.length) {
          if (peek.delimited) earlyDelimited++;
        } else {
          done = peek;
        }
      }
      expect(
        earlyDelimited,
        0,
        reason: 'a frame that might still be growing was called delimited',
      );
      expect(done, isNotNull);
      expect(done!.end, f.length);
      expect(done.message.responseCode, '000');
      expect(done.message.elements.containsKey('015'), isTrue);
    });
  });
}
