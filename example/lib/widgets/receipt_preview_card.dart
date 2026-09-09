import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:naps_flutter/naps_flutter.dart';

class ReceiptPreviewCard extends StatelessWidget {
  final NapsReceipt? displayedReceipt;
  final String receiptTitle;
  final NapsTransactionResult? lastPayment;
  final void Function(NapsReceipt receipt, String title) onSelectReceipt;

  const ReceiptPreviewCard({
    super.key,
    required this.displayedReceipt,
    required this.receiptTitle,
    this.lastPayment,
    required this.onSelectReceipt,
  });

  @override
  Widget build(BuildContext context) {
    final receipt = displayedReceipt;
    if (receipt == null) {
      return Center(
        child: Container(
          margin: const EdgeInsets.all(20),
          padding: const EdgeInsets.all(28),
          decoration: BoxDecoration(
            color: const Color(0xFF0E1626),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF1E2C48)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF131D33),
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF1E2C48)),
                ),
                child: const Icon(
                  Icons.receipt_long_outlined,
                  size: 38,
                  color: Color(0xFF64748B),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'No Receipt Available',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'Execute a Payment (TM 001), Duplicate Reprint (TM 008), or Totals Report (TM 010) to render and inspect the authentic thermal receipt slip.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 12,
                  color: Color(0xFF94A3B8),
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      );
    }

    final fields = receipt.extractFields();

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0E1626),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E2C48)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Header Bar
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: const BoxDecoration(
              color: Color(0xFF131E33),
              borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(
                      Icons.receipt,
                      size: 18,
                      color: Color(0xFF10B981),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      receiptTitle.toUpperCase(),
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        fontSize: 12,
                        letterSpacing: 1.1,
                        color: Colors.white,
                      ),
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(
                        Icons.copy,
                        size: 16,
                        color: Color(0xFF94A3B8),
                      ),
                      tooltip: 'Copy Receipt Text',
                      onPressed: () {
                        final raw = receipt.lines.map((l) => l.text).join('\n');
                        Clipboard.setData(ClipboardData(text: raw));
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('Receipt text copied')),
                        );
                      },
                    ),
                    if (lastPayment != null &&
                        lastPayment!.merchantReceipt != null &&
                        lastPayment!.customerReceipt != null) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.all(2),
                        decoration: BoxDecoration(
                          color: const Color(0xFF090E18),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Row(
                          children: [
                            InkWell(
                              onTap: () => onSelectReceipt(
                                lastPayment!.customerReceipt!,
                                'Customer Receipt',
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      displayedReceipt ==
                                          lastPayment!.customerReceipt
                                      ? const Color(0xFF10B981)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Customer',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color:
                                        displayedReceipt ==
                                            lastPayment!.customerReceipt
                                        ? Colors.black
                                        : const Color(0xFF94A3B8),
                                  ),
                                ),
                              ),
                            ),
                            InkWell(
                              onTap: () => onSelectReceipt(
                                lastPayment!.merchantReceipt!,
                                'Merchant Receipt',
                              ),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color:
                                      displayedReceipt ==
                                          lastPayment!.merchantReceipt
                                      ? const Color(0xFF10B981)
                                      : Colors.transparent,
                                  borderRadius: BorderRadius.circular(4),
                                ),
                                child: Text(
                                  'Merchant',
                                  style: TextStyle(
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    color:
                                        displayedReceipt ==
                                            lastPayment!.merchantReceipt
                                        ? Colors.black
                                        : const Color(0xFF94A3B8),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
              ],
            ),
          ),

          // Extracted Fields Pill Bar
          if (fields.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              color: const Color(0xFF090E18),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: fields.entries.take(5).map((e) {
                  return Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 3,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFF131E33),
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: const Color(0xFF1E2C48)),
                    ),
                    child: Text(
                      '${e.key}: ${e.value}',
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFE2E8F0),
                        fontFamily: 'monospace',
                      ),
                    ),
                  );
                }).toList(),
              ),
            ),
          const Divider(height: 1, color: Color(0xFF1E2C48)),

          // Authentic Thermal Slip Body
          Expanded(
            child: Container(
              color: const Color(0xFF080C14),
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
              child: Center(
                child: Container(
                  constraints: const BoxConstraints(maxWidth: 380),
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF9F9F6), // Warm Ivory Thermal Slip
                    borderRadius: BorderRadius.circular(8),
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withAlpha(120),
                        blurRadius: 12,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: ListView.builder(
                    itemCount: receipt.lines.length,
                    itemBuilder: (context, index) {
                      final line = receipt.lines[index];
                      final isCenter = line.alignment == NapsAlignment.center;
                      final isRight = line.alignment == NapsAlignment.right;
                      final isBold = line.format == NapsPrintFormat.bold;

                      return Text(
                        line.text.isEmpty ? ' ' : line.text,
                        textAlign: isCenter
                            ? TextAlign.center
                            : isRight
                            ? TextAlign.right
                            : TextAlign.left,
                        style: TextStyle(
                          fontFamily: 'monospace',
                          fontSize: isBold ? 12.5 : 11.5,
                          fontWeight: isBold
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: const Color(0xFF111827),
                          height: 1.3,
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
