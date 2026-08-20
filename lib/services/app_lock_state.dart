import 'package:flutter/foundation.dart';

/// 应用锁定状态（跨 isolate 内共享的进程内状态，主窗口 isolate 使用）。
///
/// 锁定页/主窗口负责标记；全局热键、快速填充等入口在触发前检查，
/// 确保锁定状态下任何入口都不泄漏条目列表、更不会填充密码。
class AppLockState {
  AppLockState._();

  static final ValueNotifier<bool> _locked = ValueNotifier<bool>(true);

  /// 当前是否处于锁定状态（应用启动即锁定）。
  static bool get isLocked => _locked.value;

  /// 供 UI 监听变化。
  static Listenable get listenable => _locked;

  static void markLocked() => _locked.value = true;

  static void markUnlocked() => _locked.value = false;
}
