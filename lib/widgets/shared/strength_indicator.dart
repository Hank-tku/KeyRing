import 'package:flutter/material.dart';

import '../../utils/password_utils.dart';
import '../../utils/theme_config.dart';

/// 密码强度指示器（分段式，替代原进度条样式）。
///
/// 复用 [PasswordUtils.checkStrength] 算法，确保与既有逻辑一致。
/// 展示 6 段色条 + 「密码强度：X」文字。空密码时显示「请输入密码」。
class StrengthIndicator extends StatelessWidget {
  const StrengthIndicator({super.key, required this.password});

  final String password;

  @override
  Widget build(BuildContext context) {
    if (password.isEmpty) {
      return Text(
        '请输入密码',
        style: TextStyle(
          fontSize: ThemeConfig.fontSizeCaption,
          color: ThemeConfig.hintTextColor,
        ),
      );
    }

    final PasswordStrength strength = PasswordUtils.checkStrength(password);
    final Color color = Color(PasswordUtils.getStrengthColor(strength));
    final String label = PasswordUtils.getStrengthDescription(strength);

    // PasswordStrength 枚举索引 0..5，共 6 段。
    // 用字面量而非 PasswordStrength.values.length，因为后者无法用于 const 表达式。
    final int filled = strength.index + 1;
    const int total = 6;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        // 分段色条
        ClipRRect(
          borderRadius: BorderRadius.circular(ThemeConfig.space4),
          child: Row(
            children: List<Widget>.generate(total, (int i) {
              final bool active = i < filled;
              return Expanded(
                child: Container(
                  height: 4,
                  margin: EdgeInsets.only(
                    right: i < total - 1 ? ThemeConfig.space4 : 0,
                  ),
                  color: active
                      ? color
                      : ThemeConfig.inputBorderColor.withValues(alpha: 0.5),
                ),
              );
            }),
          ),
        ),
        const SizedBox(height: ThemeConfig.space4),
        Text(
          '密码强度：$label',
          style: TextStyle(
            fontSize: ThemeConfig.fontSizeCaption,
            fontWeight: FontWeight.w600,
            color: color,
          ),
        ),
      ],
    );
  }
}
