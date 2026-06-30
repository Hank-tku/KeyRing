import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../utils/theme_config.dart';

/// 统一的复制按钮。
///
/// 点击后：写入剪贴板 + 弹出标准化 SnackBar 反馈。
/// 取代各页面里重复的 `Clipboard.setData` + SnackBar 散落代码。
///
/// 注意：当前实现尚未做剪贴板自动清空（已在安全分析中列为独立优化项）。
/// 待该能力落地后，此处可统一注入倒计时逻辑，所有调用方自动获益。
class CopyButton extends StatelessWidget {
  const CopyButton({
    super.key,
    required this.text,
    this.label,
    this.iconSize = 18,
    this.color,
    this.showLabel = false,
  });

  /// 要复制到剪贴板的内容。
  final String text;

  /// SnackBar 中展示的语义名称，如「用户名」「密码」。null 时仅提示「已复制」。
  final String? label;

  final double iconSize;

  /// 图标颜色，默认走次级图标色。
  final Color? color;

  /// 是否显示「复制」文字（详情页备注行那种样式）。false 时只显示图标。
  final bool showLabel;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    final String message = (label == null || label!.isEmpty)
        ? '已复制'
        : '已复制$label';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final Color iconColor = color ?? ThemeConfig.secondaryTextColor;

    if (showLabel) {
      return InkWell(
        onTap: () => _copy(context),
        borderRadius: BorderRadius.circular(ThemeConfig.radiusPill),
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: ThemeConfig.space4,
            vertical: ThemeConfig.space4,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              Icon(Icons.copy, size: 16, color: iconColor),
              const SizedBox(width: ThemeConfig.space4),
              Text(
                '复制',
                style: TextStyle(
                  fontSize: ThemeConfig.fontSizeCaption,
                  color: iconColor,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return InkWell(
      onTap: () => _copy(context),
      borderRadius: BorderRadius.circular(ThemeConfig.radiusPill),
      child: Padding(
        padding: const EdgeInsets.only(left: ThemeConfig.space8),
        child: Icon(Icons.copy, size: iconSize, color: iconColor),
      ),
    );
  }
}
