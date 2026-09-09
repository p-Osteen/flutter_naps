import 'package:flutter/material.dart';

import 'pages/dashboard_page.dart';

void main() {
  runApp(const NapsExampleApp());
}

class NapsExampleApp extends StatelessWidget {
  const NapsExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'NAPS SUNMI P2 Studio',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF070B12),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF10B981), // Emerald Neon
          onPrimary: Colors.black,
          secondary: Color(0xFF06B6D4), // Cyber Cyan
          onSecondary: Colors.black,
          surface: Color(0xFF0F172A), // Deep Slate
          onSurface: Color(0xFFF8FAFC),
          surfaceContainer: Color(0xFF131D33),
          surfaceContainerHigh: Color(0xFF1E293B),
          outline: Color(0xFF2A3A54),
          error: Color(0xFFEF4444),
          onError: Colors.white,
        ),
        cardTheme: CardThemeData(
          elevation: 0,
          color: const Color(0xFF0E1626),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: const BorderSide(color: Color(0xFF1E2C48), width: 1),
          ),
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: const Color(0xFF0A101D),
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 12,
          ),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF1E2C48)),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF1E2C48)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: Color(0xFF10B981), width: 1.5),
          ),
          hintStyle: const TextStyle(color: Color(0xFF475569), fontSize: 13),
          labelStyle: const TextStyle(color: Color(0xFF94A3B8), fontSize: 13),
        ),
      ),
      home: const NapsDashboardPage(),
    );
  }
}
