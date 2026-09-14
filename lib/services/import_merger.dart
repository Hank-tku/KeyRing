import '../models/password_item.dart';
import 'data_export_service.dart';
import 'device_service.dart';
import 'password_repository.dart';

/// 导入结果汇总。
class ImportSummary {
  const ImportSummary({
    required this.added,
    required this.updated,
    required this.skipped,
    required this.invalid,
    this.deleted = 0,
    this.dropped = 0,
  });

  /// 新增条目数（本地不存在该 id）。
  final int added;

  /// 更新条目数（本地存在且导入项 updatedAt 更新）。
  final int updated;

  /// 跳过条目数（本地存在但导入项 updatedAt 更旧或相同）。
  final int skipped;

  /// 无效条目数（校验未通过或未知工作区被拒收，未进入合并）。
  final int invalid;

  /// 因墓碑（本地已删除且删除时间更晚）被拒绝的条目数。
  final int deleted;

  /// 因工作区策略防御被拒收的条目数（计入 [invalid] 语义）。
  final int dropped;

  int get total => added + updated + skipped + invalid;

  bool get hasChanges => added > 0 || updated > 0;

  @override
  String toString() {
    final List<String> parts = <String>[
      if (added > 0) '新增 $added 条',
      if (updated > 0) '更新 $updated 条',
      if (skipped > 0) '跳过 $skipped 条',
      if (deleted > 0) '已删除 $deleted 条',
      if (dropped > 0) '拒收 $dropped 条',
      if (invalid > 0) '无效 $invalid 条',
    ];
    return parts.isEmpty ? '无变化' : parts.join('，');
  }
}

/// 统一的导入合并器。
///
/// 将「校验 → newer-wins 决策 → 写入仓库」封装为单一入口，供文件导入、
/// 二维码扫描、截图 OCR 三条路径复用，避免在 UI 层重复实现合并逻辑。
///
/// 合并规则（与现有 _importData 一致）：
/// - 按 [PasswordItem.id] 匹配本地条目；
/// - 本地不存在 → 新增；
/// - 导入项 updatedAt 严格晚于本地 → 更新（保留导入项原始时间戳）；
/// - 否则（更旧或相同） → 跳过。
class ImportMerger {
  ImportMerger(this._repository, {String? deviceClass})
    : _deviceClass = deviceClass ?? DeviceService().getDeviceClass();

  final PasswordRepository _repository;
  final String _deviceClass;

  /// v2 文件导入：直接以线格式合并（结构恢复 + 精确字段保留合并 +
  /// 墓碑防复活 + 接收侧防御，全部在 [PasswordRepository.applyIncoming]）。
  Future<ImportSummary> mergeBundle(ParsedImport bundle) async {
    final SyncApplyResult result = await _repository.applyIncoming(
      rawItems: bundle.rawItems,
      rawWorkspaces: bundle.rawWorkspaces,
      rawGroups: bundle.rawGroups,
      localDeviceClass: _deviceClass,
    );
    return ImportSummary(
      added: result.added,
      updated: result.updated,
      skipped: result.skipped,
      invalid: result.dropped,
      deleted: result.deleted,
      dropped: result.dropped,
    );
  }

  /// 合并一批已解析的条目（二维码 / OCR / 纯条目数组来源）。
  ///
  /// [incoming] 应已经过 [ImportValidator] 之外的去重；本方法内部会再按
  /// 仓库现状做 newer-wins 判断。所有写入在单个事务内完成，仅触发一次刷新。
  Future<ImportSummary> merge(List<PasswordItem> incoming) async {
    if (incoming.isEmpty) {
      return const ImportSummary(added: 0, updated: 0, skipped: 0, invalid: 0);
    }

    // 读取当前本地全量，建立 id 索引用于比较。
    final Map<String, PasswordItem> existing = <String, PasswordItem>{
      for (final PasswordItem it in _repository.itemsNotifier.value) it.id: it,
    };

    final List<PasswordItem> toWrite = <PasswordItem>[];
    int added = 0;
    int updated = 0;
    int skipped = 0;

    for (final PasswordItem item in incoming) {
      final PasswordItem? local = existing[item.id];
      if (local == null) {
        toWrite.add(item);
        added++;
      } else if (item.updatedAt.isAfter(local.updatedAt)) {
        // newer-wins：导入项更新则覆盖。
        toWrite.add(item);
        updated++;
      } else {
        // 导入项更旧或时间相同 → 跳过。
        skipped++;
      }
    }

    if (toWrite.isNotEmpty) {
      await _repository.importItems(toWrite);
    }

    return ImportSummary(
      added: added,
      updated: updated,
      skipped: skipped,
      invalid: 0,
    );
  }
}
