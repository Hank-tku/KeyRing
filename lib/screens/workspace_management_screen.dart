import 'package:flutter/material.dart';

import '../models/workspace.dart';
import '../services/password_repository.dart';
import '../utils/theme_config.dart';
import '../widgets/shared/workspace_guard.dart';
import '../widgets/workspace_management_tile.dart';
import 'workspace_password_screen.dart';

/// 工作区管理页：新建/编辑/删除/排序，配置同步策略。
///
/// 同步策略是本应用的选择性同步边界（设计文档 §3.1）：
/// - 全设备同步：所有已配对设备
/// - 仅移动端：手机↔手机可同步，绝不发送给电脑（连工作区名称都不发送）
/// - 仅本机：不参与任何同步
class WorkspaceManagementScreen extends StatefulWidget {
  const WorkspaceManagementScreen({super.key, required this.repository});

  final PasswordRepository repository;

  @override
  State<WorkspaceManagementScreen> createState() =>
      _WorkspaceManagementScreenState();
}

class _WorkspaceManagementScreenState extends State<WorkspaceManagementScreen> {
  final Map<String, int> _itemCounts = <String, int>{};

  @override
  void initState() {
    super.initState();
    widget.repository.workspacesNotifier.addListener(_reloadCounts);
    _reloadCounts();
  }

  @override
  void dispose() {
    widget.repository.workspacesNotifier.removeListener(_reloadCounts);
    super.dispose();
  }

  Future<void> _reloadCounts() async {
    final Map<String, int> counts = <String, int>{};
    for (final Workspace w in widget.repository.workspacesNotifier.value) {
      counts[w.id] = await widget.repository.itemCountInWorkspace(w.id);
    }
    if (mounted) {
      setState(
        () => _itemCounts
          ..clear()
          ..addAll(counts),
      );
    }
  }

  Future<void> _editWorkspace({Workspace? initial}) async {
    if (initial != null &&
        (!await authorizeWorkspace(context, widget.repository, initial.id) ||
            !mounted)) {
      return;
    }
    final bool? saved = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (_) => _WorkspaceEditPage(
          repository: widget.repository,
          initial: initial,
          itemCount: initial == null ? 0 : (_itemCounts[initial.id] ?? 0),
        ),
      ),
    );
    if (saved == true) {
      await _reloadCounts();
    }
  }

  Future<void> _deleteWorkspace(Workspace workspace) async {
    if (!await authorizeWorkspace(context, widget.repository, workspace.id) ||
        !mounted) {
      return;
    }
    final int count = _itemCounts[workspace.id] ?? 0;
    if (count > 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('"${workspace.name}" 内还有 $count 个条目，请先移动或删除'),
          backgroundColor: ThemeConfig.warningColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('删除工作区'),
        content: Text(
          '确定要删除"${workspace.name}"吗？已同步到其它设备的工作区数据'
          '也会在下次同步时删除。',
        ),
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
    if (confirm != true || !mounted) return;
    try {
      await widget.repository.deleteWorkspace(workspace.id);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('删除失败: $e'),
            backgroundColor: ThemeConfig.dangerColor,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final List<Workspace> workspaces =
        widget.repository.workspacesNotifier.value;

    return Scaffold(
      appBar: AppBar(title: const Text('工作区管理')),
      body: workspaces.isEmpty
          ? const Center(child: Text('暂无工作区'))
          : ReorderableListView.builder(
              buildDefaultDragHandles: false,
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 80),
              itemCount: workspaces.length,
              onReorderItem: (int oldIndex, int newIndex) {
                final List<String> ids = workspaces
                    .map((Workspace w) => w.id)
                    .toList();
                ids.insert(newIndex, ids.removeAt(oldIndex));
                widget.repository.reorderWorkspaces(ids);
              },
              itemBuilder: (BuildContext context, int index) {
                final Workspace w = workspaces[index];
                final int count = _itemCounts[w.id] ?? 0;
                return Padding(
                  key: ValueKey<String>(w.id),
                  padding: const EdgeInsets.only(bottom: 8),
                  child: WorkspaceManagementTile(
                    workspace: w,
                    itemCount: count,
                    isProtected: widget.repository.access.isProtected(w.id),
                    index: index,
                    onEdit: () => _editWorkspace(initial: w),
                    onDelete: () => _deleteWorkspace(w),
                    onConfigureAccess: () async {
                      await Navigator.of(context).push(
                        MaterialPageRoute<void>(
                          builder: (_) => WorkspacePasswordScreen(
                            repository: widget.repository,
                            workspace: w,
                          ),
                        ),
                      );
                      if (mounted) setState(() {});
                    },
                  ),
                );
              },
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _editWorkspace(),
        icon: const Icon(Icons.add),
        label: const Text('新建工作区'),
      ),
    );
  }
}

/// 新建/编辑工作区页。
class _WorkspaceEditPage extends StatefulWidget {
  const _WorkspaceEditPage({
    required this.repository,
    this.initial,
    required this.itemCount,
  });

  final PasswordRepository repository;
  final Workspace? initial;
  final int itemCount;

  @override
  State<_WorkspaceEditPage> createState() => _WorkspaceEditPageState();
}

class _WorkspaceEditPageState extends State<_WorkspaceEditPage> {
  static const List<String> _iconPresets = <String>[
    '🏠',
    '💼',
    '🔐',
    '🏦',
    '🌐',
    '⭐',
    '🎮',
    '🛒',
    '📷',
    '💰',
    '✈️',
    '🎓',
  ];

  late final TextEditingController _nameController;
  late String _icon;
  late SyncPolicy _policy;

  @override
  void initState() {
    super.initState();
    final Workspace? initial = widget.initial;
    _nameController = TextEditingController(text: initial?.name ?? '');
    _icon = initial?.icon ?? _iconPresets[_iconPresets.length ~/ 2];
    _policy = initial?.syncPolicy ?? SyncPolicy.full;
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  static const Map<SyncPolicy, (String, String)> _policyDescriptions =
      <SyncPolicy, (String, String)>{
        SyncPolicy.full: ('全设备同步', '在所有已配对设备间同步，适合普通账号。'),
        SyncPolicy.mobileOnly: (
          '仅移动端',
          '只在手机/平板之间同步，永远不会发送到电脑——'
              '包括工作区名称。适合银行、密钥等高隐私条目。',
        ),
        SyncPolicy.localOnly: ('仅本机', '只保存在这台设备上，不参与任何同步。'),
      };

  Future<bool> _confirmNarrowing(SyncPolicy from, SyncPolicy to) async {
    if (from == to) return true;
    final bool broader = switch ((from, to)) {
      (SyncPolicy.full, SyncPolicy.mobileOnly) => true,
      (SyncPolicy.full, SyncPolicy.localOnly) => true,
      (SyncPolicy.mobileOnly, SyncPolicy.localOnly) => true,
      _ => false,
    };
    if (!broader) return true;

    final String target = to == SyncPolicy.mobileOnly ? '电脑端' : '其它所有设备';
    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('收窄同步范围'),
        content: Text(
          '$target将删除该工作区的全部条目（${widget.itemCount} 项）。'
          '本机数据保留。确定继续吗？',
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('继续'),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

  Future<void> _save() async {
    if (widget.initial != null &&
        (!await authorizeWorkspace(
              context,
              widget.repository,
              widget.initial!.id,
            ) ||
            !mounted)) {
      return;
    }
    final String name = _nameController.text.trim();
    if (name.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('请输入工作区名称'),
          backgroundColor: ThemeConfig.warningColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    // 同名检查（不同 id 视为不同工作区）。
    final bool nameExists = widget.repository.workspacesNotifier.value.any(
      (Workspace w) => w.id != widget.initial?.id && w.name == name,
    );
    if (nameExists) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('已有同名工作区'),
          backgroundColor: ThemeConfig.warningColor,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final Workspace? initial = widget.initial;
    if (initial != null &&
        !await _confirmNarrowing(initial.syncPolicy, _policy)) {
      return;
    }

    if (initial == null) {
      await widget.repository.addWorkspace(
        Workspace(name: name, icon: _icon, syncPolicy: _policy),
      );
    } else {
      await widget.repository.updateWorkspace(
        initial.copyWith(name: name, icon: _icon, syncPolicy: _policy),
      );
    }
    if (mounted) Navigator.of(context).pop(true);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.initial == null ? '新建工作区' : '编辑工作区')),
      body: ListView(
        padding: const EdgeInsets.all(ThemeConfig.space16),
        children: <Widget>[
          Text(
            '名称',
            style: TextStyle(
              color: ThemeConfig.textColor,
              fontSize: ThemeConfig.fontSizeSubtitle,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: ThemeConfig.space8),
          TextField(
            controller: _nameController,
            style: const TextStyle(color: ThemeConfig.textColor),
            decoration: InputDecoration(
              hintText: '如：个人 / 工作 / 高隐私',
              filled: true,
              fillColor: ThemeConfig.fillColor,
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(ThemeConfig.radiusMd),
                borderSide: const BorderSide(color: ThemeConfig.dividerColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(ThemeConfig.radiusMd),
                borderSide: const BorderSide(color: ThemeConfig.primaryColor),
              ),
            ),
          ),
          const SizedBox(height: ThemeConfig.space16),
          Text(
            '图标',
            style: TextStyle(
              color: ThemeConfig.textColor,
              fontSize: ThemeConfig.fontSizeSubtitle,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: ThemeConfig.space8),
          Wrap(
            spacing: ThemeConfig.space8,
            runSpacing: ThemeConfig.space8,
            children: <Widget>[
              for (final String emoji in _iconPresets)
                InkWell(
                  onTap: () => setState(() => _icon = emoji),
                  borderRadius: BorderRadius.circular(ThemeConfig.radiusMd),
                  child: Container(
                    width: 44,
                    height: 44,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _icon == emoji
                          ? ThemeConfig.primarySoft
                          : ThemeConfig.fillColor,
                      borderRadius: BorderRadius.circular(ThemeConfig.radiusMd),
                      border: Border.all(
                        color: _icon == emoji
                            ? ThemeConfig.primaryColor
                            : ThemeConfig.dividerColor,
                        width: _icon == emoji ? 2 : 1,
                      ),
                    ),
                    child: Text(emoji, style: const TextStyle(fontSize: 22)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: ThemeConfig.space16),
          Text(
            '同步策略',
            style: TextStyle(
              color: ThemeConfig.textColor,
              fontSize: ThemeConfig.fontSizeSubtitle,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: ThemeConfig.space4),
          RadioGroup<SyncPolicy>(
            groupValue: _policy,
            onChanged: (SyncPolicy? v) {
              if (v != null) setState(() => _policy = v);
            },
            child: Column(
              children: <Widget>[
                for (final SyncPolicy policy in SyncPolicy.values)
                  RadioListTile<SyncPolicy>(
                    value: policy,
                    title: Text(
                      _policyDescriptions[policy]!.$1,
                      style: const TextStyle(
                        color: ThemeConfig.textColor,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    subtitle: Text(
                      _policyDescriptions[policy]!.$2,
                      style: const TextStyle(
                        color: ThemeConfig.secondaryTextColor,
                        fontSize: ThemeConfig.fontSizeCaption,
                        height: 1.4,
                      ),
                    ),
                    activeColor: ThemeConfig.primaryColor,
                    contentPadding: EdgeInsets.zero,
                  ),
              ],
            ),
          ),
          const SizedBox(height: ThemeConfig.space16),
          FilledButton(
            onPressed: _save,
            style: FilledButton.styleFrom(
              backgroundColor: ThemeConfig.primaryColor,
              foregroundColor: const Color(0xFF0B1220),
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(ThemeConfig.radiusMd),
              ),
            ),
            child: const Text(
              '保存',
              style: TextStyle(fontWeight: FontWeight.w600),
            ),
          ),
        ],
      ),
    );
  }
}
