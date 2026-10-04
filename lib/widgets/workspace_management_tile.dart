import 'package:flutter/material.dart';

import '../models/workspace.dart';
import '../utils/theme_config.dart';
import 'shared/app_card.dart';

/// 右侧动作按钮的固定槽位尺寸（访问 / 编辑 / 删除 / 更多 / 拖拽统一规格）。
const double _kSlotSize = 44;

/// 宽窄布局阈值：超过该宽度时动作平铺，否则编辑/删除并入更多菜单。
const double _kWideThreshold = 600;

/// 工作区管理页的工作区卡片。
///
/// - 展示图标、名称、同步策略徽章、条目数量；
/// - 右侧动作全部为 44x44 槽位，垂直居中对齐、互不重叠；
/// - 拖拽用 [ReorderableDragStartListener]（父列表需设
///   `buildDefaultDragHandles: false`），与按钮保持独立；
/// - 宽屏：访问验证 / 编辑 / 删除 / 拖拽平铺；
///   窄屏：保留访问验证、更多菜单（编辑/删除）与独立拖拽；
/// - 不固定整体高度，内容（名称 / 徽章）随文本缩放换行或截断。
class WorkspaceManagementTile extends StatelessWidget {
  const WorkspaceManagementTile({
    super.key,
    required this.workspace,
    required this.itemCount,
    required this.isProtected,
    required this.index,
    required this.onEdit,
    required this.onDelete,
    required this.onConfigureAccess,
  });

  final Workspace workspace;
  final int itemCount;

  /// 是否已配置本机访问密码（决定访问按钮的锁图标状态）。
  final bool isProtected;

  /// 在父 ReorderableListView 中的下标（供拖拽手柄使用）。
  final int index;

  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onConfigureAccess;

  static const Map<SyncPolicy, String> _policyLabels = <SyncPolicy, String>{
    SyncPolicy.full: '全设备同步',
    SyncPolicy.mobileOnly: '仅移动端',
    SyncPolicy.localOnly: '仅本机',
  };

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (BuildContext context, BoxConstraints constraints) {
        final bool wide = constraints.maxWidth >= _kWideThreshold;
        return AppCard(
          padding: const EdgeInsets.symmetric(
            horizontal: ThemeConfig.space12,
            vertical: ThemeConfig.space8,
          ),
          child: Row(
            children: <Widget>[
              _buildLeadingIcon(),
              const SizedBox(width: ThemeConfig.space12),
              Expanded(child: _buildInfo()),
              const SizedBox(width: ThemeConfig.space8),
              if (wide) _buildWideActions() else _buildCompactActions(context),
            ],
          ),
        );
      },
    );
  }

  Widget _buildLeadingIcon() {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: ThemeConfig.primarySoft,
        borderRadius: BorderRadius.circular(ThemeConfig.radiusMd),
      ),
      child: Text(
        workspace.icon ?? Workspace.defaultIcon,
        style: const TextStyle(fontSize: 20),
      ),
    );
  }

  Widget _buildInfo() {
    final Color badgeColor = switch (workspace.syncPolicy) {
      SyncPolicy.full => ThemeConfig.successColor,
      SyncPolicy.mobileOnly => ThemeConfig.warningColor,
      SyncPolicy.localOnly => ThemeConfig.dangerColor,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        Text(
          workspace.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(
            color: ThemeConfig.textColor,
            fontSize: ThemeConfig.fontSizeSubtitle,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: ThemeConfig.space4),
        // Wrap：窄屏 / 大字体时徽章与数量换行而非溢出。
        Wrap(
          spacing: ThemeConfig.space8,
          runSpacing: ThemeConfig.space4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: <Widget>[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: badgeColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(ThemeConfig.radiusPill),
                border: Border.all(color: badgeColor.withValues(alpha: 0.4)),
              ),
              child: Text(
                _policyLabels[workspace.syncPolicy] ?? '',
                style: TextStyle(
                  color: badgeColor,
                  fontSize: ThemeConfig.fontSizeCaption,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
            if (isProtected)
              const Icon(
                Icons.lock_outline,
                size: 13,
                color: ThemeConfig.hintTextColor,
              ),
            Text(
              '$itemCount 项',
              style: const TextStyle(
                color: ThemeConfig.hintTextColor,
                fontSize: ThemeConfig.fontSizeCaption,
              ),
            ),
          ],
        ),
      ],
    );
  }

  /// 宽屏：动作明确分离，全部平铺 + 独立拖拽手柄。
  Widget _buildWideActions() {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _buildAccessSlot(),
        _ActionSlot(
          tooltip: '编辑',
          icon: Icons.edit_outlined,
          color: ThemeConfig.secondaryTextColor,
          onPressed: onEdit,
        ),
        _ActionSlot(
          tooltip: '删除',
          icon: Icons.delete_outline,
          color: ThemeConfig.dangerColor,
          onPressed: onDelete,
        ),
        _buildDragHandle(),
      ],
    );
  }

  /// 窄屏：保留访问验证与独立拖拽，编辑/删除合并到更多菜单。
  Widget _buildCompactActions(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        _buildAccessSlot(),
        _ActionSlot(
          tooltip: '更多',
          icon: Icons.more_vert,
          color: ThemeConfig.secondaryTextColor,
          onPressed: () => _showMoreMenu(context),
        ),
        _buildDragHandle(),
      ],
    );
  }

  Widget _buildAccessSlot() {
    return _ActionSlot(
      tooltip: '访问验证',
      icon: isProtected ? Icons.lock : Icons.lock_open,
      color: isProtected
          ? ThemeConfig.primaryColor
          : ThemeConfig.secondaryTextColor,
      onPressed: onConfigureAccess,
    );
  }

  /// 独立拖拽手柄（与动作按钮同规格、不重叠）。
  /// 父列表需要 `buildDefaultDragHandles: false`。
  Widget _buildDragHandle() {
    return ReorderableDragStartListener(
      index: index,
      child: SizedBox(
        width: _kSlotSize,
        height: _kSlotSize,
        child: IconButton(
          onPressed: () {},
          icon: const Icon(Icons.drag_handle),
          iconSize: 22,
          color: ThemeConfig.secondaryTextColor,
          tooltip: '拖动排序',
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints(
            minWidth: _kSlotSize,
            minHeight: _kSlotSize,
          ),
        ),
      ),
    );
  }

  Future<void> _showMoreMenu(BuildContext context) async {
    final String? action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (BuildContext sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: <Widget>[
            ListTile(
              leading: const Icon(Icons.edit_outlined),
              title: const Text('编辑'),
              onTap: () => Navigator.of(sheetContext).pop('edit'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('删除'),
              textColor: ThemeConfig.dangerColor,
              iconColor: ThemeConfig.dangerColor,
              onTap: () => Navigator.of(sheetContext).pop('delete'),
            ),
          ],
        ),
      ),
    );
    if (action == 'edit') {
      onEdit();
    } else if (action == 'delete') {
      onDelete();
    }
  }
}

/// 固定 44x44 的动作按钮槽位：保证右侧各动作对齐且互不重叠。
class _ActionSlot extends StatelessWidget {
  const _ActionSlot({
    required this.tooltip,
    required this.icon,
    required this.color,
    required this.onPressed,
  });

  final String tooltip;
  final IconData icon;
  final Color color;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _kSlotSize,
      height: _kSlotSize,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon),
        iconSize: 20,
        color: color,
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
