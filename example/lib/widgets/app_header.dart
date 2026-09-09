import 'package:flutter/material.dart';

class AppHeader extends StatelessWidget implements PreferredSizeWidget {
  final bool isProcessing;
  final int? lastPingRttMs;
  final VoidCallback onProbeLink;
  final VoidCallback onClearConsole;
  final VoidCallback onCopyLogs;

  const AppHeader({
    super.key,
    required this.isProcessing,
    this.lastPingRttMs,
    required this.onProbeLink,
    required this.onClearConsole,
    required this.onCopyLogs,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 1);

  @override
  Widget build(BuildContext context) {
    return AppBar(
      backgroundColor: const Color(0xFF0A0E17),
      elevation: 0,
      titleSpacing: 12,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(color: const Color(0xFF1E2C48), height: 1),
      ),
      title: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [Color(0xFF059669), Color(0xFF10B981)],
              ),
              borderRadius: BorderRadius.circular(8),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFF10B981).withAlpha(60),
                  blurRadius: 8,
                ),
              ],
            ),
            child: const Icon(
              Icons.terminal_rounded,
              color: Colors.black,
              size: 16,
            ),
          ),
          const SizedBox(width: 8),
          const Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'NAPS // SUNMI P2',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontWeight: FontWeight.w900,
                    fontSize: 13,
                    letterSpacing: 0.8,
                    color: Colors.white,
                  ),
                ),
                Text(
                  'M2M TLV WORKBENCH',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 8.5,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1.0,
                    color: Color(0xFF10B981),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          // Live status pill
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
            decoration: BoxDecoration(
              color: isProcessing
                  ? const Color(0xFFF59E0B).withAlpha(25)
                  : const Color(0xFF10B981).withAlpha(25),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isProcessing
                    ? const Color(0xFFF59E0B).withAlpha(80)
                    : const Color(0xFF10B981).withAlpha(80),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: isProcessing
                        ? const Color(0xFFF59E0B)
                        : const Color(0xFF10B981),
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  isProcessing ? 'BUSY' : 'STANDBY',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5,
                    color: isProcessing
                        ? const Color(0xFFFBBF24)
                        : const Color(0xFF34D399),
                  ),
                ),
              ],
            ),
          ),
          if (lastPingRttMs != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: const Color(0xFF06B6D4).withAlpha(20),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF06B6D4).withAlpha(60),
                ),
              ),
              child: Text(
                '${lastPingRttMs}ms',
                style: const TextStyle(
                  fontSize: 9,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF38BDF8),
                  fontFamily: 'monospace',
                ),
              ),
            ),
          ],
        ],
      ),
      actions: [
        IconButton(
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          padding: EdgeInsets.zero,
          tooltip: 'Probe Link (TM 009)',
          icon: const Icon(
            Icons.network_ping,
            size: 19,
            color: Color(0xFF38BDF8),
          ),
          onPressed: isProcessing ? null : onProbeLink,
        ),
        IconButton(
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          padding: EdgeInsets.zero,
          tooltip: 'Clear Console',
          icon: const Icon(
            Icons.delete_sweep_outlined,
            size: 19,
            color: Color(0xFF94A3B8),
          ),
          onPressed: onClearConsole,
        ),
        IconButton(
          constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
          padding: EdgeInsets.zero,
          tooltip: 'Copy Console Logs',
          icon: const Icon(Icons.copy_all, size: 19, color: Color(0xFF94A3B8)),
          onPressed: onCopyLogs,
        ),
        const SizedBox(width: 6),
      ],
    );
  }
}
