import 'package:flutter/material.dart';
import 'package:naps_flutter/naps_flutter.dart';

void main() {
  runApp(const NapsExampleApp());
}

class NapsExampleApp extends StatelessWidget {
  const NapsExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NAPS Flutter Example',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.teal),
        useMaterial3: true,
      ),
      home: const NapsHomePage(),
    );
  }
}

class NapsHomePage extends StatefulWidget {
  const NapsHomePage({super.key});

  @override
  State<NapsHomePage> createState() => _NapsHomePageState();
}

class _NapsHomePageState extends State<NapsHomePage> {
  final TextEditingController _ipController = TextEditingController(
    text: '192.168.1.26',
  );
  final List<String> _logs = [];
  bool _isProcessing = false;

  void _log(String message) {
    if (!mounted) return;
    setState(() {
      _logs.insert(
        0,
        '${DateTime.now().toLocal().toString().split('.').first}: $message',
      );
    });
  }

  Future<void> _processPayment() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) {
      _log('Please enter a valid IP address.');
      return;
    }

    setState(() {
      _isProcessing = true;
    });

    try {
      _log('Connecting to $ip:4444...');
      final connection = NapsTcpConnection(
        host: ip,
        port: 4444,
        // Every frame in and out, with cardholder fields already masked.
        onFrame: (frame) => _log('$frame'),
      );
      final sdk = NapsSdk(
        connection: connection,
        posId: '0030007', // 7 digits: POS number (2) + cashier station (5)
        // In a real deployment pass a durable store: NS must advance across
        // transactions and restarts, not just within one.
        sequenceStore: InMemoryNapsSequenceStore(),
      );

      if (!await connection.connect()) {
        _log('Could not reach the terminal at $ip:4444');
        return;
      }

      _log('Sending Payment Request (35.00 MAD)...');
      // Nothing slow goes in onApproved: the terminal cancels the transaction
      // if TM 002 does not reach it within 40 seconds. Print from the result
      // after pay() returns instead.
      final response = await sdk.pay(
        amountInCents: 3500, // 35.00 MAD
        autoConfirm: true,
      );

      if (response.isSuccess) {
        _log(
          'Approved and confirmed. STAN ${response.stan}, NS ${response.sequenceNumber}',
        );
        _log(
          'Merchant copy: ${response.merchantReceipt?.lines.length ?? 0} lines',
        );
        _log(
          'Customer copy: ${response.customerReceipt?.lines.length ?? 0} lines',
        );
      } else if (response.requiresReconciliation) {
        // The card was approved but the confirmation did not land. This is
        // not a decline: the money may have moved.
        _log('APPROVED BUT NOT CONFIRMED — reconcile this transaction.');
        _log('  NS ${response.sequenceNumber}  STAN ${response.stan}');
        _log(
          '  payment CR ${response.responseCode}, '
          'confirmation CR ${response.confirmationResponseCode}',
        );
        _log('  reason: ${response.failureReason.name}');
      } else {
        _log(
          'Not completed: ${response.responseCode} '
          '(${response.failureReason.name}) - ${response.userMessage}',
        );
      }
    } catch (e) {
      _log('Error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<void> _requestTotals() async {
    final ip = _ipController.text.trim();
    if (ip.isEmpty) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final connection = NapsTcpConnection(host: ip, port: 4444);
      final sdk = NapsSdk(connection: connection, posId: '0030007');

      if (!await connection.connect()) {
        _log('Could not reach the terminal at $ip:4444');
        return;
      }

      _log('Requesting Totals...');
      final totals = await sdk.getTotals();
      if (totals.isSuccess) {
        _log(
          'Totals receipt received (${totals.receipt?.lines.length ?? 0} lines)',
        );
      } else {
        // The result says *why*, rather than collapsing everything to null.
        _log(
          'No totals: CR ${totals.responseCode} '
          '(${totals.failureReason.name}) — ${totals.description}',
        );
      }
    } catch (e) {
      _log('Error: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('NAPS SDK Example'),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: Center(
        child: ConstrainedBox(
          // Responsive: constrain width on large screens (tablets/windows)
          constraints: const BoxConstraints(maxWidth: 600),
          child: Padding(
            padding: const EdgeInsets.all(16.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  'Terminal Settings (Wi-Fi)',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _ipController,
                  decoration: const InputDecoration(
                    labelText: 'Terminal IP Address',
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.wifi),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 16,
                  runSpacing: 16,
                  alignment: WrapAlignment.center,
                  children: [
                    FilledButton.icon(
                      onPressed: _isProcessing ? null : _processPayment,
                      icon: _isProcessing
                          ? const SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.payment),
                      label: const Text('Pay 35.00 MAD'),
                    ),
                    OutlinedButton.icon(
                      onPressed: _isProcessing ? null : _requestTotals,
                      icon: const Icon(Icons.receipt_long),
                      label: const Text('Get Totals'),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const Text(
                  'Transaction Logs',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: Container(
                    decoration: BoxDecoration(
                      color: Colors.black87,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    padding: const EdgeInsets.all(12),
                    child: ListView.builder(
                      itemCount: _logs.length,
                      itemBuilder: (context, index) {
                        return Padding(
                          padding: const EdgeInsets.only(bottom: 4.0),
                          child: Text(
                            _logs[index],
                            style: const TextStyle(
                              color: Colors.greenAccent,
                              fontFamily: 'monospace',
                              fontSize: 13,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
