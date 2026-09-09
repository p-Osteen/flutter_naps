import 'package:flutter/material.dart';
import 'package:naps_flutter/naps_flutter.dart';

import '../models/connection_type.dart';

class ConnectionCard extends StatefulWidget {
  final ConnectionType connectionType;
  final ValueChanged<ConnectionType> onConnectionTypeChanged;
  final TextEditingController ipController;
  final TextEditingController portController;
  final TextEditingController serialPortController;
  final int baudRate;
  final ValueChanged<int> onBaudRateChanged;
  final TextEditingController posIdController;
  final VoidCallback onPosIdChanged;

  const ConnectionCard({
    super.key,
    required this.connectionType,
    required this.onConnectionTypeChanged,
    required this.ipController,
    required this.portController,
    required this.serialPortController,
    required this.baudRate,
    required this.onBaudRateChanged,
    required this.posIdController,
    required this.onPosIdChanged,
  });

  @override
  State<ConnectionCard> createState() => _ConnectionCardState();
}

class _ConnectionCardState extends State<ConnectionCard> {
  List<NapsSerialPortInfo> _detectedPorts = [];
  bool _manualPortEntry = false;

  @override
  void initState() {
    super.initState();
    _scanUsbPorts();
  }

  void _scanUsbPorts() {
    final devices = NapsSerialConnection.availableDevices;
    setState(() {
      _detectedPorts = devices;
      if (devices.isNotEmpty) {
        final current = widget.serialPortController.text.trim();
        final matches = devices.any((d) => d.name == current);
        if (!matches && current.isEmpty) {
          widget.serialPortController.text = devices.first.name;
        }
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final posIssue = NapsSdk.posIdIssue(widget.posIdController.text.trim());

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
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.settings_input_composite,
                    color: Color(0xFF10B981),
                    size: 18,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'HARDWARE LINK CONFIG',
                    style: TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      letterSpacing: 1.1,
                      color: Colors.white,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E293B),
                  borderRadius: BorderRadius.circular(4),
                ),
                child: Text(
                  widget.connectionType == ConnectionType.tcp
                      ? 'TCP / PORT 4444'
                      : 'SERIAL / RS-232',
                  style: const TextStyle(
                    fontSize: 10,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF94A3B8),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),

          // Sliding Transport Selector
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: const Color(0xFF090E18),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: const Color(0xFF1E2C48)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () =>
                        widget.onConnectionTypeChanged(ConnectionType.tcp),
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: widget.connectionType == ConnectionType.tcp
                            ? const Color(0xFF1E293B)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.wifi_tethering,
                            size: 16,
                            color: widget.connectionType == ConnectionType.tcp
                                ? const Color(0xFF10B981)
                                : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'TCP / IP (Wi-Fi / LAN)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: widget.connectionType == ConnectionType.tcp
                                  ? Colors.white
                                  : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                Expanded(
                  child: InkWell(
                    onTap: () {
                      widget.onConnectionTypeChanged(ConnectionType.serial);
                      _scanUsbPorts();
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Container(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      decoration: BoxDecoration(
                        color: widget.connectionType == ConnectionType.serial
                            ? const Color(0xFF1E293B)
                            : Colors.transparent,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.usb,
                            size: 16,
                            color:
                                widget.connectionType == ConnectionType.serial
                                ? const Color(0xFF06B6D4)
                                : const Color(0xFF64748B),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            'Serial (USB-C / COM)',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color:
                                  widget.connectionType == ConnectionType.serial
                                  ? Colors.white
                                  : const Color(0xFF64748B),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Parameters
          if (widget.connectionType == ConnectionType.tcp) ...[
            Row(
              children: [
                Expanded(
                  flex: 3,
                  child: TextField(
                    controller: widget.ipController,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                    ),
                    decoration: const InputDecoration(
                      labelText: 'Terminal IPv4 Host Address',
                      hintText: '192.168.1.26',
                      prefixIcon: Icon(
                        Icons.router_outlined,
                        size: 18,
                        color: Color(0xFF06B6D4),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: widget.portController,
                    readOnly: true,
                    style: const TextStyle(
                      fontFamily: 'monospace',
                      fontWeight: FontWeight.w600,
                      fontSize: 13,
                      color: Color(0xFF94A3B8),
                    ),
                    decoration: const InputDecoration(
                      labelText: 'TCP Port (Fixed)',
                      hintText: '4444',
                      prefixIcon: Icon(
                        Icons.tag,
                        size: 18,
                        color: Color(0xFF94A3B8),
                      ),
                      suffixIcon: Icon(
                        Icons.lock_outline,
                        size: 16,
                        color: Color(0xFF64748B),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ] else ...[
            // Serial / USB connection with auto-discovered devices
            if (_detectedPorts.isNotEmpty && !_manualPortEntry) ...[
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: DropdownButtonFormField<String>(
                      initialValue:
                          _detectedPorts.any(
                            (d) =>
                                d.name ==
                                widget.serialPortController.text.trim(),
                          )
                          ? widget.serialPortController.text.trim()
                          : _detectedPorts.first.name,
                      decoration: InputDecoration(
                        labelText: 'Detected USB Device',
                        prefixIcon: const Icon(
                          Icons.usb,
                          size: 18,
                          color: Color(0xFF06B6D4),
                        ),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Rescan USB ports',
                              icon: const Icon(
                                Icons.refresh,
                                size: 18,
                                color: Color(0xFF10B981),
                              ),
                              onPressed: _scanUsbPorts,
                            ),
                            IconButton(
                              tooltip: 'Type COM port manually',
                              icon: const Icon(
                                Icons.edit_note,
                                size: 18,
                                color: Color(0xFF94A3B8),
                              ),
                              onPressed: () =>
                                  setState(() => _manualPortEntry = true),
                            ),
                          ],
                        ),
                      ),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: Colors.white,
                        fontSize: 13,
                      ),
                      dropdownColor: const Color(0xFF0E1626),
                      items: _detectedPorts.map((device) {
                        final desc = device.description;
                        final label = (desc != null && desc.isNotEmpty)
                            ? '${device.name} ($desc)'
                            : device.name;
                        return DropdownMenuItem<String>(
                          value: device.name,
                          child: Text(
                            label,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(fontSize: 12),
                          ),
                        );
                      }).toList(),
                      onChanged: (val) {
                        if (val != null) {
                          setState(() {
                            widget.serialPortController.text = val;
                          });
                        }
                      },
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<int>(
                      initialValue: widget.baudRate,
                      decoration: const InputDecoration(labelText: 'Baud Rate'),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: Colors.white,
                        fontSize: 13,
                      ),
                      dropdownColor: const Color(0xFF0E1626),
                      items: const [9600, 19200, 38400, 57600, 115200]
                          .map(
                            (b) => DropdownMenuItem(
                              value: b,
                              child: Text('$b baud'),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        if (val != null) widget.onBaudRateChanged(val);
                      },
                    ),
                  ),
                ],
              ),
            ] else ...[
              // Manual entry or fallback when no ports detected
              Row(
                children: [
                  Expanded(
                    flex: 3,
                    child: TextField(
                      controller: widget.serialPortController,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontWeight: FontWeight.w600,
                        fontSize: 13,
                      ),
                      decoration: InputDecoration(
                        labelText: 'Serial COM Port',
                        hintText: 'COM1',
                        prefixIcon: const Icon(
                          Icons.cable,
                          size: 18,
                          color: Color(0xFF06B6D4),
                        ),
                        suffixIcon: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: 'Scan for USB devices',
                              icon: const Icon(
                                Icons.refresh,
                                size: 18,
                                color: Color(0xFF10B981),
                              ),
                              onPressed: _scanUsbPorts,
                            ),
                            if (_detectedPorts.isNotEmpty)
                              IconButton(
                                tooltip: 'Select from detected devices',
                                icon: const Icon(
                                  Icons.list,
                                  size: 18,
                                  color: Color(0xFF38BDF8),
                                ),
                                onPressed: () =>
                                    setState(() => _manualPortEntry = false),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    flex: 2,
                    child: DropdownButtonFormField<int>(
                      initialValue: widget.baudRate,
                      decoration: const InputDecoration(labelText: 'Baud Rate'),
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        color: Colors.white,
                        fontSize: 13,
                      ),
                      dropdownColor: const Color(0xFF0E1626),
                      items: const [9600, 19200, 38400, 57600, 115200]
                          .map(
                            (b) => DropdownMenuItem(
                              value: b,
                              child: Text('$b baud'),
                            ),
                          )
                          .toList(),
                      onChanged: (val) {
                        if (val != null) widget.onBaudRateChanged(val);
                      },
                    ),
                  ),
                ],
              ),
              if (_detectedPorts.isEmpty) ...[
                const SizedBox(height: 6),
                const Row(
                  children: [
                    Icon(
                      Icons.info_outline,
                      size: 13,
                      color: Color(0xFF64748B),
                    ),
                    SizedBox(width: 5),
                    Text(
                      'No USB devices detected. Connect terminal via USB-C or enter port name.',
                      style: TextStyle(fontSize: 11, color: Color(0xFF64748B)),
                    ),
                  ],
                ),
              ],
            ],
          ],
          const SizedBox(height: 14),

          // POS Station ID (NCAI)
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Expanded(
                child: TextField(
                  controller: widget.posIdController,
                  readOnly: true,
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                    letterSpacing: 1.5,
                    color: Color(0xFFE2E8F0),
                  ),
                  decoration: InputDecoration(
                    labelText: 'POS Identifier (Tag 003 NCAI - Fixed)',
                    hintText: '0030007',
                    prefixIcon: const Icon(
                      Icons.badge_outlined,
                      size: 18,
                      color: Color(0xFF10B981),
                    ),
                    suffixIcon: const Icon(
                      Icons.lock_outline,
                      size: 16,
                      color: Color(0xFF64748B),
                    ),
                    errorText: posIssue,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: posIssue == null
                      ? const Color(0xFF10B981).withAlpha(20)
                      : const Color(0xFFEF4444).withAlpha(20),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                    color: posIssue == null
                        ? const Color(0xFF10B981).withAlpha(60)
                        : const Color(0xFFEF4444).withAlpha(60),
                  ),
                ),
                child: Text(
                  posIssue == null ? '✓ VALID NCAI' : '✗ INVALID',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                    color: posIssue == null
                        ? const Color(0xFF34D399)
                        : const Color(0xFFF87171),
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
