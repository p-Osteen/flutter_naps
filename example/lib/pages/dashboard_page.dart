import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:naps_flutter/naps_flutter.dart';

import '../dialogs/cancellation_dialog.dart';
import '../dialogs/frame_inspector_sheet.dart';
import '../models/connection_type.dart';
import '../models/log_filter.dart';
import '../models/log_item.dart';
import '../models/pending_confirmation.dart';
import '../widgets/admin_services_card.dart';
import '../widgets/app_header.dart';
import '../widgets/connection_card.dart';
import '../widgets/dashboard_nav_bar.dart';
import '../widgets/operations_card.dart';
import '../widgets/receipt_preview_card.dart';
import '../widgets/telemetry_terminal.dart';

class NapsDashboardPage extends StatefulWidget {
  const NapsDashboardPage({super.key});

  @override
  State<NapsDashboardPage> createState() => _NapsDashboardPageState();
}

class _NapsDashboardPageState extends State<NapsDashboardPage> {
  int _selectedTabIndex = 0;
  ConnectionType _connectionType = ConnectionType.tcp;

  // TCP link settings
  final TextEditingController _ipController = TextEditingController(
    text: '192.168.1.26',
  );
  final TextEditingController _portController = TextEditingController(
    text: '4444',
  );

  // Serial link settings
  final TextEditingController _serialPortController = TextEditingController(
    text: 'COM1',
  );
  int _baudRate = 9600;

  // POS ID settings
  final TextEditingController _posIdController = TextEditingController(
    text: '0030007',
  );

  // Operations settings
  final TextEditingController _amountController = TextEditingController(
    text: '35.00',
  );
  bool _autoConfirm = true;

  // Administrative / Duplicate STAN
  final TextEditingController _duplicateStanController =
      TextEditingController();

  // Execution state
  bool _isProcessing = false;
  String _currentOperation = '';
  NapsCancelToken? _cancelToken;

  // Manual Confirmation state (when autoConfirm == false)
  PendingManualConfirmation? _pendingConfirmation;
  Timer? _countdownTimer;
  int _secondsRemaining = 40;

  // Transaction results and displayed receipt
  String? _lastStan;
  NapsTransactionResult? _lastPayment;
  NapsReceipt? _displayedReceipt;
  String _receiptTitle = 'Receipt Studio';

  // Frame and event logs
  final List<LogItem> _logs = [];
  LogFilter _logFilter = LogFilter.all;
  final TextEditingController _logSearchController = TextEditingController();

  // Ping RTT measurement
  int? _lastPingRttMs;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _ipController.dispose();
    _portController.dispose();
    _serialPortController.dispose();
    _posIdController.dispose();
    _amountController.dispose();
    _duplicateStanController.dispose();
    _logSearchController.dispose();
    super.dispose();
  }

  void _log(
    String message, {
    NapsFrameDirection? direction,
    bool isError = false,
    bool isSuccess = false,
    NapsMessage? rawMessage,
    NapsFrameLog? frameLog,
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
          rawMessage: rawMessage,
          frameLog: frameLog,
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
        onFrame: (frame) =>
            _log(frame.toString(), direction: frame.direction, frameLog: frame),
      );
    } else {
      final portName = _serialPortController.text.trim();
      return NapsSerialConnection(
        portName: portName,
        baudRate: _baudRate,
        onFrame: (frame) =>
            _log(frame.toString(), direction: frame.direction, frameLog: frame),
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
      _currentOperation = 'Probing link (TM 009)...';
      _lastPingRttMs = null;
    });

    final stopwatch = Stopwatch()..start();
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
      stopwatch.stop();

      if (result.isSuccess) {
        setState(() => _lastPingRttMs = stopwatch.elapsedMilliseconds);
        _log(
          'Link Online! RTT: ${stopwatch.elapsedMilliseconds}ms - ${result.description}',
          isSuccess: true,
        );
      } else {
        _log(
          'Network test failed: CR ${result.responseCode} (${result.failureReason.name}) - ${result.userMessage}',
          isError: true,
        );
      }
    } catch (e) {
      _log('Network test error: $e', isError: true);
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
      _currentOperation = 'Awaiting card presentation on SUNMI P2...';
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
        final stanVal = result.stan;
        if (stanVal != null && stanVal.isNotEmpty) {
          _lastStan = stanVal;
          _duplicateStanController.text = stanVal;
        }

        if (result.customerReceipt != null) {
          _displayedReceipt = result.customerReceipt;
          _receiptTitle = 'Customer Receipt';
        } else if (result.merchantReceipt != null) {
          _displayedReceipt = result.merchantReceipt;
          _receiptTitle = 'Merchant Receipt';
        }
      });

      if (result.isSuccess) {
        if (!_autoConfirm) {
          _log(
            'Payment Approved (TM 101)! Awaiting manual confirmation (TM 002). STAN=${result.stan}',
            isSuccess: true,
          );
          _startManualConfirmationTimer(
            PendingManualConfirmation(
              amountInCents: amountInCents,
              sequenceNumber: result.sequenceNumber ?? 0,
              stan: result.stan ?? '',
              cardMasked: result.cardNumber ?? '',
              expirationDate: result.cardExpirationDate ?? '',
              approvedAt: DateTime.now(),
            ),
          );
        } else {
          _log(
            'Payment Approved & Confirmed! STAN=${result.stan}, Auth=${result.authorizationNumber}, Card=${result.cardNumber}',
            isSuccess: true,
          );
        }
      } else if (result.requiresReconciliation) {
        _log(
          'CRITICAL: Approved but NOT confirmed! Reconcile STAN=${result.stan}, NS=${result.sequenceNumber}. Reason: ${result.failureReason.name}',
          isError: true,
        );
      } else if (result.source == NapsResultSource.cancelled) {
        _log('Payment aborted by user.', isError: false);
      } else {
        _log(
          'Payment declined: CR ${result.responseCode} (${result.failureReason.name}) - ${result.userMessage}',
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

  void _startManualConfirmationTimer(PendingManualConfirmation pending) {
    _countdownTimer?.cancel();
    setState(() {
      _pendingConfirmation = pending;
      _secondsRemaining = 40;
    });

    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      setState(() {
        if (_secondsRemaining > 0) {
          _secondsRemaining--;
        } else {
          timer.cancel();
          _pendingConfirmation = null;
          _log(
            'Manual confirmation window (40s) expired. Terminal reverses transaction automatically.',
            isError: true,
          );
        }
      });
    });
  }

  Future<void> _executeManualConfirm() async {
    final pending = _pendingConfirmation;
    if (pending == null) return;

    _countdownTimer?.cancel();
    setState(() {
      _isProcessing = true;
      _currentOperation = 'Sending manual confirmation (TM 002)...';
      _pendingConfirmation = null;
    });

    final connection = _createConnection();
    final sdk = _createSdk(connection);

    try {
      if (!await connection.connect()) {
        _log('Could not connect to terminal for confirmation', isError: true);
        return;
      }

      _log(
        'Confirming payment STAN=${pending.stan}, NS=${pending.sequenceNumber}...',
      );
      final result = await sdk.confirmPayment(
        amountInCents: pending.amountInCents,
        sequenceNumber: pending.sequenceNumber,
        stan: pending.stan,
        cardMasked: pending.cardMasked,
        expirationDate: pending.expirationDate,
        approvedAt: pending.approvedAt,
      );

      setState(() {
        _lastPayment = result;
        if (result.customerReceipt != null) {
          _displayedReceipt = result.customerReceipt;
          _receiptTitle = 'Customer Receipt';
        }
      });

      if (result.isSuccess) {
        _log(
          'Manual confirmation SUCCESS! STAN=${result.stan}, CR=${result.responseCode}',
          isSuccess: true,
        );
      } else {
        _log(
          'Manual confirmation FAILED: CR ${result.responseCode} - ${result.userMessage}',
          isError: true,
        );
      }
    } catch (e) {
      _log('Manual confirmation error: $e', isError: true);
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

  Future<void> _showCancellationFlow() async {
    await showCancellationDialog(
      context: context,
      initialStan: _lastStan,
      onLookup: (stan) async {
        final connection = _createConnection();
        final sdk = _createSdk(connection);
        try {
          _log('Querying cancellation TM 003 for STAN $stan...');
          if (!await connection.connect()) {
            throw Exception('Could not connect to terminal');
          }
          final info = await sdk.initiateCancellation(stan: stan);
          if (!info.isFound) {
            _log(
              'Cancellation lookup failed: CR ${info.responseCode} - ${info.userMessage}',
              isError: true,
            );
          } else {
            _log(
              'Transaction found for cancellation: ${(info.amountInCents / 100).toStringAsFixed(2)} MAD',
              isSuccess: true,
            );
          }
          return info;
        } finally {
          await connection.disconnect();
        }
      },
      onConfirmReversal: (info) async {
        await _confirmCancellationExecution(info);
      },
    );
  }

  Future<void> _confirmCancellationExecution(NapsCancellationInfo info) async {
    setState(() {
      _isProcessing = true;
      _currentOperation = 'Executing cancellation (TM 004)...';
    });

    final connection = _createConnection();
    final sdk = _createSdk(connection);

    try {
      if (!await connection.connect()) {
        _log('Could not connect to terminal', isError: true);
        return;
      }

      _log('Sending Cancellation Confirmation TM 004 for STAN ${info.stan}...');
      final result = await sdk.confirmCancellation(info: info);

      if (result.isSuccess) {
        setState(() {
          if (result.cancellationReceipt != null) {
            _displayedReceipt = result.cancellationReceipt;
            _receiptTitle = 'Cancellation Receipt';
          }
        });
        _log(
          'Cancellation SUCCESS! STAN=${info.stan}, CR=${result.responseCode} - ${result.userMessage}',
          isSuccess: true,
        );
      } else {
        _log(
          'Cancellation FAILED: CR ${result.responseCode} (${result.failureReason.name}) - ${result.userMessage}',
          isError: true,
        );
      }
    } catch (e) {
      _log('Cancellation execution error: $e', isError: true);
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

  Future<void> _requestDuplicate({String? specificStan}) async {
    setState(() {
      _isProcessing = true;
      _currentOperation = specificStan == null
          ? 'Requesting duplicate receipt (TM 008)...'
          : 'Requesting duplicate receipt for STAN $specificStan (TM 008)...';
    });

    final connection = _createConnection();
    final sdk = _createSdk(connection);

    try {
      if (!await connection.connect()) {
        _log('Could not connect to terminal', isError: true);
        return;
      }

      _log('Requesting Duplicate Receipt (TM 008)...');
      final result = await sdk.getDuplicate(stan: specificStan);
      if (result.isSuccess && result.receipt != null) {
        setState(() {
          _displayedReceipt = result.receipt;
          _receiptTitle = specificStan != null
              ? 'Duplicate Receipt (STAN: $specificStan)'
              : 'Duplicate Receipt (Latest)';
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
      _currentOperation = 'Requesting batch totals (TM 010)...';
    });

    final connection = _createConnection();
    final sdk = _createSdk(connection);

    try {
      if (!await connection.connect()) {
        _log('Could not connect to terminal', isError: true);
        return;
      }

      _log('Requesting Batch Totals (TM 010)...');
      final result = await sdk.getTotals();
      if (result.isSuccess && result.receipt != null) {
        setState(() {
          _displayedReceipt = result.receipt;
          _receiptTitle = 'Batch Totals Report (TM 010)';
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
      _currentOperation = 'Resetting EPT (TM 012)...';
    });

    final connection = _createConnection();
    final sdk = _createSdk(connection);

    try {
      if (!await connection.connect()) {
        _log('Could not connect to terminal', isError: true);
        return;
      }

      _log('Resetting Terminal EPT (TM 012)...');
      final result = await sdk.resetEpt();
      if (result.isSuccess) {
        _log(
          'Terminal reset acknowledged: ${result.description}',
          isSuccess: true,
        );
      } else {
        _log(
          'Reset failed: CR ${result.responseCode} - ${result.userMessage}',
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

  Future<void> _getPrintInfo() async {
    setState(() {
      _isProcessing = true;
      _currentOperation = 'Requesting config print (TM 011)...';
    });

    final connection = _createConnection();
    final sdk = _createSdk(connection);

    try {
      if (!await connection.connect()) {
        _log('Could not connect to terminal', isError: true);
        return;
      }

      _log('Requesting Print Info (TM 011)...');
      final result = await sdk.getPrintInfo(ticketType: '01');
      if (result.isSuccess && result.receipt != null) {
        setState(() {
          _displayedReceipt = result.receipt;
          _receiptTitle = 'Configuration Ticket (TM 011)';
        });
        _log('Config ticket received', isSuccess: true);
      } else {
        _log(
          'Print info failed: CR ${result.responseCode} - ${result.userMessage}',
          isError: true,
        );
      }
    } catch (e) {
      _log('Print info error: $e', isError: true);
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

  void _copyLogs() {
    final text = _logs
        .map((e) => '${e.timestamp.toIso8601String()} ${e.text}')
        .join('\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Console logs copied to clipboard')),
    );
  }

  void _selectReceipt(NapsReceipt receipt, String title) {
    setState(() {
      _displayedReceipt = receipt;
      _receiptTitle = title;
    });
  }

  @override
  Widget build(BuildContext context) {
    final errorCount = _logs.where((l) => l.isError).length;

    return Scaffold(
      appBar: AppHeader(
        isProcessing: _isProcessing,
        lastPingRttMs: _lastPingRttMs,
        onProbeLink: _pingTerminal,
        onClearConsole: () => setState(() => _logs.clear()),
        onCopyLogs: _copyLogs,
      ),
      body: SafeArea(
        child: IndexedStack(
          index: _selectedTabIndex,
          children: [
            // Tab 0: Payment Desk
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: OperationsCard(
                    amountController: _amountController,
                    autoConfirm: _autoConfirm,
                    onAutoConfirmChanged: (val) =>
                        setState(() => _autoConfirm = val),
                    pendingConfirmation: _pendingConfirmation,
                    secondsRemaining: _secondsRemaining,
                    onManualConfirm: _executeManualConfirm,
                    onAbortManualConfirm: () {
                      _countdownTimer?.cancel();
                      setState(() => _pendingConfirmation = null);
                      _log(
                        'Manual confirmation cancelled by user. Terminal will auto-reverse.',
                        isError: true,
                      );
                    },
                    isProcessing: _isProcessing,
                    currentOperation: _currentOperation,
                    onCancelPayment: _cancelToken != null
                        ? () {
                            _cancelToken?.cancel();
                            _log('Cancelling payment via cancel token...');
                          }
                        : null,
                    onInitiatePayment: _processPayment,
                  ),
                ),
              ),
            ),

            // Tab 1: Receipt Slip
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: ReceiptPreviewCard(
                    displayedReceipt: _displayedReceipt,
                    receiptTitle: _receiptTitle,
                    lastPayment: _lastPayment,
                    onSelectReceipt: _selectReceipt,
                  ),
                ),
              ),
            ),

            // Tab 2: Admin Services
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: AdminServicesCard(
                    duplicateStanController: _duplicateStanController,
                    lastStan: _lastStan,
                    isProcessing: _isProcessing,
                    onRequestDuplicate: () {
                      final stan = _duplicateStanController.text.trim();
                      _requestDuplicate(
                        specificStan: stan.isEmpty ? null : stan,
                      );
                    },
                    onShowCancellationFlow: _showCancellationFlow,
                    onRequestTotals: _requestTotals,
                    onGetPrintInfo: _getPrintInfo,
                    onResetTerminal: _resetTerminal,
                  ),
                ),
              ),
            ),

            // Tab 3: Wire Telemetry
            Padding(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1000),
                  child: TelemetryTerminal(
                    logs: _logs,
                    searchController: _logSearchController,
                    onSearchChanged: (_) => setState(() {}),
                    activeFilter: _logFilter,
                    onFilterChanged: (filter) =>
                        setState(() => _logFilter = filter),
                    onInspectItem: (item) =>
                        showFrameInspectorSheet(context, item),
                  ),
                ),
              ),
            ),

            // Tab 4: Link Config
            SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 680),
                  child: ConnectionCard(
                    connectionType: _connectionType,
                    onConnectionTypeChanged: (type) =>
                        setState(() => _connectionType = type),
                    ipController: _ipController,
                    portController: _portController,
                    serialPortController: _serialPortController,
                    baudRate: _baudRate,
                    onBaudRateChanged: (baud) =>
                        setState(() => _baudRate = baud),
                    posIdController: _posIdController,
                    onPosIdChanged: () => setState(() {}),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: DashboardNavBar(
        currentIndex: _selectedTabIndex,
        onTabSelected: (index) => setState(() => _selectedTabIndex = index),
        hasReceipt: _displayedReceipt != null,
        errorCount: errorCount,
      ),
    );
  }
}
