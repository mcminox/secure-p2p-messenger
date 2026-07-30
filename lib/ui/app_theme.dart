import 'package:flutter/material.dart';

ThemeData buildAppTheme() {
  const seed = Color(0xFF8B5CF6);
  final base = ThemeData(
    useMaterial3: true,
    brightness: Brightness.dark,
    colorScheme: ColorScheme.fromSeed(
      seedColor: seed,
      brightness: Brightness.dark,
    ),
  );
  return base.copyWith(
    scaffoldBackgroundColor: const Color(0xFF090A12),
    colorScheme: base.colorScheme.copyWith(
      primary: const Color(0xFF9C6BFF),
      secondary: const Color(0xFF4DE6D3),
      tertiary: const Color(0xFF6FB2FF),
      surface: const Color(0xFF101323),
      surfaceContainer: const Color(0xFF151A2D),
      surfaceContainerHighest: const Color(0xFF1C2136),
      error: const Color(0xFFFF667A),
    ),
    cardTheme: CardThemeData(
      color: const Color(0xFF14192C).withValues(alpha: 0.76),
      elevation: 0,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    appBarTheme: AppBarTheme(
      centerTitle: false,
      backgroundColor: Colors.black.withValues(alpha: 0.2),
      surfaceTintColor: Colors.transparent,
      titleTextStyle: const TextStyle(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        color: Colors.white,
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: const Color(0xFF171B2D).withValues(alpha: 0.78),
      hintStyle: const TextStyle(color: Color(0xFF8E9CB8)),
      labelStyle: const TextStyle(color: Color(0xFFC6D2E8)),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(16),
        borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.12)),
      ),
      focusedBorder: const OutlineInputBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
        borderSide: BorderSide(color: Color(0xFF4DE6D3), width: 1.4),
      ),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        backgroundColor: const Color(0xFF6E42E5),
        foregroundColor: Colors.white,
        minimumSize: const Size(0, 48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    outlinedButtonTheme: OutlinedButtonThemeData(
      style: OutlinedButton.styleFrom(
        foregroundColor: const Color(0xFFC4F9F2),
        side: BorderSide(color: const Color(0xFF4DE6D3).withValues(alpha: 0.4)),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
      ),
    ),
    pageTransitionsTheme: const PageTransitionsTheme(
      builders: {
        TargetPlatform.android: FadeUpwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: FadeUpwardsPageTransitionsBuilder(),
      },
    ),
  );
}
