import 'package:flutter/material.dart';

/// A widget that generates the app icon design
/// This can be used to preview the icon or generate it programmatically
class ThemeConfig {
  static const mainBgColor = Color(0xFF121A2E);
  static const primaryColor = Color(0xFF2DD4BF);
  static const fillColor = Color(0xFF1E293B);
  static const hintTextColor = Color(0xFF9CA3AF);
  static const textColor = Color(0xFFffffff);
  static const inputBorderColor = Color(0x80334155);

  static ThemeData appTheme = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: Brightness.light,
    ),
    useMaterial3: true,
    scaffoldBackgroundColor: mainBgColor,
    fontFamily: 'Roboto',

    appBarTheme: const AppBarTheme(
      elevation: 0,
      backgroundColor: mainBgColor,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Colors.black87,
      iconTheme: IconThemeData(
        color: Colors.white, // 将返回按钮等图标的颜色设置为白色
      ),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: fillColor,
      isCollapsed: false,
      hintStyle: const TextStyle(color: hintTextColor),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: inputBorderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: inputBorderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: primaryColor, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
    cardTheme: const CardThemeData(
      color: Colors.white,
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
    snackBarTheme: const SnackBarThemeData(behavior: SnackBarBehavior.floating),
  );
}
