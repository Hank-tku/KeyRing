import 'package:flutter/material.dart';

/// 全局主题与设计 Token 配置。
///
/// 配色方向：雅致紫（#A78BFA）+ 深灰黑层次背景。
/// 所有颜色必须从此类取用，禁止在页面里硬编码 Color(0x...)。
class ThemeConfig {
  // ---- 背景层次（从深到浅）----
  /// 最深层，主背景。
  static const mainBgColor = Color(0xFF0F1115);

  /// 卡片 / 表面。
  static const fillColor = Color(0xFF181B23);

  /// 次级表面（输入框 / hover）。
  static const surfaceColor = Color(0xFF1F2330);

  // ---- 品牌色 ----
  /// 雅致紫，主操作色。
  static const primaryColor = Color(0xFFA78BFA);

  /// 品牌色软背景（图标底、avatar 底、chip 选中底）。
  static Color get primarySoft => primaryColor.withValues(alpha: 0.14);

  // ---- 文字层次 ----
  static const textColor = Color(0xFFF4F5F7);
  static const secondaryTextColor = Color(0xFF9BA1AE);
  static const hintTextColor = Color(0xFF5E6573);

  // ---- 描边 ----
  static const inputBorderColor = Color(0xFF21262F);
  static const dividerColor = Color(0xFF2A2F3D);

  // ---- 语义色 ----
  static const successColor = Color(0xFF4ADE80);
  static const warningColor = Color(0xFFFBBF24);
  static const dangerColor = Color(0xFFF87171);
  static const infoColor = Color(0xFF60A5FA);

  /// 收藏图标 / 强调色（bookmark 选中色）。
  static Color get favoriteColor => primaryColor;

  // ---- 设计 Token：spacing（8pt 栅格）----
  static const double space4 = 4;
  static const double space8 = 8;
  static const double space12 = 12;
  static const double space16 = 16;
  static const double space20 = 20;
  static const double space24 = 24;
  static const double space32 = 32;

  // ---- 设计 Token：圆角 ----
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusCard = 16;
  static const double radiusPill = 999;

  // ---- 设计 Token：字号 ----
  static const double fontSizeCaption = 12;
  static const double fontSizeBody = 14;
  static const double fontSizeSubtitle = 16;
  static const double fontSizeTitle = 22;

  static ThemeData appTheme = ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: primaryColor,
      brightness: Brightness.dark,
    ).copyWith(
      primary: primaryColor,
      onPrimary: const Color(0xFF0F1115),
      surface: fillColor,
      onSurface: textColor,
      error: dangerColor,
    ),
    useMaterial3: true,
    scaffoldBackgroundColor: mainBgColor,
    fontFamily: 'Roboto',

    appBarTheme: const AppBarTheme(
      elevation: 0,
      backgroundColor: mainBgColor,
      surfaceTintColor: Colors.transparent,
      foregroundColor: Colors.white,
      iconTheme: IconThemeData(color: Colors.white),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: fillColor,
      isCollapsed: false,
      hintStyle: const TextStyle(color: hintTextColor),
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: inputBorderColor),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: const BorderSide(color: inputBorderColor),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(radiusMd),
        borderSide: BorderSide(color: primaryColor, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
    ),
    cardTheme: const CardThemeData(
      color: fillColor,
      elevation: 0,
      margin: EdgeInsets.zero,
    ),
    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMd),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primaryColor,
      foregroundColor: const Color(0xFF0F1115),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(radiusMd),
      ),
    ),
    dividerTheme: const DividerThemeData(
      color: inputBorderColor,
      thickness: 1,
      space: 1,
    ),
    iconButtonTheme: IconButtonThemeData(
      style: IconButton.styleFrom(foregroundColor: secondaryTextColor),
    ),
  );
}
