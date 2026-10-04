import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../models/item_group.dart';
import '../models/password_item.dart';
import '../models/secret_field.dart';
import '../models/workspace.dart';
import '../services/password_repository.dart';
import '../utils/theme_config.dart';
import '../widgets/shared/app_card.dart';
import '../widgets/shared/copy_button.dart';
import '../widgets/shared/password_visibility_toggle.dart';
import 'edit_item_screen.dart';
import '../widgets/shared/workspace_guard.dart';

class DetailScreen extends StatefulWidget {
  const DetailScreen({super.key, required this.item, required this.repository});

  final PasswordItem item;
  final PasswordRepository repository;

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  bool _obscurePassword = true;

  /// 已点击显示的保密项 id（默认全部掩码）。
  final Set<String> _revealedFieldIds = <String>{};

  // 编辑返回后刷新本页展示的数据（在 initState 中初始化）。
  late PasswordItem _current;

  @override
  void initState() {
    super.initState();
    _current = widget.item;
  }

  Future<void> _edit() async {
    if (!await authorizeWorkspace(
          context,
          widget.repository,
          _current.workspaceId,
        ) ||
        !mounted) {
      return;
    }
    final bool? changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) =>
            EditItemScreen(repository: widget.repository, initial: _current),
      ),
    );
    if (changed != true || !mounted) return;
    // 编辑后从仓库取最新值刷新本页。
    final PasswordItem? fresh = await widget.repository.getByIdAsync(
      _current.id,
    );
    if (!mounted) return;
    if (fresh != null) {
      setState(() {
        _current = fresh;
        _obscurePassword = true;
        _revealedFieldIds.clear();
      });
    }
    // 首页监听仓库通知；保存后保持详情页打开。
  }

  Future<void> _delete() async {
    if (!await authorizeWorkspace(
          context,
          widget.repository,
          _current.workspaceId,
        ) ||
        !mounted) {
      return;
    }
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除"${_current.title}"吗？此操作无法撤销。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(
              foregroundColor: ThemeConfig.dangerColor,
            ),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await widget.repository.removeItem(_current.id);
        if (mounted) {
          Navigator.of(context).pop(true);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text('删除失败: $e')));
        }
      }
    }
  }

  String _formatDateTime(DateTime dateTime) {
    return DateFormat('yyyy-MM-dd HH:mm').format(dateTime);
  }

  /// 从 url 提取 host 用于头像区展示。
  String _hostFromUrl(String url) {
    try {
      final Uri? uri = Uri.tryParse(url);
      if (uri != null && uri.host.isNotEmpty) {
        return uri.host;
      }
    } catch (_) {
      // ignore
    }
    return url;
  }

  @override
  Widget build(BuildContext context) {
    final String? url = (_current.url != null && _current.url!.isNotEmpty)
        ? _current.url
        : null;

    return Scaffold(
      appBar: AppBar(
        title: const Text('密码详情'),
        titleTextStyle: const TextStyle(
          color: ThemeConfig.primaryColor,
          fontSize: ThemeConfig.fontSizeTitle,
          fontWeight: FontWeight.w500,
        ),
        actions: <Widget>[
          IconButton(
            onPressed: _edit,
            icon: const Icon(Icons.edit_outlined),
            tooltip: '编辑',
          ),
          IconButton(
            onPressed: _delete,
            icon: const Icon(Icons.delete_outline),
            tooltip: '删除',
          ),
        ],
      ),
      body: WorkspaceGuard(
        repository: widget.repository,
        workspaceId: _current.workspaceId,
        child: ListView(
          padding: const EdgeInsets.all(ThemeConfig.space16),
          children: <Widget>[
            _buildHeader(url),
            const SizedBox(height: ThemeConfig.space16),
            _buildBasicInfoCard(),
            if (_current.customFields.isNotEmpty) ...<Widget>[
              const SizedBox(height: ThemeConfig.space12),
              _buildSecretFieldsCard(),
            ],
            ...<Widget>[
              const SizedBox(height: ThemeConfig.space12),
              _buildNotesCard(),
            ],
            const SizedBox(height: ThemeConfig.space12),
            _buildMetaCard(),
            const SizedBox(height: ThemeConfig.space24),
          ],
        ),
      ),
    );
  }

  /// 顶部头像区：首字母圆形 + 标题 + 网址来源 + 收藏 bookmark。
  Widget _buildHeader(String? url) {
    final String initial = _current.title.isNotEmpty
        ? _current.title.characters.first.toUpperCase()
        : '?';
    return AppCard(
      child: Row(
        children: <Widget>[
          Container(
            width: 54,
            height: 54,
            decoration: BoxDecoration(
              color: ThemeConfig.primarySoft,
              borderRadius: BorderRadius.circular(ThemeConfig.radiusMd),
            ),
            alignment: Alignment.center,
            child: Text(
              initial,
              style: const TextStyle(
                color: ThemeConfig.primaryColor,
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          const SizedBox(width: ThemeConfig.space16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: <Widget>[
                Text(
                  _current.title,
                  style: const TextStyle(
                    color: ThemeConfig.textColor,
                    fontSize: 21,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                if (url != null) ...<Widget>[
                  const SizedBox(height: 4),
                  Row(
                    children: <Widget>[
                      Icon(
                        Icons.language,
                        size: 13,
                        color: ThemeConfig.hintTextColor,
                      ),
                      const SizedBox(width: ThemeConfig.space4),
                      Flexible(
                        child: Text(
                          _hostFromUrl(url),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: ThemeConfig.hintTextColor,
                            fontSize: ThemeConfig.fontSizeCaption,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          if (_current.isFavorite)
            Icon(Icons.bookmark, color: ThemeConfig.favoriteColor, size: 22),
        ],
      ),
    );
  }

  Widget _buildBasicInfoCard() {
    final bool hasUsername = _current.username.isNotEmpty;
    final bool hasUrl = _current.url != null && _current.url!.isNotEmpty;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildFieldRow(
            label: '用户名',
            value: hasUsername ? _current.username : null,
            emptyText: '未设置',
            showCopy: hasUsername,
            copyText: _current.username,
            copyLabel: '用户名',
          ),
          const Divider(),
          _buildPasswordRow(),
          ...<Widget>[
            const Divider(),
            _buildFieldRow(
              label: '网址',
              value: hasUrl ? _current.url : null,
              emptyText: '未设置',
              showCopy: hasUrl,
              copyText: _current.url ?? '',
              copyLabel: '网址',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildNotesCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              const Text(
                '备注',
                style: TextStyle(
                  color: ThemeConfig.hintTextColor,
                  fontSize: ThemeConfig.fontSizeBody,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const Spacer(),
              CopyButton(
                text: _current.notes ?? '',
                label: '备注',
                showLabel: true,
              ),
            ],
          ),
          const SizedBox(height: ThemeConfig.space8),
          SelectableText(
            _current.notes?.isNotEmpty == true ? _current.notes! : '未填写',
            style: const TextStyle(
              color: ThemeConfig.textColor,
              fontSize: ThemeConfig.fontSizeBody,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }

  /// 保密项卡片：protected 项默认掩码，可显示/复制。
  Widget _buildSecretFieldsCard() {
    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          const Text(
            '保密项',
            style: TextStyle(
              color: ThemeConfig.hintTextColor,
              fontSize: ThemeConfig.fontSizeBody,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: ThemeConfig.space4),
          for (int i = 0; i < _current.customFields.length; i++) ...<Widget>[
            if (i > 0) const Divider(),
            _buildSecretFieldRow(_current.customFields[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildSecretFieldRow(SecretField field) {
    final bool revealed = _revealedFieldIds.contains(field.id);
    final bool isSecret = field.protected || field.type == SecretFieldType.password;
    final bool masked = isSecret && !revealed;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ThemeConfig.space8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 110),
            child: Text(
              field.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ThemeConfig.textColor,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: ThemeConfig.space12),
          Expanded(
            child: Text(
              masked ? '•' * (field.value.length.clamp(6, 12)) : field.value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: ThemeConfig.textColor,
                fontSize: 15,
                letterSpacing: masked ? 2.0 : 0.0,
              ),
            ),
          ),
          if (isSecret)
            PasswordVisibilityToggle(
              obscured: masked,
              onToggle: () => setState(() {
                if (revealed) {
                  _revealedFieldIds.remove(field.id);
                } else {
                  _revealedFieldIds.add(field.id);
                }
              }),
            ),
          CopyButton(text: field.value, label: field.label, iconSize: 17),
        ],
      ),
    );
  }

  Widget _buildMetaCard() {
    final Workspace? workspace = widget.repository.workspacesNotifier.value
        .where((Workspace w) => w.id == _current.workspaceId)
        .firstOrNull;
    final ItemGroup? group = _current.groupId == null
        ? null
        : widget.repository.groupsNotifier.value
              .where((ItemGroup g) => g.id == _current.groupId)
              .firstOrNull;

    return AppCard(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          _buildFieldRow(
            label: '归属',
            value: <String>[
              if (workspace != null)
                '${workspace.icon ?? ''} ${workspace.name}'.trim(),
              if (group != null) group.name,
            ].join(' · '),
          ),
          const Divider(),
          _buildFieldRow(
            label: '创建时间',
            value: _formatDateTime(_current.createdAt),
          ),
          const Divider(),
          _buildFieldRow(
            label: '更新时间',
            value: _formatDateTime(_current.updatedAt),
          ),
        ],
      ),
    );
  }

  Widget _buildFieldRow({
    required String label,
    String? value,
    String emptyText = '',
    bool showCopy = false,
    String copyText = '',
    String copyLabel = '',
  }) {
    final bool isEmpty = value == null || value.isEmpty;
    final String display = isEmpty ? emptyText : value;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ThemeConfig.space8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          SizedBox(
            width: 64,
            child: Text(
              label,
              style: const TextStyle(
                color: ThemeConfig.hintTextColor,
                fontSize: ThemeConfig.fontSizeBody,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: ThemeConfig.space12),
          Expanded(
            child: SelectableText(
              display,
              style: TextStyle(
                color: isEmpty
                    ? ThemeConfig.hintTextColor
                    : ThemeConfig.textColor,
                fontSize: 15,
              ),
            ),
          ),
          if (showCopy && !isEmpty)
            CopyButton(text: copyText, label: copyLabel, iconSize: 17),
        ],
      ),
    );
  }

  /// 密码行：常驻眼睛 + 复制（不用先点眼睛才出现复制）。
  Widget _buildPasswordRow() {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: ThemeConfig.space8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: <Widget>[
          const SizedBox(
            width: 64,
            child: Text(
              '密码',
              style: TextStyle(
                color: ThemeConfig.hintTextColor,
                fontSize: ThemeConfig.fontSizeBody,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(width: ThemeConfig.space12),
          Expanded(
            child: Text(
              _obscurePassword
                  ? '•' * (_current.password.length.clamp(6, 12))
                  : _current.password,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                color: ThemeConfig.textColor,
                fontSize: 15,
                letterSpacing: 2,
              ),
            ),
          ),
          PasswordVisibilityToggle(
            obscured: _obscurePassword,
            onToggle: () =>
                setState(() => _obscurePassword = !_obscurePassword),
          ),
          CopyButton(text: _current.password, label: '密码', iconSize: 17),
        ],
      ),
    );
  }
}
