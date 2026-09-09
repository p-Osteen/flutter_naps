import 'package:flutter/material.dart';

class DashboardNavBar extends StatelessWidget {
  final int currentIndex;
  final ValueChanged<int> onTabSelected;
  final bool hasReceipt;
  final int errorCount;

  const DashboardNavBar({
    super.key,
    required this.currentIndex,
    required this.onTabSelected,
    this.hasReceipt = false,
    this.errorCount = 0,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF0A0E17),
        border: Border(top: BorderSide(color: Color(0xFF1E2C48), width: 1)),
      ),
      child: NavigationBarTheme(
        data: NavigationBarThemeData(
          backgroundColor: const Color(0xFF0A0E17),
          indicatorColor: const Color(0xFF10B981).withAlpha(35),
          labelTextStyle: WidgetStateProperty.resolveWith<TextStyle>((states) {
            final isSelected = states.contains(WidgetState.selected);
            return TextStyle(
              fontSize: 11,
              fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
              color: isSelected
                  ? const Color(0xFF10B981)
                  : const Color(0xFF64748B),
            );
          }),
          iconTheme: WidgetStateProperty.resolveWith<IconThemeData>((states) {
            final isSelected = states.contains(WidgetState.selected);
            return IconThemeData(
              size: 20,
              color: isSelected
                  ? const Color(0xFF10B981)
                  : const Color(0xFF64748B),
            );
          }),
        ),
        child: NavigationBar(
          selectedIndex: currentIndex,
          onDestinationSelected: onTabSelected,
          height: 64,
          destinations: [
            const NavigationDestination(
              icon: Icon(Icons.payments_outlined),
              selectedIcon: Icon(Icons.payments),
              label: 'Payment',
            ),
            NavigationDestination(
              icon: hasReceipt
                  ? const Badge(
                      smallSize: 8,
                      backgroundColor: Color(0xFF10B981),
                      child: Icon(Icons.receipt_long_outlined),
                    )
                  : const Icon(Icons.receipt_long_outlined),
              selectedIcon: const Icon(Icons.receipt_long),
              label: 'Receipt',
            ),
            const NavigationDestination(
              icon: Icon(Icons.admin_panel_settings_outlined),
              selectedIcon: Icon(Icons.admin_panel_settings),
              label: 'Services',
            ),
            NavigationDestination(
              icon: errorCount > 0
                  ? Badge(
                      label: Text(
                        '$errorCount',
                        style: const TextStyle(
                          fontSize: 10,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      backgroundColor: const Color(0xFFEF4444),
                      child: const Icon(Icons.cable_outlined),
                    )
                  : const Icon(Icons.cable_outlined),
              selectedIcon: const Icon(Icons.cable),
              label: 'Telemetry',
            ),
            const NavigationDestination(
              icon: Icon(Icons.settings_input_composite_outlined),
              selectedIcon: Icon(Icons.settings_input_composite),
              label: 'Link Config',
            ),
          ],
        ),
      ),
    );
  }
}
