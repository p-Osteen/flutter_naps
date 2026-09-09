import 'package:flutter/material.dart';
import 'package:naps_flutter/naps_flutter.dart';

Future<void> showCancellationDialog({
  required BuildContext context,
  String? initialStan,
  required Future<NapsCancellationInfo> Function(String stan) onLookup,
  required void Function(NapsCancellationInfo info) onConfirmReversal,
}) async {
  final stanController = TextEditingController(text: initialStan ?? '');

  await showDialog<void>(
    context: context,
    builder: (dialogCtx) {
      bool isLookingUp = false;
      NapsCancellationInfo? retrievedInfo;
      String? lookupError;

      return StatefulBuilder(
        builder: (ctx, setDialogState) {
          return AlertDialog(
            backgroundColor: const Color(0xFF0F172A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: const BorderSide(color: Color(0xFF1E2C48)),
            ),
            title: const Row(
              children: [
                Icon(Icons.assignment_return, color: Color(0xFFF97316)),
                SizedBox(width: 10),
                Text(
                  'Void / Cancel Transaction',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 17),
                ),
              ],
            ),
            content: SizedBox(
              width: 440,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Two-step NAPS M2M reversal: TM 003 queries the transaction parameters, followed by TM 004 confirmation to reverse the charge.',
                    style: TextStyle(fontSize: 13, color: Color(0xFF94A3B8)),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: stanController,
                    style: const TextStyle(fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      labelText: 'Transaction STAN (6 digits)',
                      hintText: 'e.g. 000123',
                      suffixIcon: initialStan != null
                          ? IconButton(
                              tooltip: 'Use Last STAN ($initialStan)',
                              icon: const Icon(Icons.history, size: 20),
                              onPressed: () {
                                setDialogState(() {
                                  stanController.text = initialStan;
                                });
                              },
                            )
                          : null,
                    ),
                  ),
                  if (lookupError != null) ...[
                    const SizedBox(height: 12),
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: const Color(0xFFEF4444).withAlpha(25),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: const Color(0xFFEF4444).withAlpha(80),
                        ),
                      ),
                      child: Text(
                        lookupError!,
                        style: const TextStyle(
                          color: Color(0xFFF87171),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                  if (retrievedInfo != null && retrievedInfo!.isFound) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: const Color(0xFF10B981).withAlpha(20),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(
                          color: const Color(0xFF10B981).withAlpha(80),
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Row(
                            children: [
                              Icon(
                                Icons.check_circle,
                                color: Color(0xFF10B981),
                                size: 16,
                              ),
                              SizedBox(width: 6),
                              Text(
                                'Transaction Found (TM 103)',
                                style: TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 13,
                                  color: Color(0xFF34D399),
                                ),
                              ),
                            ],
                          ),
                          const Divider(height: 16, color: Color(0xFF1E2C48)),
                          Text(
                            'Amount: ${(retrievedInfo!.amountInCents / 100).toStringAsFixed(2)} MAD',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            'Card: ${retrievedInfo!.cardNumber}',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                          Text(
                            'Date/Time: ${retrievedInfo!.transactionDate} ${retrievedInfo!.transactionTime}',
                            style: const TextStyle(
                              fontSize: 12,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                          Text(
                            'STAN: ${retrievedInfo!.stan}',
                            style: const TextStyle(
                              fontFamily: 'monospace',
                              fontSize: 12,
                              color: Color(0xFF94A3B8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(dialogCtx).pop(),
                child: const Text('Cancel'),
              ),
              if (retrievedInfo == null || !retrievedInfo!.isFound)
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF10B981),
                    foregroundColor: Colors.black,
                  ),
                  onPressed: isLookingUp
                      ? null
                      : () async {
                          final stan = stanController.text.trim();
                          if (stan.isEmpty) {
                            setDialogState(() {
                              lookupError = 'Please enter a valid STAN';
                            });
                            return;
                          }
                          setDialogState(() {
                            isLookingUp = true;
                            lookupError = null;
                          });

                          try {
                            final info = await onLookup(stan);
                            setDialogState(() {
                              isLookingUp = false;
                              retrievedInfo = info;
                              if (!info.isFound) {
                                lookupError =
                                    'Transaction not found: CR ${info.responseCode} - ${info.userMessage}';
                              }
                            });
                          } catch (e) {
                            setDialogState(() {
                              isLookingUp = false;
                              lookupError = 'Error: $e';
                            });
                          }
                        },
                  child: isLookingUp
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.black,
                          ),
                        )
                      : const Text(
                          'Lookup TM 003',
                          style: TextStyle(fontWeight: FontWeight.bold),
                        ),
                )
              else
                FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFFEF4444),
                    foregroundColor: Colors.white,
                  ),
                  onPressed: () {
                    Navigator.of(dialogCtx).pop();
                    onConfirmReversal(retrievedInfo!);
                  },
                  icon: const Icon(Icons.delete_forever, size: 18),
                  label: const Text(
                    'Execute Reversal (TM 004)',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
            ],
          );
        },
      );
    },
  );
}
