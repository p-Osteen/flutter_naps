import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:naps_flutter/naps_flutter.dart';

import '../constants/tag_descriptions.dart';
import '../models/log_item.dart';

void showFrameInspectorSheet(BuildContext context, LogItem logItem) {
  final msg = logItem.rawMessage;
  final frame = logItem.frameLog;
  if (msg == null && frame == null) return;

  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      return Container(
        height: MediaQuery.of(context).size.height * 0.8,
        decoration: const BoxDecoration(
          color: Color(0xFF0F172A),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
          border: Border(top: BorderSide(color: Color(0xFF334155))),
        ),
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Title Bar
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: logItem.direction == NapsFrameDirection.outbound
                            ? const Color(0xFF06B6D4).withAlpha(30)
                            : const Color(0xFFF59E0B).withAlpha(30),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        logItem.direction == NapsFrameDirection.outbound
                            ? Icons.arrow_upward
                            : Icons.arrow_downward,
                        color: logItem.direction == NapsFrameDirection.outbound
                            ? const Color(0xFF06B6D4)
                            : const Color(0xFFF59E0B),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          msg != null
                              ? 'Frame Telemetry: TM ${msg.messageType}'
                              : 'Wire Payload: ${frame?.byteLength ?? 0} Bytes',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 18,
                            color: Colors.white,
                          ),
                        ),
                        Text(
                          logItem.direction == NapsFrameDirection.outbound
                              ? 'HOST → TERMINAL (OUTBOUND)'
                              : 'TERMINAL → HOST (INBOUND)',
                          style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF94A3B8),
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close, color: Color(0xFF94A3B8)),
                  onPressed: () => Navigator.of(ctx).pop(),
                ),
              ],
            ),
            const SizedBox(height: 14),

            // Metadata Badges
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                if (msg != null) ...[
                  _buildBadge('NS: ${msg.sequenceNumber ?? 'N/A'}'),
                  _buildBadge('POS ID: ${msg.posId}'),
                  if (msg.responseCode.isNotEmpty)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: msg.responseCode == '000'
                            ? const Color(0xFF10B981).withAlpha(35)
                            : const Color(0xFFEF4444).withAlpha(35),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: msg.responseCode == '000'
                              ? const Color(0xFF10B981)
                              : const Color(0xFFEF4444),
                        ),
                      ),
                      child: Text(
                        'CR: ${msg.responseCode}',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: msg.responseCode == '000'
                              ? const Color(0xFF34D399)
                              : const Color(0xFFF87171),
                        ),
                      ),
                    ),
                  _buildBadge('${msg.elements.length} TLV Fields'),
                ],
                if (frame != null) ...[
                  _buildBadge('${frame.byteLength} Bytes'),
                  if (frame.bufferedAfter > 0)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.orange.withAlpha(35),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.orange),
                      ),
                      child: Text(
                        'Buffered: ${frame.bufferedAfter}B',
                        style: const TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: Colors.orangeAccent,
                        ),
                      ),
                    ),
                ],
              ],
            ),
            const SizedBox(height: 16),

            // Main Content
            Expanded(
              child: ListView(
                children: [
                  if (frame != null) ...[
                    const Text(
                      'Wire TLV Breakdown',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF94A3B8),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF0B1120),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF1E2C48)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: SelectableText(
                              frame.tlv,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: Color(0xFFE2E8F0),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.copy,
                              size: 16,
                              color: Color(0xFF94A3B8),
                            ),
                            tooltip: 'Copy TLV Breakdown',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: frame.tlv));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Copied TLV summary'),
                                ),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    const Text(
                      'Redacted Wire Hex',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF94A3B8),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF070B14),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: const Color(0xFF1E2C48)),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: SelectableText(
                              frame.hex,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: Color(0xFF34D399),
                              ),
                            ),
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.copy,
                              size: 16,
                              color: Color(0xFF94A3B8),
                            ),
                            tooltip: 'Copy Hex',
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: frame.hex));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(content: Text('Copied Hex')),
                              );
                            },
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],
                  if (msg != null) ...[
                    const Text(
                      'Parsed TLV Structure',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF94A3B8),
                        letterSpacing: 0.5,
                      ),
                    ),
                    const SizedBox(height: 8),
                    ...msg.elements.entries.map((entry) {
                      final tagKey = entry.key;
                      final elem = entry.value;
                      final tagDescription =
                          kTagDescriptions[tagKey] ?? 'Unknown Tag';

                      return Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0B1120),
                          border: Border.all(color: const Color(0xFF1E2C48)),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF10B981,
                                    ).withAlpha(30),
                                    borderRadius: BorderRadius.circular(6),
                                    border: Border.all(
                                      color: const Color(
                                        0xFF10B981,
                                      ).withAlpha(80),
                                    ),
                                  ),
                                  child: Text(
                                    'TAG $tagKey',
                                    style: const TextStyle(
                                      fontFamily: 'monospace',
                                      fontWeight: FontWeight.bold,
                                      fontSize: 11,
                                      color: Color(0xFF34D399),
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    tagDescription,
                                    style: const TextStyle(
                                      fontWeight: FontWeight.w600,
                                      fontSize: 13,
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                                Text(
                                  '${elem.length} chars (${elem.valueBytes.length}B)',
                                  style: const TextStyle(
                                    fontSize: 11,
                                    color: Color(0xFF64748B),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 6),
                            SelectableText(
                              elem.value.isEmpty ? '(empty)' : elem.value,
                              style: const TextStyle(
                                fontFamily: 'monospace',
                                fontSize: 12,
                                color: Color(0xFFCBD5E1),
                              ),
                            ),
                          ],
                        ),
                      );
                    }),
                  ],
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
}

Widget _buildBadge(String text) {
  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
    decoration: BoxDecoration(
      color: const Color(0xFF1E293B),
      borderRadius: BorderRadius.circular(8),
      border: Border.all(color: const Color(0xFF334155)),
    ),
    child: Text(
      text,
      style: const TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        color: Color(0xFFE2E8F0),
      ),
    ),
  );
}
