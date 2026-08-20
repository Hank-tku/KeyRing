import '../models/password_item.dart';

/// 导入条目有效性校验。
///
/// [PasswordItem.fromMap] 是防御性的（缺字段给默认值、不抛异常），
/// 因此解析阶段不会因坏数据中断。但「空 title + 空 password」这类条目
/// 对用户无意义，应在合并前剔除并计数。
class ImportValidator {
  const ImportValidator();

  /// 单条是否有效：title 与 password 至少一个非空（去首尾空白后）。
  bool isValid(PasswordItem item) {
    final bool hasTitle = item.title.trim().isNotEmpty;
    final bool hasPassword = item.password.trim().isNotEmpty;
    return hasTitle || hasPassword;
  }

  /// 过滤一批条目，返回 (有效列表, 无效数量)。
  ({List<PasswordItem> valid, int invalid}) filter(
    Iterable<PasswordItem> items,
  ) {
    final List<PasswordItem> valid = <PasswordItem>[];
    int invalid = 0;
    for (final PasswordItem item in items) {
      if (isValid(item)) {
        valid.add(item);
      } else {
        invalid++;
      }
    }
    return (valid: valid, invalid: invalid);
  }
}
