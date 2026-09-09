import 'package:flutter/material.dart';

class AdminServicesCard extends StatelessWidget {
  final TextEditingController duplicateStanController;
  final String? lastStan;
  final bool isProcessing;
  final VoidCallback onRequestDuplicate;
  final VoidCallback onShowCancellationFlow;
  final VoidCallback onRequestTotals;
  final VoidCallback onGetPrintInfo;
  final VoidCallback onResetTerminal;

  const AdminServicesCard({
    super.key,
    required this.duplicateStanController,
    this.lastStan,
    required this.isProcessing,
    required this.onRequestDuplicate,
    required this.onShowCancellationFlow,
    required this.onRequestTotals,
    required this.onGetPrintInfo,
    required this.onResetTerminal,
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
                    Icons.admin_panel_settings_outlined,
                    color: Color(0xFF06B6D4),
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'TERMINAL SERVICES & REVERSALS',
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
                'TM 003 / 008 / 010 / 011 / 012',
                style: TextStyle(
                  fontSize: 10,
                  fontFamily: 'monospace',
                  color: Color(0xFF64748B),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Duplicate by STAN row
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: duplicateStanController,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
                  decoration: InputDecoration(
                    labelText: 'Target STAN for Duplicate (TM 008)',
                    hintText: 'Leave empty for latest terminal receipt',
                    prefixIcon: const Icon(
                      Icons.find_in_page_outlined,
                      size: 18,
                      color: Color(0xFF94A3B8),
                    ),
                    suffixIcon: lastStan != null
                        ? IconButton(
                            tooltip: 'Insert Last STAN ($lastStan)',
                            icon: const Icon(Icons.history, size: 18),
                            onPressed: () {
                              duplicateStanController.text = lastStan!;
                            },
                          )
                        : null,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              SizedBox(
                height: 46,
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF38BDF8),
                    side: const BorderSide(color: Color(0xFF06B6D4)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  onPressed: isProcessing ? null : onRequestDuplicate,
                  icon: const Icon(Icons.copy, size: 16),
                  label: const Text(
                    'Duplicate',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // Action buttons grid
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFF87171),
                    side: const BorderSide(color: Color(0xFFEF4444)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: isProcessing ? null : onShowCancellationFlow,
                  icon: const Icon(Icons.assignment_return_outlined, size: 16),
                  label: const Text(
                    'Void / Refund (TM 003)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFCBD5E1),
                    side: const BorderSide(color: Color(0xFF2A3A54)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: isProcessing ? null : onRequestTotals,
                  icon: const Icon(Icons.receipt_long, size: 16),
                  label: const Text(
                    'Totals (TM 010)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFCBD5E1),
                    side: const BorderSide(color: Color(0xFF2A3A54)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: isProcessing ? null : onGetPrintInfo,
                  icon: const Icon(Icons.print_outlined, size: 16),
                  label: const Text(
                    'Config (TM 011)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFFCBD5E1),
                    side: const BorderSide(color: Color(0xFF2A3A54)),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: isProcessing ? null : onResetTerminal,
                  icon: const Icon(Icons.restart_alt, size: 16),
                  label: const Text(
                    'Reset EPT (TM 012)',
                    style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
