import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:naps_flutter/naps_flutter.dart';

void main() {
  runApp(const NapsExampleApp());
}

class NapsExampleApp extends StatelessWidget {
  const NapsExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NAPS SUNMI P2 Terminal Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E), // Teal/Emerald
          brightness: Brightness.light,
        ),
      ),
      darkTheme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF0F766E),
          brightness: Brightness.dark,
        ),
      ),
      themeMode: ThemeMode.system,
      home: const NapsDashboardPage(),
    );
  }
}

enum ConnectionType { tcp, serial }

class LogItem {
  final DateTime timestamp;
  final String text;
  final NapsFrameDirection? direction;
  final bool isError;
  final bool isSuccess;

  const LogItem({
    required this.timestamp,
    required this.text,
    this.direction,
    this.isError = false,
    this.isSuccess = false,
  });
}

class NapsDashboardPage extends StatefulWidget {
  const NapsDashboardPage({super.key});

  @override
  State<NapsDashboardPage> createState() => _NapsDashboardPageState();
}

class _NapsDashboardPageState extends State<NapsDashboardPage> {
  ConnectionType _connectionType = ConnectionType.tcp;

  // TCP settings
  final TextEditingController _ipController = TextEditingController(
    text: '192.168.1.26',
  );
  final TextEditingController _portController = TextEditingController(
    text: '4444',
  );

  // Serial settings
  final TextEditingController _serialPortController = TextEditingController(
    text: 'COM1',
  );
  int _baudRate = 9600;

  // POS settings
  final TextEditingController _posIdController = TextEditingController(
    text: '0030007',
  );

  // Operation settings
  final TextEditingController _amountController = TextEditingController(
    text: '35.00',
  );
  bool _autoConfirm = true;

  // Execution state
  bool _isProcessing = false;
  String _currentOperation = '';
  NapsCancelToken? _cancelToken;

  // Last transaction & receipt
  NapsTransactionResult? _lastPayment;
  NapsReceipt? _displayedReceipt;
  String _receiptTitle = '';

  // Frame and event logs
  final List<LogItem> _logs = [];

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _ipController.dispose();
    _portController.dispose();
    _serialPortController.dispose();
    _posIdController.dispose();
    _amountController.dispose();
    super.dispose();
  }

  void _log(
    String message, {
    NapsFrameDirection? direction,
    bool isError = false,
    bool isSuccess = false,
  }) {
    if (!mounted) return;
    setState(() {
      _logs.insert(
        0,
        LogItem(
          timestamp: DateTime.now(),
          text: message,
          direction: direction,
          isError: isError,
          isSuccess: isSuccess,
        ),
      );
    });
  }

  NapsConnection _createConnection() {
    if (_connectionType == ConnectionType.tcp) {
      final host = _ipController.text.trim();
      final port = int.tryParse(_portController.text.trim()) ?? 4444;
      return NapsTcpConnection(
        host: host,
        port: port,
        onFrame: (frame) => _log(frame.toString(), direction: frame.direction),
      );
    } else {
      final portName = _serialPortController.text.trim();
      return NapsSerialConnection(
        portName: portName,
        baudRate: _baudRate,
        onFrame: (frame) => _log(frame.toString(), direction: frame.direction),
      );
    }
  }

  NapsSdk _createSdk(NapsConnection connection) {
    return NapsSdk(
      connection: connection,
      posId: _posIdController.text.trim(),
      sequenceStore: InMemoryNapsSequenceStore(),
    );
  }

  Future<void> _pingTerminal() async {
    final posIssue = NapsSdk.posIdIssue(_posIdController.text.trim());
    if (posIssue != null) {
      _log('Invalid POS ID: $posIssue', isError: true);
      return;
    }

    setState(() {
      _isProcessing = true;
      _currentOperation = 'Testing link (Ping TM 009)...';
    });

    final connection = _createConnection();
    final sdk = _createSdk(connection);

    try {
      _log('Connecting via ${connection.transportDescription}...');
      if (!await connection.connect()) {
        _log('Could not connect to terminal', isError: true);
        return;
      }

      _log('Sending Network Test (TM 009)...');
      final result = await sdk.networkTest();
      if (result.isSuccess) {
        _log(
          'Terminal reachable! Response: ${result.description}',
          isSuccess: true,
        );
      } else {
        _log(
          'Network test declined/failed: CR ${result.responseCode} (${result.failureReason.name}) - ${result.userMessage}',
          isError: true,
        );
      }
    } catch (e) {
      _log('Error during network test: $e', isError: true);
    } finally {
      await connection.disconnect();
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _currentOperation = '';
        });
      }
    }
  }

  Future<void> _processPayment() async {
    final posIssue = NapsSdk.posIdIssue(_posIdController.text.trim());
    if (posIssue != null) {
      _log('Invalid POS ID: $posIssue', isError: true);
      return;
    }

    final amountText = _amountController.text.replaceAll(',', '.').trim();
    final amountDouble = double.tryParse(amountText);
    if (amountDouble == null || amountDouble <= 0) {
      _log('Please enter a valid positive amount', isError: true);
      return;
    }
    final amountInCents = (amountDouble * 100).round();

    final cancelToken = NapsCancelToken();
    setState(() {
      _isProcessing = true;
      _currentOperation = 'Payment in progress ($amountText MAD)...';
      _cancelToken = cancelToken;
    });

    final connection = _createConnection();
    final sdk = _createSdk(connection);

    try {
      _log('Connecting via ${connection.transportDescription}...');
      if (!await connection.connect()) {
        _log('Could not connect to terminal', isError: true);
        return;
      }

      _log(
        'Sending Payment TM 001 for $amountText MAD (autoConfirm=$_autoConfirm)...',
      );
      final result = await sdk.pay(
        amountInCents: amountInCents,
        autoConfirm: _autoConfirm,
        cancelToken: cancelToken,
      );

      setState(() {
        _lastPayment = result;
        if (result.customerReceipt != null) {
          _displayedReceipt = result.customerReceipt;
          _receiptTitle = 'Customer Receipt';
        } else if (result.merchantReceipt != null) {
          _displayedReceipt = result.merchantReceipt;
          _receiptTitle = 'Merchant Receipt';
        }
      });

      if (result.isSuccess) {
        _log(
          'Payment Approved & Confirmed! STAN=${result.stan}, Auth=${result.authorizationNumber}, Card=${result.cardNumber}',
          isSuccess: true,
        );
      } else if (result.requiresReconciliation) {
        _log(
          'CRITICAL: Approved but NOT confirmed! Money may have moved. Reconcile STAN=${result.stan}, NS=${result.sequenceNumber}. Reason: ${result.failureReason.name}',
          isError: true,
        );
      } else if (result.source == NapsResultSource.cancelled) {
        _log('Payment aborted by user.', isError: false);
      } else {
        _log(
          'Payment declined/failed: CR ${result.responseCode} (${result.failureReason.name}) - ${result.userMessage}',
          isError: true,
        );
      }
    } catch (e) {
      _log('Payment exception: $e', isError: true);
    } finally {
      await connection.disconnect();
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _currentOperation = '';
          _cancelToken = null;
        });
      }
    }
  }

  Future<void> _requestDuplicate() async {
    setState(() {
      _isProcessing = true;
      _currentOperation = 'Requesting duplicate receipt (TM 005)...';
    });

    final connection = _createConnection();
    final sdk = _createSdk(connection);

    try {
      if (!await connection.connect()) {
        _log('Could not connect to terminal', isError: true);
        return;
      }

      _log('Requesting Duplicate Receipt (TM 005)...');
      final result = await sdk.getDuplicate();
      if (result.isSuccess && result.receipt != null) {
        setState(() {
          _displayedReceipt = result.receipt;
          _receiptTitle = 'Duplicate Receipt';
        });
        _log(
          'Duplicate receipt received (${result.receipt!.lines.length} lines)',
          isSuccess: true,
        );
      } else {
        _log(
          'Duplicate failed: CR ${result.responseCode} (${result.failureReason.name}) - ${result.userMessage}',
          isError: true,
        );
      }
    } catch (e) {
      _log('Duplicate error: $e', isError: true);
    } finally {
      await connection.disconnect();
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _currentOperation = '';
        });
      }
    }
  }

  Future<void> _requestTotals() async {
    setState(() {
      _isProcessing = true;
      _currentOperation = 'Requesting batch totals (TM 006)...';
    });

    final connection = _createConnection();
    final sdk = _createSdk(connection);

    try {
      if (!await connection.connect()) {
        _log('Could not connect to terminal', isError: true);
        return;
      }

      _log('Requesting Batch Totals (TM 006)...');
      final result = await sdk.getTotals();
      if (result.isSuccess && result.receipt != null) {
        setState(() {
          _displayedReceipt = result.receipt;
          _receiptTitle = 'Batch Totals Receipt';
        });
        _log(
          'Totals receipt received (${result.receipt!.lines.length} lines)',
          isSuccess: true,
        );
      } else {
        _log(
          'Totals failed: CR ${result.responseCode} (${result.failureReason.name}) - ${result.userMessage}',
          isError: true,
        );
      }
    } catch (e) {
      _log('Totals error: $e', isError: true);
    } finally {
      await connection.disconnect();
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _currentOperation = '';
        });
      }
    }
  }

  Future<void> _resetTerminal() async {
    setState(() {
      _isProcessing = true;
      _currentOperation = 'Resetting EPT (TM 008)...';
    });

    final connection = _createConnection();
    final sdk = _createSdk(connection);

    try {
      if (!await connection.connect()) {
        _log('Could not connect to terminal', isError: true);
        return;
      }

      _log('Resetting Terminal EPT (TM 008)...');
      final result = await sdk.resetEpt();
      if (result.isSuccess) {
        _log(
          'Terminal reset acknowledged: ${result.description}',
          isSuccess: true,
        );
      } else {
        _log(
          'Reset failed: CR ${result.responseCode} (${result.failureReason.name}) - ${result.userMessage}',
          isError: true,
        );
      }
    } catch (e) {
      _log('Reset error: $e', isError: true);
    } finally {
      await connection.disconnect();
      if (mounted) {
        setState(() {
          _isProcessing = false;
          _currentOperation = '';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.point_of_sale, size: 24),
            SizedBox(width: 8),
            Text('NAPS SUNMI P2 Studio'),
          ],
        ),
        actions: [
          IconButton(
            tooltip: 'Clear Logs',
            icon: const Icon(Icons.delete_outline),
            onPressed: () => setState(() => _logs.clear()),
          ),
          IconButton(
            tooltip: 'Copy Logs',
            icon: const Icon(Icons.copy_all),
            onPressed: () {
              final text = _logs
                  .map((e) => '${e.timestamp.toIso8601String()} ${e.text}')
                  .join('\n');
              Clipboard.setData(ClipboardData(text: text));
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Logs copied to clipboard')),
              );
            },
          ),
        ],
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final isWide = constraints.maxWidth > 900;
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1300),
              child: isWide
                  ? Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          flex: 5,
                          child: SingleChildScrollView(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              children: [
                                _buildConnectionCard(theme),
                                const SizedBox(height: 16),
                                _buildOperationsCard(theme),
                              ],
                            ),
                          ),
                        ),
                        Expanded(
                          flex: 5,
                          child: Padding(
                            padding: const EdgeInsets.only(
                              top: 16,
                              right: 16,
                              bottom: 16,
                            ),
                            child: Column(
                              children: [
                                if (_displayedReceipt != null) ...[
                                  Expanded(
                                    flex: 5,
                                    child: _buildReceiptCard(theme),
                                  ),
                                  const SizedBox(height: 16),
                                ],
                                Expanded(
                                  flex: 5,
                                  child: _buildLogTerminal(isDark),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    )
                  : SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        children: [
                          _buildConnectionCard(theme),
                          const SizedBox(height: 16),
                          _buildOperationsCard(theme),
                          if (_displayedReceipt != null) ...[
                            const SizedBox(height: 16),
                            SizedBox(
                              height: 380,
                              child: _buildReceiptCard(theme),
                            ),
                          ],
                          const SizedBox(height: 16),
                          SizedBox(
                            height: 350,
                            child: _buildLogTerminal(isDark),
                          ),
                        ],
                      ),
                    ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildConnectionCard(ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.settings_ethernet, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Connection & Terminal Settings',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            SegmentedButton<ConnectionType>(
              segments: const [
                ButtonSegment(
                  value: ConnectionType.tcp,
                  label: Text('TCP/IP (Wi-Fi)'),
                  icon: Icon(Icons.wifi),
                ),
                ButtonSegment(
                  value: ConnectionType.serial,
                  label: Text('Serial (USB-C / COM)'),
                  icon: Icon(Icons.usb),
                ),
              ],
              selected: {_connectionType},
              onSelectionChanged: (set) {
                setState(() => _connectionType = set.first);
              },
            ),
            const SizedBox(height: 16),
            if (_connectionType == ConnectionType.tcp) ...[
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _ipController,
                      decoration: const InputDecoration(
                        labelText: 'Terminal IP',
                        hintText: '192.168.1.26',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.router),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: TextField(
                      controller: _portController,
                      keyboardType: TextInputType.number,
                      decoration: const InputDecoration(
                        labelText: 'Port',
                        hintText: '4444',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: _serialPortController,
                      decoration: const InputDecoration(
                        labelText: 'Serial Port',
                        hintText: 'COM1 or /dev/ttyUSB0',
                        border: OutlineInputBorder(),
                        prefixIcon: Icon(Icons.usb),
                        isDense: true,
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<int>(
                      initialValue: _baudRate,
                      decoration: const InputDecoration(
                        labelText: 'Baud Rate',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      items: const [9600, 19200, 38400, 57600, 115200]
                          .map(
                            (b) =>
                                DropdownMenuItem(value: b, child: Text('$b')),
                          )
                          .toList(),
                      onChanged: (val) {
                        if (val != null) setState(() => _baudRate = val);
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Wrap(
                spacing: 6,
                children:
                    [
                      'COM1',
                      'COM2',
                      'COM3',
                      '/dev/ttyUSB0',
                      '/dev/ttyACM0',
                    ].map((port) {
                      return ActionChip(
                        visualDensity: VisualDensity.compact,
                        label: Text(port, style: const TextStyle(fontSize: 11)),
                        onPressed: () =>
                            setState(() => _serialPortController.text = port),
                      );
                    }).toList(),
              ),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _posIdController,
                    decoration: const InputDecoration(
                      labelText: 'POS Station ID (7-8 digits)',
                      hintText: '0030007',
                      border: OutlineInputBorder(),
                      prefixIcon: Icon(Icons.badge),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                FilledButton.tonalIcon(
                  onPressed: _isProcessing ? null : _pingTerminal,
                  icon: const Icon(Icons.network_ping),
                  label: const Text('Test Link'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOperationsCard(ThemeData theme) {
    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.payment, color: theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  'Transaction Operations',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            TextField(
              controller: _amountController,
              keyboardType: const TextInputType.numberWithOptions(
                decimal: true,
              ),
              style: theme.textTheme.headlineMedium?.copyWith(
                fontWeight: FontWeight.bold,
              ),
              decoration: const InputDecoration(
                labelText: 'Payment Amount (MAD)',
                border: OutlineInputBorder(),
                prefixText: 'MAD ',
                prefixIcon: Icon(Icons.attach_money),
              ),
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: ['10.00', '25.00', '35.00', '50.00', '100.00'].map((
                amount,
              ) {
                return ActionChip(
                  label: Text('$amount MAD'),
                  onPressed: () =>
                      setState(() => _amountController.text = amount),
                );
              }).toList(),
            ),
            const SizedBox(height: 12),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Auto-Confirm Payment (TM 002)'),
              subtitle: const Text(
                'Automatically confirms terminal authorization within 40s budget',
              ),
              value: _autoConfirm,
              onChanged: (val) => setState(() => _autoConfirm = val),
            ),
            const SizedBox(height: 16),
            if (_isProcessing) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  children: [
                    const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2.5),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        _currentOperation,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onPrimaryContainer,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    if (_cancelToken != null)
                      TextButton.icon(
                        onPressed: () {
                          _cancelToken?.cancel();
                          _log('Cancelling payment via CancelToken...');
                        },
                        icon: const Icon(Icons.cancel, color: Colors.red),
                        label: const Text(
                          'Abort',
                          style: TextStyle(color: Colors.red),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
            ],
            SizedBox(
              width: double.infinity,
              height: 48,
              child: FilledButton.icon(
                onPressed: _isProcessing ? null : _processPayment,
                icon: const Icon(Icons.contactless),
                label: const Text(
                  'Start Payment Transaction',
                  style: TextStyle(fontSize: 16),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'Terminal Administrative Utilities',
              style: theme.textTheme.labelLarge,
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: _isProcessing ? null : _requestDuplicate,
                  icon: const Icon(Icons.copy),
                  label: const Text('Get Duplicate'),
                ),
                OutlinedButton.icon(
                  onPressed: _isProcessing ? null : _requestTotals,
                  icon: const Icon(Icons.receipt_long),
                  label: const Text('Get Totals'),
                ),
                OutlinedButton.icon(
                  onPressed: _isProcessing ? null : _resetTerminal,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Reset EPT'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildReceiptCard(ThemeData theme) {
    final receipt = _displayedReceipt;
    if (receipt == null) return const SizedBox.shrink();

    final fields = receipt.extractFields();

    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: theme.colorScheme.outlineVariant),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(16),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    const Icon(Icons.receipt, size: 18),
                    const SizedBox(width: 8),
                    Text(
                      _receiptTitle,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
                if (_lastPayment != null &&
                    _lastPayment!.merchantReceipt != null &&
                    _lastPayment!.customerReceipt != null)
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'cust', label: Text('Customer')),
                      ButtonSegment(value: 'merch', label: Text('Merchant')),
                    ],
                    selected: {
                      _displayedReceipt == _lastPayment!.customerReceipt
                          ? 'cust'
                          : 'merch',
                    },
                    onSelectionChanged: (val) {
                      setState(() {
                        if (val.first == 'cust') {
                          _displayedReceipt = _lastPayment!.customerReceipt;
                          _receiptTitle = 'Customer Receipt';
                        } else {
                          _displayedReceipt = _lastPayment!.merchantReceipt;
                          _receiptTitle = 'Merchant Receipt';
                        }
                      });
                    },
                  ),
              ],
            ),
          ),
          if (fields.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: fields.entries.take(4).map((e) {
                  return Chip(
                    label: Text(
                      '${e.key}: ${e.value}',
                      style: const TextStyle(fontSize: 11),
                    ),
                    padding: EdgeInsets.zero,
                    visualDensity: VisualDensity.compact,
                  );
                }).toList(),
              ),
            ),
          const Divider(height: 1),
          Expanded(
            child: Container(
              color: theme.brightness == Brightness.dark
                  ? const Color(0xFF1E1E1E)
                  : const Color(0xFFF9F9F9),
              padding: const EdgeInsets.all(12),
              child: ListView.builder(
                itemCount: receipt.lines.length,
                itemBuilder: (context, index) {
                  final line = receipt.lines[index];
                  TextAlign align = TextAlign.left;
                  if (line.alignment == NapsAlignment.center) {
                    align = TextAlign.center;
                  } else if (line.alignment == NapsAlignment.right) {
                    align = TextAlign.right;
                  }

                  final isBold = line.format == NapsPrintFormat.bold;

                  return Text(
                    line.text.isEmpty ? ' ' : line.text,
                    textAlign: align,
                    style: TextStyle(
                      fontFamily: 'monospace',
                      fontSize: 12,
                      fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
                      letterSpacing: 0.5,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLogTerminal(bool isDark) {
    return Container(
      decoration: BoxDecoration(
        color: isDark ? const Color(0xFF121212) : const Color(0xFF1E293B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white12),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(Icons.terminal, color: Colors.greenAccent, size: 18),
                  SizedBox(width: 8),
                  Text(
                    'Wire & Protocol Console',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
              Text(
                '${_logs.length} entries',
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],
          ),
          const SizedBox(height: 8),
          const Divider(color: Colors.white12, height: 1),
          const SizedBox(height: 8),
          Expanded(
            child: _logs.isEmpty
                ? const Center(
                    child: Text(
                      'Ready. Initiate an operation above to inspect traffic.',
                      style: TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    itemCount: _logs.length,
                    itemBuilder: (context, index) {
                      final item = _logs[index];
                      final timeStr =
                          '${item.timestamp.hour.toString().padLeft(2, '0')}:${item.timestamp.minute.toString().padLeft(2, '0')}:${item.timestamp.second.toString().padLeft(2, '0')}';

                      Color textColor = Colors.white70;
                      Widget? prefix;

                      if (item.isError) {
                        textColor = Colors.redAccent;
                      } else if (item.isSuccess) {
                        textColor = Colors.greenAccent;
                      } else if (item.direction ==
                          NapsFrameDirection.outbound) {
                        textColor = Colors.cyanAccent;
                        prefix = const Text(
                          '>> ',
                          style: TextStyle(
                            color: Colors.cyanAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      } else if (item.direction == NapsFrameDirection.inbound) {
                        textColor = Colors.amberAccent;
                        prefix = const Text(
                          '<< ',
                          style: TextStyle(
                            color: Colors.amberAccent,
                            fontWeight: FontWeight.bold,
                          ),
                        );
                      }

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 4),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '$timeStr ',
                              style: const TextStyle(
                                color: Colors.white38,
                                fontFamily: 'monospace',
                                fontSize: 11,
                              ),
                            ),
                            ?prefix,
                            Expanded(
                              child: Text(
                                item.text,
                                style: TextStyle(
                                  color: textColor,
                                  fontFamily: 'monospace',
                                  fontSize: 12,
                                ),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
