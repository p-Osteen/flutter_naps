import 'package:flutter/material.dart';

import '../models/pending_confirmation.dart';

class OperationsCard extends StatelessWidget {
  final TextEditingController amountController;
  final bool autoConfirm;
  final ValueChanged<bool> onAutoConfirmChanged;
  final PendingManualConfirmation? pendingConfirmation;
  final int secondsRemaining;
  final VoidCallback onManualConfirm;
  final VoidCallback onAbortManualConfirm;
  final bool isProcessing;
  final String currentOperation;
  final VoidCallback? onCancelPayment;
  final VoidCallback onInitiatePayment;

  const OperationsCard({
    super.key,
    required this.amountController,
    required this.autoConfirm,
    required this.onAutoConfirmChanged,
    required this.pendingConfirmation,
    required this.secondsRemaining,
    required this.onManualConfirm,
    required this.onAbortManualConfirm,
    required this.isProcessing,
    required this.currentOperation,
    this.onCancelPayment,
    required this.onInitiatePayment,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0E1626),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E2C48)),
      ),
      padding: const EdgeInsets.all(18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    Icons.payments_outlined,
                    color: Color(0xFF10B981),
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'TRANSACTION DESK',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      letterSpacing: 1.1,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              Text(
                'M2M TM 001 // TM 002',
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Amount Box (Prominent Hero Display)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF090E18),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: const Color(0xFF1E2C48)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF10B981).withAlpha(20),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Text(
                    'MAD',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.w900,
                      color: Color(0xFF34D399),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: TextField(
                    controller: amountController,
                    keyboardType: const TextInputType.numberWithOptions(
                      decimal: true,
                    ),
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                      fontFamily: 'monospace',
                      color: Colors.white,
                    ),
                    decoration: const InputDecoration(
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      hintText: '0.00',
                      contentPadding: EdgeInsets.zero,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),

          // Sleek Preset Amount Buttons
          Row(
            children: ['10.00', '25.00', '50.00', '100.00', '250.00'].map((
              amt,
            ) {
              final isCur = amountController.text.trim() == amt;
              return Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: InkWell(
                    onTap: () => amountController.text = amt,
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: isCur
                            ? const Color(0xFF10B981).withAlpha(30)
                            : const Color(0xFF131D33),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: isCur
                              ? const Color(0xFF10B981)
                              : const Color(0xFF1E2C48),
                        ),
                      ),
                      child: Center(
                        child: Text(
                          amt,
                          style: TextStyle(
                            fontFamily: 'monospace',
                            fontSize: 12,
                            fontWeight: isCur
                                ? FontWeight.bold
                                : FontWeight.w600,
                            color: isCur
                                ? const Color(0xFF34D399)
                                : const Color(0xFFCBD5E1),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 14),

          // Auto-confirm switch card
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0xFF0B1120),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF1E2C48)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Auto-Confirm TM 002',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Colors.white,
                        ),
                      ),
                      Text(
                        'Automatically dispatches TM 002 confirmation within 40s budget',
                        style: TextStyle(
                          fontSize: 11,
                          color: Color(0xFF94A3B8),
                        ),
                      ),
                    ],
                  ),
                ),
                Switch(
                  activeTrackColor: const Color(0xFF10B981),
                  activeThumbColor: Colors.white,
                  value: autoConfirm,
                  onChanged: onAutoConfirmChanged,
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Active 40s confirmation countdown banner
          if (pendingConfirmation != null) ...[
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFFF59E0B).withAlpha(20),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFF59E0B), width: 1.5),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Row(
                        children: [
                          const Icon(
                            Icons.hourglass_top,
                            color: Color(0xFFF59E0B),
                            size: 18,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            'CONFIRMATION PENDING (${secondsRemaining}s)',
                            style: const TextStyle(
                              fontWeight: FontWeight.w900,
                              fontSize: 13,
                              letterSpacing: 0.8,
                              color: Color(0xFFFBBF24),
                            ),
                          ),
                        ],
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: const Color(0xFF0F172A),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          'STAN: ${pendingConfirmation!.stan}',
                          style: const TextStyle(
                            fontFamily: 'monospace',
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                            color: Colors.white,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Card authorized by terminal. Confirming now finalizes the debit; omitting TM 002 triggers an automatic reversal after 40 seconds.',
                    style: TextStyle(fontSize: 12, color: Color(0xFFCBD5E1)),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(
                            backgroundColor: const Color(0xFF10B981),
                            foregroundColor: Colors.black,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          onPressed: isProcessing ? null : onManualConfirm,
                          icon: const Icon(Icons.check, size: 18),
                          label: const Text(
                            'Send TM 002 (Confirm)',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          foregroundColor: const Color(0xFFF87171),
                          side: const BorderSide(color: Color(0xFFEF4444)),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(8),
                          ),
                          padding: const EdgeInsets.symmetric(vertical: 12),
                        ),
                        onPressed: onAbortManualConfirm,
                        child: const Text('Abort'),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Active payment progress banner
          if (isProcessing) ...[
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF090E18),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(
                  color: const Color(0xFF10B981).withAlpha(80),
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.2,
                      color: Color(0xFF10B981),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      currentOperation,
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF34D399),
                      ),
                    ),
                  ),
                  if (onCancelPayment != null)
                    TextButton.icon(
                      style: TextButton.styleFrom(
                        foregroundColor: const Color(0xFFEF4444),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      onPressed: onCancelPayment,
                      icon: const Icon(Icons.cancel, size: 16),
                      label: const Text(
                        'Cancel',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],

          // Master Primary CTA: INITIATE PAYMENT
          SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF10B981),
                foregroundColor: Colors.black,
                elevation: 6,
                shadowColor: const Color(0xFF10B981).withAlpha(80),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              onPressed: isProcessing ? null : onInitiatePayment,
              icon: const Icon(Icons.contactless, size: 22),
              label: const Text(
                'INITIATE PAYMENT (TM 001)',
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 1.1,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
