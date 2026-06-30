import 'package:flutter/material.dart';

import '../../utils/theme_config.dart';

/// 密码显隐切换按钮（眼睛图标）。
///
/// 详情页、编辑页、列表卡片共用。调用方持有 [obscured] 状态，点击时翻转。
class PasswordVisibilityToggle extends StatelessWidget {
  const PasswordVisibilityToggle({
    super.key,
    required this.obscured,
    required this.onToggle,
    this.iconSize = 18,
    this.color,
  });

  /// 当前是否处于遮罩态。
  final bool obscured;

  final VoidCallback onToggle;
  final double iconSize;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onToggle,
      borderRadius: BorderRadius.circular(ThemeConfig.radiusPill),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: ThemeConfig.space8),
        child: Icon(
          obscured ? Icons.visibility : Icons.visibility_off,
          size: iconSize,
          color: color ?? ThemeConfig.secondaryTextColor,
        ),
      ),
    );
  }
}
