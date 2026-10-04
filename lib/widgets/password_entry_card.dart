import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/password_item.dart';
import '../models/secret_field.dart';
import '../utils/theme_config.dart';
import 'shared/app_card.dart';

/// 右侧行按钮的固定槽位尺寸（眼睛 / 复制 / 收藏统一规格）。
const double _kSlotSize = 44;

/// 行标签列宽：让「用户名 / 密码 / 密码2 / 自定义名」纵向对齐，
/// 超长标签以省略号截断。
const double _kLabelWidth = 76;

/// 主密码的掩码状态键（自定义保密项用 SecretField.id）。
const String _kMainPasswordKey = '__password__';

/// 主页密码条目卡片：标题收藏 + 用户名 / 主密码 / 自定义保密项 / 网址主机。
///
/// - 保密值（主密码、password 类型或 protected 的自定义项）默认掩码，
///   每个字段独立显示 / 隐藏，互不影响；
/// - 记录变化（同步 / 编辑后重建对象）时统一重新掩码，避免明文跨记录残留；
/// - 行按钮（眼睛 / 复制 / 收藏）固定 44x44 槽位，右缘对齐，点击不透传到
///   卡片 [onTap]（不触发详情）；
/// - 复制始终复制原始值（与是否掩码显示无关），并给出 SnackBar 反馈；
/// - 组件只持有短暂掩码状态，不记录任何日志。
class PasswordEntryCard extends StatefulWidget {
  const PasswordEntryCard({
    super.key,
    required this.item,
    required this.onTap,
    required this.onLongPress,
    required this.onToggleFavorite,
  });

  final PasswordItem item;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggleFavorite;

  @override
  State<PasswordEntryCard> createState() => _PasswordEntryCardState();
}

class _PasswordEntryCardState extends State<PasswordEntryCard> {
  /// 短暂掩码状态：当前明文展示的字段 key 集合（主密码用 [_kMainPasswordKey]）。
  final Set<String> _revealed = <String>{};

  @override
  void didUpdateWidget(covariant PasswordEntryCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // 记录被编辑 / 同步覆盖后会得到新对象：全部重新掩码。
    if (!identical(widget.item, oldWidget.item)) {
      _revealed.clear();
    }
  }

  bool _isMaskable(SecretField field) =>
      field.protected || field.type == SecretFieldType.password;

  String _maskOf(String value) => '•' * value.length.clamp(6, 12);

  void _toggleReveal(String key) {
    setState(() {
      if (!_revealed.remove(key)) {
        _revealed.add(key);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final PasswordItem item = widget.item;
    final String? urlHost = _hostFromUrl(item.url);

    return AppCard(
      onTap: widget.onTap,
      onLongPress: widget.onLongPress,
      backgroundColor: item.isFavorite ? ThemeConfig.primarySoft : null,
      borderColor: item.isFavorite
          ? ThemeConfig.favoriteColor.withValues(alpha: 0.4)
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _buildTitleRow(),
          const SizedBox(height: ThemeConfig.space8),
          _buildUsernameRow(),
          const SizedBox(height: ThemeConfig.space8),
          _buildFieldRow(
            label: '密码',
            value: item.password,
            maskable: true,
            revealKey: _kMainPasswordKey,
          ),
          for (final SecretField field in item.customFields) ...<Widget>[
            const SizedBox(height: ThemeConfig.space8),
            _buildFieldRow(
              label: field.label,
              value: field.value,
              maskable: _isMaskable(field),
              revealKey: 'custom:${field.id}',
            ),
          ],
          if (urlHost != null) ...<Widget>[
            const SizedBox(height: ThemeConfig.space8),
            _buildFieldRow(
              label: '网址',
              value: urlHost,
              copyable: false,
              valueColor: ThemeConfig.hintTextColor,
              valueFontSize: ThemeConfig.fontSizeCaption,
            ),
          ],
        ],
      ),
    );
  }

  /// 标题行：标题 + 收藏 bookmark（44x44 槽位，右缘与各行复制按钮对齐）。
  Widget _buildTitleRow() {
    final bool isFavorite = widget.item.isFavorite;
    return Row(
      children: <Widget>[
        Expanded(
          child: Text(
            widget.item.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: ThemeConfig.textColor,
              fontSize: 20,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        SizedBox(
          width: _kSlotSize,
          height: _kSlotSize,
          child: IconButton(
            onPressed: widget.onToggleFavorite,
            icon: Icon(
              isFavorite ? Icons.bookmark : Icons.bookmark_border,
              size: 22,
              color: isFavorite
                  ? ThemeConfig.favoriteColor
                  : ThemeConfig.secondaryTextColor,
            ),
            tooltip: isFavorite ? '取消收藏' : '收藏',
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(
              minWidth: _kSlotSize,
              minHeight: _kSlotSize,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildUsernameRow() {
    final String username = widget.item.username;
    return _buildFieldRow(
      label: '用户名',
      value: username.isEmpty ? '无用户名' : username,
      copyable: username.isNotEmpty,
      valueColor: username.isEmpty ? ThemeConfig.hintTextColor : null,
    );
  }

  /// 单行字段：固定宽度标签 + 可截断/换行的值 + 可选眼睛/复制槽位。
  Widget _buildFieldRow({
    required String label,
    required String value,
    String? revealKey,
    bool maskable = false,
    bool copyable = true,
    Color? valueColor,
    double? valueFontSize,
  }) {
    final bool revealed =
        maskable && revealKey != null && _revealed.contains(revealKey);
    final String display = maskable && !revealed ? _maskOf(value) : value;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: <Widget>[
        SizedBox(
          width: _kLabelWidth,
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: ThemeConfig.hintTextColor,
              fontSize: ThemeConfig.fontSizeCaption,
            ),
          ),
        ),
        const SizedBox(width: ThemeConfig.space8),
        Expanded(
          child: Text(
            display,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: valueColor ?? ThemeConfig.textColor,
              fontSize: valueFontSize ?? ThemeConfig.fontSizeBody,
              letterSpacing: maskable && !revealed ? 1.5 : 0.0,
            ),
          ),
        ),
        if (maskable && revealKey != null)
          _EyeSlot(
            revealed: revealed,
            tooltip: (revealed ? '隐藏' : '显示') + label,
            onToggle: () => _toggleReveal(revealKey),
          ),
        if (copyable && value.isNotEmpty) _CopySlot(label: label, value: value),
      ],
    );
  }
}

/// 固定 44x44 的眼睛按钮：只切换自己字段的掩码。
class _EyeSlot extends StatelessWidget {
  const _EyeSlot({
    required this.revealed,
    required this.tooltip,
    required this.onToggle,
  });

  final bool revealed;
  final String tooltip;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _kSlotSize,
      height: _kSlotSize,
      child: IconButton(
        onPressed: onToggle,
        icon: Icon(
          revealed ? Icons.visibility_off_outlined : Icons.visibility_outlined,
        ),
        iconSize: 20,
        color: ThemeConfig.secondaryTextColor,
        tooltip: tooltip,
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(
          minWidth: _kSlotSize,
          minHeight: _kSlotSize,
        ),
      ),
    );
  }
}

/// 固定 44x44 的复制按钮：复制原始值并弹出标准化反馈。
///
/// 取代旧 CopyButton 在卡片里的非固定尺寸用法，保证各行右缘对齐。
class _CopySlot extends StatelessWidget {
  const _CopySlot({required this.label, required this.value});

  final String label;
  final String value;

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: value));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('已复制$label'),
        duration: const Duration(milliseconds: 1500),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _kSlotSize,
      height: _kSlotSize,
      child: IconButton(
        onPressed: () => _copy(context),
        icon: const Icon(Icons.copy_outlined),
        iconSize: 18,
        color: ThemeConfig.secondaryTextColor,
        tooltip: '复制$label',
        padding: EdgeInsets.zero,
        constraints: const BoxConstraints(
          minWidth: _kSlotSize,
          minHeight: _kSlotSize,
        ),
      ),
    );
  }
}

/// 从 url 中提取 host 用于卡片展示（如 https://github.com/x → github.com）。
String? _hostFromUrl(String? url) {
  if (url == null || url.isEmpty) return null;
  try {
    final Uri? uri = Uri.tryParse(url);
    if (uri != null && uri.host.isNotEmpty) {
      return uri.host;
    }
  } catch (_) {
    // 解析失败，回退到原始字符串。
  }
  return url;
}
