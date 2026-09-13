import 'package:flutter/material.dart';

/// 🎨 Tema DZR Builder — dark premium, ungu + cyan (nyambung sama brand bot).
/// SEMUA UI = widget Flutter native (Material 3). NOL WebView.
class DzrTheme {
  static const seed = Color(0xFF7C4DFF);      // deep purple
  static const accent = Color(0xFF22D3EE);    // cyan
  static const bg = Color(0xFF0B0B10);
  static const card = Color(0xFF15151F);
  static const cardAlt = Color(0xFF1C1C29);
  static const good = Color(0xFF34D399);
  static const warn = Color(0xFFFBBF24);
  static const bad = Color(0xFFF87171);

  static ThemeData dark() {
    final base = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorScheme: ColorScheme.fromSeed(
        seedColor: seed,
        brightness: Brightness.dark,
        primary: seed,
        secondary: accent,
        surface: card,
      ),
      scaffoldBackgroundColor: bg,
      appBarTheme: const AppBarTheme(
        backgroundColor: Colors.transparent,
        elevation: 0,
        centerTitle: false,
        titleTextStyle: TextStyle(
          fontSize: 20, fontWeight: FontWeight.w800, color: Colors.white,
        ),
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: card,
        indicatorColor: seed.withOpacity(0.35),
        labelTextStyle: WidgetStatePropertyAll(const TextStyle(
          fontSize: 12, fontWeight: FontWeight.w600, color: Colors.white70,
        )),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: seed,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          textStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: Colors.white,
          side: const BorderSide(color: Colors.white24),
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: cardAlt,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(14),
          borderSide: const BorderSide(color: seed, width: 1.6),
        ),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
      dividerTheme: DividerThemeData(color: Colors.white.withOpacity(0.06), thickness: 1),
      snackBarTheme: SnackBarThemeData(
        backgroundColor: cardAlt,
        contentTextStyle: const TextStyle(color: Colors.white),
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
    );
    return base;
  }

  static LinearGradient heroGradient() => const LinearGradient(
        colors: [Color(0xFF2A1B54), Color(0xFF0F2E46)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );

  static LinearGradient iconGradient() => const LinearGradient(
        colors: [Color(0xFF7C4DFF), Color(0xFF22D3EE)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      );
}
