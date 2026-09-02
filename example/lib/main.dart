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
  final TextEditingController _ipController = TextEditingController(text: '192.168.1.26');
  final List<String> _logs = [];
  bool _isProcessing = false;

  void _log(String message) {
    if (!mounted) return;
    setState(() {
      _logs.insert(0, '${DateTime.now().toLocal().toString().split('.').first}: $message');
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
      final connection = NapsTcpConnection(host: ip, port: 4444);
      final sdk = NapsSdk(
        connection: connection,
        posId: '0030007', // 7 chars: cash register (3) + cashier (4)
      );

      _log('Sending Payment Request (35.00 MAD)...');
      final response = await sdk.pay(
        amountInCents: 3500, // 35.00 MAD
        autoConfirm: true,
        onApproved: (result) async {
          _log('Payment Approved! STAN: ${result.stan}');
          if (result.merchantReceipt != null) {
            _log('Merchant Receipt received (${result.merchantReceipt!.lines.length} lines).');
          }
        },
      );

      if (response.isSuccess) {
        _log('Transaction completed successfully!');
        if (response.customerReceipt != null) {
          _log('Customer Receipt received.');
        }
      } else {
        _log('Transaction failed: ${response.responseCode} - ${response.userMessage}');
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
      final sdk = NapsSdk(
        connection: connection,
        posId: '0030007',
      );

      _log('Requesting Totals...');
      final receipt = await sdk.getTotals();
      if (receipt != null) {
        _log('Totals receipt received! (${receipt.lines.length} lines)');
      } else {
        _log('No totals returned or request failed.');
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
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
