import 'package:flutter/material.dart';

// Industrial Orange Theme (2025)
class AppTheme {
  // ============================
  // Brand / Semantic Colors
  // ============================

  // --- Light ---
  static const Color lightBackground = Color(0xFFF5F2EF); // 非純白
  static const Color lightSurface = Color(0xFFE7DED6); // 區塊背景
  static const Color lightPrimaryOrange = Color(0xFFBA7954); // 品牌橘
  static const Color lightPrimaryText = Color(0xFF2F2A26); // 高可讀深灰棕
  static const Color lightSecondaryText = Color(0xFF6B5F55);

  // --- Dark ---
  static const Color darkBackground = Color(0xFF12100E); // 暖碳黑
  static const Color darkSurface = Color(0xFF1F1B17); // 區塊層次
  static const Color darkPrimaryOrange = Color(0xFFD89A6C); // 提亮品牌橘
  static const Color darkPrimaryText = Color(0xFFF2ECE6);
  static const Color darkSecondaryText = Color(0xFFB8ADA5);

  // Common
  static const Color errorColor = Color(0xFFD32F2F);
  static const Color successColor = Color(0xFF2E7D32);

  // ============================
  // Light Theme
  // ============================
  static ThemeData get lightTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      scaffoldBackgroundColor: lightBackground,

      colorScheme: ColorScheme.light(
        primary: lightPrimaryOrange,
        background: lightBackground,
        surface: lightSurface,
        onPrimary: Colors.white,
        onBackground: lightPrimaryText,
        onSurface: lightPrimaryText,
        error: errorColor,
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: lightBackground,
        foregroundColor: lightPrimaryText,
        elevation: 0,
        centerTitle: true,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: lightSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.transparent),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.transparent),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: lightPrimaryOrange, width: 2),
        ),
        hintStyle: const TextStyle(color: lightSecondaryText),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: lightPrimaryOrange,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }

  // ============================
  // Dark Theme
  // ============================
  static ThemeData get darkTheme {
    return ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      scaffoldBackgroundColor: darkBackground,

      colorScheme: ColorScheme.dark(
        primary: darkPrimaryOrange,
        background: darkBackground,
        surface: darkSurface,
        onPrimary: darkBackground,
        onBackground: darkPrimaryText,
        onSurface: darkPrimaryText,
        error: errorColor,
      ),

      appBarTheme: const AppBarTheme(
        backgroundColor: darkBackground,
        foregroundColor: darkPrimaryText,
        elevation: 0,
        centerTitle: true,
      ),

      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: darkSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.transparent),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.transparent),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: darkPrimaryOrange, width: 2),
        ),
        hintStyle: const TextStyle(color: darkSecondaryText),
      ),

      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: darkPrimaryOrange,
          foregroundColor: darkBackground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
          padding: const EdgeInsets.symmetric(vertical: 16),
        ),
      ),
    );
  }
}
