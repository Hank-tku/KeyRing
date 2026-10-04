import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';

import '../../models/item_group.dart';
import '../../models/password_item.dart';
import '../../models/workspace.dart';
import '../../services/chrome_csv_import_service.dart';
import '../../services/password_repository.dart';
import '../../utils/theme_config.dart';
import '../../widgets/shared/workspace_guard.dart';

/// 从 Chrome 导出的 CSV 文件导入密码。
///
/// 流程：导出指引 → 选择 CSV 与目标工作区/分组 → 预览（冲突逐条选择）→
/// 确认导入 → 结果汇总并以 [Navigator.pop] 返回结果描述（String）。
///
/// 集成方式（主任务接入 import 入口时）：
/// ```dart
/// final String? summary = await Navigator.of(context).push<String>(
///   MaterialPageRoute<String>(
///     builder: (_) => ChromeImportScreen(
///       repository: repository,
///       initialWorkspaceId: currentWorkspaceId,
///       authorizeWorkspace: (String workspaceId) =>
///           verifyWorkspaceAccess(context, workspaceId),
///     ),
///   ),
/// );
/// ```
///
/// [authorizeWorkspace] 在用户切换目标工作区与确认导入两个时机调用；返回
/// false（取消或验证失败）时不发生任何写入。
///
/// 安全约束：本页面不显示、不打印密码与文件内容；预览只呈现标题、用户名、
/// 网址与字段差异标记。
class ChromeImportScreen extends StatefulWidget {
  const ChromeImportScreen({
    super.key,
    required this.repository,
    this.initialWorkspaceId = Workspace.defaultId,
    required this.authorizeWorkspace,
  });

  final PasswordRepository repository;
  final String initialWorkspaceId;
  final Future<bool> Function(String workspaceId) authorizeWorkspace;

  @override
  State<ChromeImportScreen> createState() => _ChromeImportScreenState();
}

class _ChromeImportScreenState extends State<ChromeImportScreen> {
  late final ChromeCsvImportService _service =
      ChromeCsvImportService(repository: widget.repository);

  String _workspaceId = '';
  String? _groupId;
  String? _csvContent;
  String? _fileName;
  ChromeImportPreview? _preview;
  ChromeImportCommitResult? _result;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _workspaceId = widget.initialWorkspaceId;
  }

  // ---------------------------------------------------------------------------
  // 交互
  // ---------------------------------------------------------------------------

  void _snack(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  String? _effectiveGroupId() =>
      _groupId == null || _groupId!.isEmpty ? null : _groupId;

  Future<void> _pickFile() async {
    if (_busy) return;
    if (!await widget.authorizeWorkspace(_workspaceId) || !mounted) return;
    setState(() => _busy = true);
    try {
      final FilePickerResult? picked = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: <String>['csv'],
      );
      if (picked == null || picked.files.isEmpty) return;
      final PlatformFile file = picked.files.single;
      String content;
      if (file.bytes != null) {
        content = utf8.decode(file.bytes!, allowMalformed: false);
      } else if (file.path != null) {
        content = utf8.decode(await File(file.path!).readAsBytes(),
            allowMalformed: false);
      } else {
        _snack('无法读取所选文件');
        return;
      }
      if (!mounted) return;
      _csvContent = content;
      _fileName = file.name;
      _rebuildPreview();
    } catch (_) {
      _snack('读取文件失败，请重试');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  void _rebuildPreview() {
    final String? content = _csvContent;
    if (content == null) return;
    final ChromeImportPreview preview = _service.buildPreview(
      csvContent: content,
      workspaceId: _workspaceId,
    );
    if (!preview.parse.isOk) {
      _snack(preview.parse.headerError ?? '无法解析该文件');
      if (_preview != null) setState(() => _preview = null);
      return;
    }
    if (preview.rows.isEmpty && preview.parse.errors.isEmpty) {
      _snack('文件中没有可导入的条目');
      return;
    }
    setState(() => _preview = preview);
  }

  Future<void> _changeWorkspace(String? newId) async {
    if (newId == null || newId == _workspaceId || _busy) return;
    setState(() => _busy = true);
    final bool allowed = await widget.authorizeWorkspace(newId);
    if (!mounted) return;
    setState(() => _busy = false);
    if (!allowed) {
      _snack('未通过工作区验证，保持原工作区');
      return;
    }
    setState(() {
      _workspaceId = newId;
      _groupId = null;
    });
    if (_csvContent != null) {
      _rebuildPreview();
    }
  }

  void _changeGroup(String? newId) {
    if (newId == null) return;
    setState(() => _groupId = newId.isEmpty ? null : newId);
  }

  Future<void> _confirmImport() async {
    final ChromeImportPreview? preview = _preview;
    if (preview == null || _busy) return;
    final ChromeImportPlan plan =
        _service.finalizePlan(preview, groupId: _effectiveGroupId());
    if (plan.errors.isNotEmpty) {
      _snack(plan.errors.first);
      return;
    }
    setState(() => _busy = true);
    final bool allowed = await widget.authorizeWorkspace(_workspaceId);
    if (!mounted) return;
    if (!allowed) {
      setState(() => _busy = false);
      _snack('未通过工作区验证，已取消导入');
      return;
    }
    late final ChromeImportCommitResult result;
    try {
      result = await _service.commit(preview, groupId: _effectiveGroupId());
    } catch (_) {
      if (mounted) {
        setState(() => _busy = false);
        _snack('导入未完成，请重新验证工作区并刷新预览后重试');
      }
      return;
    }
    if (!mounted) return;
    setState(() => _busy = false);
    if (result.stale) {
      _snack('数据已变化，正在刷新预览');
      _rebuildPreview();
      return;
    }
    if (result.errors.isNotEmpty) {
      _snack(result.errors.first);
      return;
    }
    setState(() {
      _result = result;
      _preview = null;
    });
  }

  // ---------------------------------------------------------------------------
  // 视图
  // ---------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final Widget body;
    if (_result != null) {
      body = _resultView();
    } else if (_preview != null) {
      body = _previewView();
    } else {
      body = _introView();
    }
    return Scaffold(
      appBar: AppBar(title: const Text('从 Chrome 导入')),
      body: WorkspaceGuard(repository: widget.repository, workspaceId: _workspaceId, child: Column(
        children: <Widget>[
          if (_busy) const LinearProgressIndicator(minHeight: 2),
          Expanded(child: body),
        ],
      )),
      bottomNavigationBar: _preview == null ? null : _confirmBar(),
    );
  }

  Widget _introView() {
    return ListView(
      padding: const EdgeInsets.all(ThemeConfig.space16),
      children: <Widget>[
        _card(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Row(
                children: <Widget>[
                  Icon(Icons.download_outlined,
                      color: ThemeConfig.primaryColor, size: 20),
                  const SizedBox(width: ThemeConfig.space8),
                  const Text(
                    '第一步：在 Chrome 中导出密码',
                    style: TextStyle(
                      fontSize: ThemeConfig.fontSizeSubtitle,
                      fontWeight: FontWeight.w600,
                      color: ThemeConfig.textColor,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: ThemeConfig.space12),
              const Text(
                '1. 电脑端：打开 Chrome 密码管理器设置\n'
                '（地址栏输入 chrome://password-manager/settings）\n'
                '2. 点击「导出密码」，按提示确认并保存 CSV 文件\n'
                '3. 手机端：Chrome 设置 → 密码管理器 → 导出密码',
                style: TextStyle(
                  fontSize: ThemeConfig.fontSizeBody,
                  color: ThemeConfig.secondaryTextColor,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: ThemeConfig.space12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Icon(Icons.warning_amber_rounded,
                      color: ThemeConfig.warningColor, size: 18),
                  const SizedBox(width: ThemeConfig.space8),
                  const Expanded(
                    child: Text(
                      'CSV 文件以明文保存全部密码，导入完成后请尽快删除该文件。',
                      style: TextStyle(
                        fontSize: ThemeConfig.fontSizeCaption,
                        color: ThemeConfig.warningColor,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: ThemeConfig.space12),
        _card(child: _targetSelectors()),
        const SizedBox(height: ThemeConfig.space24),
        FilledButton.icon(
          onPressed: _busy ? null : _pickFile,
          icon: const Icon(Icons.upload_file_outlined),
          label: const Text('第二步：选择导出的 CSV 文件'),
        ),
      ],
    );
  }

  Widget _previewView() {
    final ChromeImportPreview preview = _preview!;
    final ChromeImportPlan plan =
        _service.finalizePlan(preview, groupId: _effectiveGroupId());
    final Map<int, ChromePlannedWrite> writesByRow = <int, ChromePlannedWrite>{
      for (final ChromePlannedWrite w in plan.writes) w.row.entry.sourceRow: w,
    };

    return ListView(
      padding: const EdgeInsets.all(ThemeConfig.space16),
      children: <Widget>[
        _card(child: _targetSelectors()),
        const SizedBox(height: ThemeConfig.space12),
        _summaryCard(preview),
        if (preview.parse.errors.isNotEmpty) ...<Widget>[
          const SizedBox(height: ThemeConfig.space12),
          _errorsCard(preview.parse.errors),
        ],
        const SizedBox(height: ThemeConfig.space12),
        for (final ChromeImportRow row in preview.rows)
          Padding(
            padding: const EdgeInsets.only(bottom: ThemeConfig.space8),
            child: _rowCard(row, writesByRow[row.entry.sourceRow]),
          ),
        const SizedBox(height: ThemeConfig.space16),
      ],
    );
  }

  Widget _confirmBar() {
    final ChromeImportPreview? preview = _preview;
    if (preview == null) return const SizedBox.shrink();
    final ChromeImportPlan plan =
        _service.finalizePlan(preview, groupId: _effectiveGroupId());
    final bool blocked = plan.errors.isNotEmpty || _busy;
    final int count = plan.writes.length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(
          ThemeConfig.space16,
          ThemeConfig.space8,
          ThemeConfig.space16,
          ThemeConfig.space12,
        ),
        child: FilledButton(
          onPressed: blocked ? null : _confirmImport,
          child: Text(count > 0 ? '确认导入 $count 项' : '没有可导入的项'),
        ),
      ),
    );
  }

  Widget _resultView() {
    final ChromeImportCommitResult r = _result!;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(ThemeConfig.space24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Icon(Icons.check_circle_outline,
                color: ThemeConfig.successColor, size: 56),
            const SizedBox(height: ThemeConfig.space16),
            const Text(
              '导入完成',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: ThemeConfig.fontSizeTitle,
                fontWeight: FontWeight.w600,
                color: ThemeConfig.textColor,
              ),
            ),
            const SizedBox(height: ThemeConfig.space8),
            Text(
              '新增 ${r.added} · 更新 ${r.updated} · 跳过 ${r.skipped}'
              '${r.invalid > 0 ? ' · 无效 ${r.invalid}' : ''}',
              textAlign: TextAlign.center,
              style: const TextStyle(
                fontSize: ThemeConfig.fontSizeBody,
                color: ThemeConfig.secondaryTextColor,
              ),
            ),
            const SizedBox(height: ThemeConfig.space16),
            const Text(
              '导出的 CSV 文件包含明文密码，建议立即删除。',
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: ThemeConfig.fontSizeCaption,
                color: ThemeConfig.warningColor,
              ),
            ),
            const SizedBox(height: ThemeConfig.space24),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop<String>(r.summaryMessage),
              child: const Text('完成'),
            ),
          ],
        ),
      ),
    );
  }

  // ---------------------------------------------------------------------------
  // 组件
  // ---------------------------------------------------------------------------

  Widget _card({required Widget child}) {
    return Container(
      padding: const EdgeInsets.all(ThemeConfig.space16),
      decoration: BoxDecoration(
        color: ThemeConfig.fillColor,
        borderRadius: BorderRadius.circular(ThemeConfig.radiusCard),
      ),
      child: child,
    );
  }

  Widget _targetSelectors() {
    return AnimatedBuilder(
      animation: Listenable.merge(<Listenable>[
        widget.repository.workspacesNotifier,
        widget.repository.groupsNotifier,
      ]),
      builder: (BuildContext context, Widget? _) {
        final List<Workspace> workspaces =
            widget.repository.workspacesNotifier.value;
        final List<ItemGroup> groups = widget.repository.groupsNotifier.value
            .where((ItemGroup g) => g.workspaceId == _workspaceId)
            .toList();
        final bool wsValid =
            workspaces.any((Workspace w) => w.id == _workspaceId);
        final String? groupValue =
            _groupId != null && groups.any((ItemGroup g) => g.id == _groupId)
                ? _groupId
                : '';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            DropdownButtonFormField<String>(
              initialValue: wsValid ? _workspaceId : null,
              decoration: const InputDecoration(labelText: '导入到工作区'),
              items: <DropdownMenuItem<String>>[
                for (final Workspace w in workspaces)
                  DropdownMenuItem<String>(
                    value: w.id,
                    child: Text('${w.icon ?? ''} ${w.name}'.trim()),
                  ),
              ],
              onChanged: _changeWorkspace,
            ),
            const SizedBox(height: ThemeConfig.space12),
            DropdownButtonFormField<String>(
              key: ValueKey<String>('group-$_workspaceId'),
              initialValue: groupValue,
              decoration: const InputDecoration(labelText: '分组（仅新增条目）'),
              items: <DropdownMenuItem<String>>[
                const DropdownMenuItem<String>(
                  value: '',
                  child: Text('未分组'),
                ),
                for (final ItemGroup g in groups)
                  DropdownMenuItem<String>(value: g.id, child: Text(g.name)),
              ],
              onChanged: _changeGroup,
            ),
          ],
        );
      },
    );
  }

  Widget _summaryCard(ChromeImportPreview preview) {
    final ChromeCsvParseResult parse = preview.parse;
    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Expanded(
                child: Text(
                  _fileName ?? 'CSV 文件',
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                    fontSize: ThemeConfig.fontSizeBody,
                    fontWeight: FontWeight.w600,
                    color: ThemeConfig.textColor,
                  ),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.swap_horiz),
                tooltip: '更换文件',
                onPressed: _busy ? null : _pickFile,
              ),
            ],
          ),
          const SizedBox(height: ThemeConfig.space4),
          Wrap(
            spacing: ThemeConfig.space8,
            runSpacing: ThemeConfig.space4,
            children: <Widget>[
              _countChip('待处理 ${preview.rows.length}', ThemeConfig.textColor),
              if (preview.createCount > 0)
                _countChip(
                    '新增 ${preview.createCount}', ThemeConfig.infoColor),
              if (preview.identicalCount > 0)
                _countChip('完全相同 ${preview.identicalCount}',
                    ThemeConfig.successColor),
              if (preview.conflictCount > 0)
                _countChip(
                    '内容不同 ${preview.conflictCount}', ThemeConfig.warningColor),
              if (preview.multiMatchCount > 0)
                _countChip('多条匹配 ${preview.multiMatchCount}',
                    ThemeConfig.dangerColor),
              if (parse.errors.isNotEmpty)
                _countChip('无法解析 ${parse.errors.length}',
                    ThemeConfig.hintTextColor),
            ],
          ),
          if (preview.undecidedCount > 0) ...<Widget>[
            const SizedBox(height: ThemeConfig.space8),
            const Text(
              '存在多条匹配的条目，需逐条明确选择后才能导入。',
              style: TextStyle(
                fontSize: ThemeConfig.fontSizeCaption,
                color: ThemeConfig.dangerColor,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _countChip(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: ThemeConfig.space8,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(ThemeConfig.radiusPill),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: ThemeConfig.fontSizeCaption,
          color: color,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }

  Widget _errorsCard(List<ChromeCsvRowError> errors) {
    return _card(
      child: ExpansionTile(
        initiallyExpanded: false,
        tilePadding: EdgeInsets.zero,
        childrenPadding: EdgeInsets.zero,
        title: Text(
          '${errors.length} 行无法解析（已跳过）',
          style: const TextStyle(
            fontSize: ThemeConfig.fontSizeBody,
            fontWeight: FontWeight.w600,
            color: ThemeConfig.secondaryTextColor,
          ),
        ),
        children: <Widget>[
          for (final ChromeCsvRowError e in errors)
            Padding(
              padding: const EdgeInsets.only(
                top: ThemeConfig.space4,
                bottom: ThemeConfig.space4,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  SizedBox(
                    width: 48,
                    child: Text(
                      '第 ${e.sourceRow} 行',
                      style: const TextStyle(
                        fontSize: ThemeConfig.fontSizeCaption,
                        color: ThemeConfig.hintTextColor,
                      ),
                    ),
                  ),
                  Expanded(
                    child: Text(
                      e.reason,
                      style: const TextStyle(
                        fontSize: ThemeConfig.fontSizeCaption,
                        color: ThemeConfig.secondaryTextColor,
                      ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  Widget _rowCard(ChromeImportRow row, ChromePlannedWrite? write) {
    final ChromeImportKind kind = row.kind;
    final IconData icon;
    final Color color;
    switch (kind) {
      case ChromeImportKind.create:
        icon = Icons.add_circle_outline;
        color = ThemeConfig.infoColor;
      case ChromeImportKind.identical:
        icon = Icons.check_circle_outline;
        color = ThemeConfig.successColor;
      case ChromeImportKind.conflict:
        icon = Icons.warning_amber_rounded;
        color = ThemeConfig.warningColor;
      case ChromeImportKind.multiMatch:
        icon = Icons.error_outline;
        color = ThemeConfig.dangerColor;
    }

    final String host = ChromeCsvImportService.urlHostOf(row.entry.url);
    final String subtitle = row.entry.username.isEmpty
        ? (host.isEmpty ? '无网址' : host)
        : (host.isEmpty ? row.entry.username : '${row.entry.username} · $host');

    return _card(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: <Widget>[
              Icon(icon, color: color, size: 22),
              const SizedBox(width: ThemeConfig.space12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      row.entry.desiredTitle,
                      style: const TextStyle(
                        fontSize: ThemeConfig.fontSizeBody,
                        fontWeight: FontWeight.w600,
                        color: ThemeConfig.textColor,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: const TextStyle(
                        fontSize: ThemeConfig.fontSizeCaption,
                        color: ThemeConfig.secondaryTextColor,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (write != null &&
              write.item.title != row.entry.desiredTitle) ...<Widget>[
            const SizedBox(height: ThemeConfig.space4),
            Text(
              '最终名称：${write.item.title}',
              style: const TextStyle(
                fontSize: ThemeConfig.fontSizeCaption,
                color: ThemeConfig.hintTextColor,
              ),
            ),
          ],
          if (kind == ChromeImportKind.conflict) ...<Widget>[
            const SizedBox(height: ThemeConfig.space8),
            Wrap(
              spacing: ThemeConfig.space8,
              runSpacing: ThemeConfig.space4,
              children: <Widget>[
                for (final String label in _diffLabels(row))
                  _countChip(label, ThemeConfig.secondaryTextColor),
              ],
            ),
          ],
          if (kind == ChromeImportKind.identical) ...<Widget>[
            const SizedBox(height: ThemeConfig.space8),
            Text(
              row.duplicateInFile ? '文件中已有相同记录，将跳过' : '与本地条目完全相同，将跳过',
              style: TextStyle(
                fontSize: ThemeConfig.fontSizeCaption,
                color: ThemeConfig.successColor,
              ),
            ),
          ],
          const SizedBox(height: ThemeConfig.space12),
          _decisionControl(row, kind),
        ],
      ),
    );
  }

  List<String> _diffLabels(ChromeImportRow row) {
    final PasswordItem local = row.matches.single;
    final ChromeCsvEntry e = row.entry;
    final List<String> labels = <String>[];
    if (local.password != e.password) labels.add('密码不同');
    if (local.username.trim() != e.username) labels.add('用户名不同');
    if ((local.notes ?? '').trim() != (e.note ?? '').trim()) {
      labels.add('备注不同');
    }
    if (local.title.trim() != e.desiredTitle) labels.add('名称不同');
    if ((local.url ?? '').trim() != e.url) labels.add('网址写法不同');
    return labels;
  }

  Widget _decisionControl(ChromeImportRow row, ChromeImportKind kind) {
    switch (kind) {
      case ChromeImportKind.create:
        return SegmentedButton<ChromeImportChoice>(
          showSelectedIcon: false,
          segments: const <ButtonSegment<ChromeImportChoice>>[
            ButtonSegment<ChromeImportChoice>(
              value: ChromeImportChoice.addNew,
              label: Text('导入'),
            ),
            ButtonSegment<ChromeImportChoice>(
              value: ChromeImportChoice.skipImport,
              label: Text('跳过'),
            ),
          ],
          selected: <ChromeImportChoice>{row.choice},
          onSelectionChanged: row.choice == ChromeImportChoice.addNew ||
                  row.choice == ChromeImportChoice.skipImport
              ? (Set<ChromeImportChoice> selection) =>
                  setState(() => row.choice = selection.first)
              : null,
        );
      case ChromeImportKind.identical:
        return const SizedBox.shrink();
      case ChromeImportKind.conflict:
        return SegmentedButton<ChromeImportChoice>(
          showSelectedIcon: false,
          segments: const <ButtonSegment<ChromeImportChoice>>[
            ButtonSegment<ChromeImportChoice>(
              value: ChromeImportChoice.keepLocal,
              label: Text('保留本地'),
            ),
            ButtonSegment<ChromeImportChoice>(
              value: ChromeImportChoice.update,
              label: Text('更新'),
            ),
            ButtonSegment<ChromeImportChoice>(
              value: ChromeImportChoice.saveAsNew,
              label: Text('另存'),
            ),
          ],
          selected: <ChromeImportChoice>{row.choice},
          onSelectionChanged: (Set<ChromeImportChoice> selection) =>
              setState(() => row.choice = selection.first),
        );
      case ChromeImportKind.multiMatch:
        return RadioGroup<String>(groupValue: _multiRadioValue(row),
          onChanged: (v) => setState(() => _applyMultiChoice(row, v)),
          child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            const Text(
              '本地存在多条相同网址 + 用户名的条目，请选择要更新哪一条：',
              style: TextStyle(
                fontSize: ThemeConfig.fontSizeCaption,
                color: ThemeConfig.dangerColor,
              ),
            ),
            for (final PasswordItem m in row.matches)
              RadioListTile<String>(
                value: 'update:${m.id}',
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text('更新「${m.title}」'),
              ),
            RadioListTile<String>(
              value: 'keep',
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('全部保留本地，不更新'),
            ),
            RadioListTile<String>(
              value: 'save',
              contentPadding: EdgeInsets.zero,
              dense: true,
              title: const Text('另存为新条目'),
            ),
          ],
        ));
    }
  }

  String? _multiRadioValue(ChromeImportRow row) {
    switch (row.choice) {
      case ChromeImportChoice.update:
        return 'update:${row.updateTargetId}';
      case ChromeImportChoice.keepLocal:
        return 'keep';
      case ChromeImportChoice.saveAsNew:
        return 'save';
      default:
        return null;
    }
  }

  void _applyMultiChoice(ChromeImportRow row, String? value) {
    if (value == null) return;
    if (value.startsWith('update:')) {
      row.choice = ChromeImportChoice.update;
      row.updateTargetId = value.substring('update:'.length);
    } else if (value == 'keep') {
      row.choice = ChromeImportChoice.keepLocal;
      row.updateTargetId = null;
    } else if (value == 'save') {
      row.choice = ChromeImportChoice.saveAsNew;
      row.updateTargetId = null;
    }
  }
}
