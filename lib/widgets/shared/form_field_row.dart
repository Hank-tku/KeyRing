import 'package:flutter/material.dart';

import '../../utils/theme_config.dart';

/// 统一的「label + 控件」表单行布局。
///
/// 取代 edit_item_screen 中 `_buildFormItem` 写死 SizedBox(width:72) 的手写布局。
/// 支持垂直居中或顶部对齐（多行输入如备注用顶部对齐）。
class FormFieldRow extends StatelessWidget {
  const FormFieldRow({
    super.key,
    required this.label,
    required this.child,
    this.alignWithField = false,
    this.labelWidth = 72,
  });

  final String label;
  final Widget child;

  /// true 时 label 顶部对齐（用于 TextArea 等多行控件）。
  final bool alignWithField;

  /// label 列宽，默认 72（与既有视觉一致）。
  final double labelWidth;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: ThemeConfig.space8),
      child: Row(
        crossAxisAlignment: alignWithField
            ? CrossAxisAlignment.start
            : CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: labelWidth,
            height: alignWithField ? null : 40,
            child: alignWithField
                ? Align(
                    alignment: Alignment.topLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(top: ThemeConfig.space12),
                      child: Text(
                        label,
                        style: const TextStyle(
                          fontSize: ThemeConfig.fontSizeBody,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  )
                : Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: ThemeConfig.fontSizeBody,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
          ),
          const SizedBox(width: ThemeConfig.space8),
          Expanded(child: child),
        ],
      ),
    );
  }
}
