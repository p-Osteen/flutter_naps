import 'package:flutter/material.dart';
import 'package:naps_flutter/naps_flutter.dart';

import '../models/log_filter.dart';
import '../models/log_item.dart';

class TelemetryTerminal extends StatelessWidget {
  final List<LogItem> logs;
  final TextEditingController searchController;
  final ValueChanged<String> onSearchChanged;
  final LogFilter activeFilter;
  final ValueChanged<LogFilter> onFilterChanged;
  final void Function(LogItem item) onInspectItem;

  const TelemetryTerminal({
    super.key,
    required this.logs,
    required this.searchController,
    required this.onSearchChanged,
    required this.activeFilter,
    required this.onFilterChanged,
    required this.onInspectItem,
  });

  List<LogItem> get _filteredLogs {
    return logs.where((item) {
      switch (activeFilter) {
        case LogFilter.all:
          break;
        case LogFilter.inbound:
          if (item.direction != NapsFrameDirection.inbound) return false;
          break;
        case LogFilter.outbound:
          if (item.direction != NapsFrameDirection.outbound) return false;
          break;
        case LogFilter.errors:
          if (!item.isError) return false;
          break;
        case LogFilter.success:
          if (!item.isSuccess) return false;
          break;
      }

      final q = searchController.text.trim().toLowerCase();
      if (q.isNotEmpty && !item.text.toLowerCase().contains(q)) {
        return false;
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredLogs;

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF080C14),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFF1E2C48)),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Terminal Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.cable_outlined,
                    color: Color(0xFF06B6D4),
                    size: 16,
                  ),
                  SizedBox(width: 8),
                  Text(
                    'WIRE PROTOCOL TELEMETRY',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 12,
                      letterSpacing: 1.1,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                decoration: BoxDecoration(
                  color: const Color(0xFF131D33),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: const Color(0xFF1E2C48)),
                ),
                child: Text(
                  '${filtered.length} / ${logs.length} FRAMES',
                  style: const TextStyle(
                    color: Color(0xFF94A3B8),
                    fontSize: 10,
                    fontFamily: 'monospace',
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // Search Box
          SizedBox(
            height: 36,
            child: TextField(
              controller: searchController,
              onChanged: onSearchChanged,
              style: const TextStyle(color: Colors.white, fontSize: 12),
              decoration: InputDecoration(
                hintText: 'Filter frames by STAN, TM code, hex, text...',
                prefixIcon: const Icon(
                  Icons.search,
                  size: 16,
                  color: Color(0xFF64748B),
                ),
                contentPadding: EdgeInsets.zero,
                fillColor: const Color(0xFF0E1626),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF1E2C48)),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(8),
                  borderSide: const BorderSide(color: Color(0xFF1E2C48)),
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // Filter Buttons with Live Counters
          Wrap(
            spacing: 6,
            runSpacing: 6,
            children: LogFilter.values.map((f) {
              final isSelected = activeFilter == f;

              final Color activeBg;
              final Color activeTextColor;
              switch (f) {
                case LogFilter.all:
                  activeBg = const Color(0xFF10B981);
                  activeTextColor = Colors.black;
                  break;
                case LogFilter.inbound:
                  activeBg = const Color(0xFFF59E0B);
                  activeTextColor = Colors.black;
                  break;
                case LogFilter.outbound:
                  activeBg = const Color(0xFF06B6D4);
                  activeTextColor = Colors.black;
                  break;
                case LogFilter.errors:
                  activeBg = const Color(0xFFEF4444);
                  activeTextColor = Colors.white;
                  break;
                case LogFilter.success:
                  activeBg = const Color(0xFF22C55E);
                  activeTextColor = Colors.black;
                  break;
              }

              int count;
              switch (f) {
                case LogFilter.all:
                  count = logs.length;
                  break;
                case LogFilter.inbound:
                  count = logs
                      .where((l) => l.direction == NapsFrameDirection.inbound)
                      .length;
                  break;
                case LogFilter.outbound:
                  count = logs
                      .where((l) => l.direction == NapsFrameDirection.outbound)
                      .length;
                  break;
                case LogFilter.errors:
                  count = logs.where((l) => l.isError).length;
                  break;
                case LogFilter.success:
                  count = logs.where((l) => l.isSuccess).length;
                  break;
              }

              return InkWell(
                onTap: () => onFilterChanged(f),
                borderRadius: BorderRadius.circular(6),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: isSelected ? activeBg : const Color(0xFF131D33),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(
                      color: isSelected ? activeBg : const Color(0xFF1E2C48),
                      width: 1,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        f.name.toUpperCase(),
                        style: TextStyle(
                          fontSize: 10,
                          fontWeight: isSelected
                              ? FontWeight.w900
                              : FontWeight.w600,
                          color: isSelected
                              ? activeTextColor
                              : const Color(0xFFCBD5E1),
                        ),
                      ),
                      if (count > 0) ...[
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: isSelected
                                ? (activeTextColor == Colors.black
                                      ? Colors.black.withAlpha(40)
                                      : Colors.white.withAlpha(50))
                                : const Color(0xFF090E18),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Text(
                            '$count',
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.bold,
                              fontFamily: 'monospace',
                              color: isSelected
                                  ? activeTextColor
                                  : const Color(0xFF94A3B8),
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          const Divider(color: Color(0xFF1E2C48), height: 1),
          const SizedBox(height: 8),

          // Log Stream
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                    child: Text(
                      'Ready. Initiate an operation above to stream wire traffic.',
                      style: TextStyle(color: Color(0xFF475569), fontSize: 12),
                    ),
                  )
                : ListView.builder(
                    itemCount: filtered.length,
                    itemBuilder: (context, index) {
                      final item = filtered[index];
                      final timeStr =
                          '${item.timestamp.hour.toString().padLeft(2, '0')}:${item.timestamp.minute.toString().padLeft(2, '0')}:${item.timestamp.second.toString().padLeft(2, '0')}.${item.timestamp.millisecond.toString().padLeft(3, '0')}';

                      Color textColor = const Color(0xFFCBD5E1);
                      Widget? prefix;

                      if (item.isError) {
                        textColor = const Color(0xFFF87171);
                      } else if (item.isSuccess) {
                        textColor = const Color(0xFF34D399);
                      } else if (item.direction ==
                          NapsFrameDirection.outbound) {
                        textColor = const Color(0xFF38BDF8);
                        prefix = const Text(
                          '>> ',
                          style: TextStyle(
                            color: Color(0xFF06B6D4),
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        );
                      } else if (item.direction == NapsFrameDirection.inbound) {
                        textColor = const Color(0xFFFBBF24);
                        prefix = const Text(
                          '<< ',
                          style: TextStyle(
                            color: Color(0xFFF59E0B),
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace',
                          ),
                        );
                      }

                      final canInspect =
                          item.rawMessage != null || item.frameLog != null;

                      return InkWell(
                        onTap: canInspect ? () => onInspectItem(item) : null,
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 3),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                '$timeStr ',
                                style: const TextStyle(
                                  color: Color(0xFF475569),
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
                                    fontSize: 11.5,
                                  ),
                                ),
                              ),
                              if (canInspect)
                                const Icon(
                                  Icons.info_outline,
                                  size: 14,
                                  color: Color(0xFF64748B),
                                ),
                            ],
                          ),
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
