import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// 应用内快捷键动作类型。
enum AppShortcutAction { openImport, exportData, focusSearch, lockNow, quickFill }

/// 快捷键消息总线。
///
/// main.dart 根节点的 [CallbackShortcuts] 捕获按键后，通过此总线广播动作；
/// HomeScreen 监听并执行对应操作。这样键盘处理与业务 UI 解耦，
/// 避免用 GlobalKey 访问私有 State。
class ShortcutBus extends ChangeNotifier {
  AppShortcutAction? _last;

  /// 最近一次触发的动作（读取后即清除，防止重复消费）。
  AppShortcutAction? consume() {
    final AppShortcutAction? action = _last;
    _last = null;
    return action;
  }

  void fire(AppShortcutAction action) {
    _last = action;
    notifyListeners();
  }
}

/// 平台感知的修饰键：macOS 用 Cmd（meta），其余平台用 Ctrl（control）。
bool get _useMeta =>
    !kIsWeb && defaultTargetPlatform == TargetPlatform.macOS;

SingleActivator _combo(LogicalKeyboardKey key) {
  return _useMeta
      ? SingleActivator(key, meta: true)
      : SingleActivator(key, control: true);
}

/// 应用级快捷键映射。
///
/// - Cmd/Ctrl+I → 打开导入面板
/// - Cmd/Ctrl+E → 导出数据
/// - Cmd/Ctrl+F → 聚焦搜索框
/// - Cmd/Ctrl+L → 立即锁定
Map<ShortcutActivator, Intent> buildAppShortcuts(ShortcutBus bus) {
  void fire(AppShortcutAction action) => bus.fire(action);

  return <ShortcutActivator, Intent>{
    _combo(LogicalKeyboardKey.keyI): _CallbackIntent(() => fire(AppShortcutAction.openImport)),
    _combo(LogicalKeyboardKey.keyE): _CallbackIntent(() => fire(AppShortcutAction.exportData)),
    _combo(LogicalKeyboardKey.keyF): _CallbackIntent(() => fire(AppShortcutAction.focusSearch)),
    _combo(LogicalKeyboardKey.keyL): _CallbackIntent(() => fire(AppShortcutAction.lockNow)),
  };
}

/// 携带回调的简单 Intent，配合 [CallbackAction] 使用。
class _CallbackIntent extends Intent {
  const _CallbackIntent(this.callback);
  final VoidCallback callback;
}

/// 把快捷键映射转换成对应的 Actions 映射。
Map<Type, Action<Intent>> buildAppActions() {
  return <Type, Action<Intent>>{
    _CallbackIntent: CallbackAction<_CallbackIntent>(
      onInvoke: (_CallbackIntent intent) {
        intent.callback();
        return null;
      },
    ),
  };
}
