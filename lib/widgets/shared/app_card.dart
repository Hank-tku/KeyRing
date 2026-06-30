import 'package:flutter/material.dart';

import '../../utils/theme_config.dart';

/// 统一卡片容器。
///
/// 取代散落在各页面的手画 `Container(decoration: BoxDecoration(...))`。
/// 统一圆角、内边距、可选点击涟漪（ripple）反馈。
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(ThemeConfig.space16),
    this.onTap,
    this.onLongPress,
    this.margin,
    this.borderColor,
    this.backgroundColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final EdgeInsetsGeometry? margin;

  /// 设置后卡片有点击涟漪反馈（InkWell）。null 时不可点击、无涟漪。
  final VoidCallback? onTap;

  /// 长按回调。配合 HapticFeedback 使用由调用方决定（本组件不强制）。
  final VoidCallback? onLongPress;

  /// 可选描边色（默认无描边）。
  final Color? borderColor;

  /// 覆盖默认卡片底色（默认走主题 cardTheme = fillColor）。
  final Color? backgroundColor;

  @override
  Widget build(BuildContext context) {
    final Card card = Card(
      color: backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ThemeConfig.radiusCard),
        side: borderColor == null
            ? BorderSide.none
            : BorderSide(color: borderColor!),
      ),
      margin: margin,
      child: Padding(
        padding: padding,
        child: child,
      ),
    );

    if (onTap == null && onLongPress == null) {
      return card;
    }

    // 用 InkWell 提供水波纹反馈——这是原 Container+GestureDetector 方案缺失的交互。
    return Card(
      color: backgroundColor,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(ThemeConfig.radiusCard),
        side: borderColor == null
            ? BorderSide.none
            : BorderSide(color: borderColor!),
      ),
      margin: margin,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: padding,
          child: child,
        ),
      ),
    );
  }
}
