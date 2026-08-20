import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/services.dart';

import '../models/password_item.dart';
import '../services/foreground_app_service.dart';
import '../services/keyboard_inject_service.dart';
import '../services/password_repository.dart';

/// 快速填充小窗的宿主（运行在主窗口 isolate）。
///
/// 职责：
/// - 创建/显示/隐藏子窗口（toggle）；呼起时先激活本应用抢键盘焦点，
///   并把面板定位到鼠标光标处
/// - 通道架构（desktop_multi_window 0.3.0，unidirectional 模式下
///   一条通道只允许一个引擎注册 handler）：
///   - controller 通道 `mixin.one/window_controller/$windowId`：宿主注册
///     handler，接收子窗口的 requestItems / fill / panelHidden
///   - 命令通道 `keyring.quickfill/cmd`：子窗口注册 handler，
///     宿主推送 refresh / feedback / hide
/// - 呼起时记住前台应用（填充目标），每次呼起都刷新条目
/// - 填充失败时把原因带回面板重新显示（用户在别的应用里也能看到）
///
/// 安全：密码不经过子窗口；注入由主窗口执行后立即丢弃引用；
/// 前台是 KeyRing 自己（或记不到目标）时直接取消填充，绝不盲打。
class QuickFillHost {
  QuickFillHost({required this.repository, required this.onFeedback});

  final PasswordRepository repository;

  /// 填充结果反馈（成功/失败提示，由宿主侧记录日志）。
  final void Function(String message, bool success) onFeedback;

  /// 宿主 → 面板命令通道（handler 在子窗口引擎侧注册）。
  static const WindowMethodChannel _cmdChannel = WindowMethodChannel(
    'keyring.quickfill/cmd',
    mode: ChannelMode.unidirectional,
  );

  WindowController? _window;
  bool _visible = false;
  bool _filling = false;

  /// 本次呼起是否记录到了有效的填充目标（非 KeyRing 自身）。
  bool _hasTarget = false;

  bool get isVisible => _visible;

  /// 热键/托盘入口：切换小窗显隐。
  ///
  /// 显示前先记住当前前台应用（填充后切回）。
  Future<void> toggle() async {
    if (_visible) {
      await hide();
      return;
    }
    await show();
  }

  Future<void> show() async {
    _hasTarget = await ForegroundAppService.remember();

    WindowController? window = _window;
    final bool firstLaunch = window == null;
    if (window == null) {
      window = await WindowController.create(
        const WindowConfiguration(
          arguments: 'quick_fill',
          hiddenAtLaunch: true,
        ),
      );
      _window = window;
      await window.setWindowMethodHandler(_onWindowCall);
    }
    // 先激活本应用再显示面板：后台 app 的窗口无法直接获得键盘焦点。
    await ForegroundAppService.activateSelf();
    // 面板中心对齐到鼠标光标（每次呼起都重新定位，夹在屏幕可视区内）。
    await ForegroundAppService.centerPanelAtMouse();
    await window.show();
    _visible = true;
    // 首次创建时子引擎 _boot 会自己拉取；之后每次呼起都刷新，
    // 保证主窗口的增删改立即反映到面板。
    if (!firstLaunch) {
      unawaited(_pushToPanel('refresh'));
    }
  }

  Future<void> hide() async {
    await _window?.hide();
    _visible = false;
  }

  Future<void> dispose() async {
    // 0.3.0 没有 close API：隐藏即可，进程退出时一并销毁。
    await _window?.hide();
    _visible = false;
  }

  Future<dynamic> _onWindowCall(MethodCall call) async {
    switch (call.method) {
      case 'requestItems':
        // 脱敏：不含密码。按既有序（收藏优先、更新时间倒序）。
        final List<Map<String, String>> payload = <Map<String, String>>[
          for (final PasswordItem it in repository.itemsNotifier.value)
            <String, String>{
              'id': it.id,
              'title': it.title,
              'username': it.username,
              'url': it.url ?? '',
            },
        ];
        return jsonEncode(payload);
      case 'fill':
        final String? id = call.arguments as String?;
        if (id != null) {
          // 不阻塞子窗口：填充要等切换应用+注入（最长 2 秒+），
          // 面板应立即隐藏，失败时再通过 feedback 带回。
          unawaited(_fill(id));
        }
        return null;
      case 'panelHidden':
        // 面板自己隐藏（Esc/失焦/选中后）：同步显隐状态，
        // 下次热键才能正确 toggle。
        _visible = false;
        return null;
      default:
        return null;
    }
  }

  Future<void> _pushToPanel(String method, [dynamic arguments]) async {
    try {
      await _cmdChannel.invokeMethod<dynamic>(method, arguments);
    } catch (_) {
      // 子引擎尚未就绪/已关闭：忽略。
    }
  }

  /// 填充失败时把错误带回面板：重新显示并提示原因（面板是最自然的
  /// 反馈面，用户按下热键的地方），不再静默吞掉。
  Future<void> _notifyPanelError(String message) async {
    _visible = true;
    await ForegroundAppService.activateSelf();
    await _window?.show();
    unawaited(
      _pushToPanel('feedback', <String, dynamic>{'message': message, 'ok': false}),
    );
  }

  Future<void> _fill(String id) async {
    if (_filling) return;
    _filling = true;
    try {
      final PasswordItem? item =
          await repository.getByIdAsync(id);
      if (item == null) {
        onFeedback('条目不存在', false);
        await _notifyPanelError('条目不存在，可能刚被删除');
        return;
      }
      if (!_hasTarget) {
        onFeedback('填充取消：没有可用的目标应用', false);
        await _notifyPanelError('无法确定填充目标：请在目标应用里按热键唤起后再试');
        return;
      }

      // 切回热键按下时的应用；失败则给用户手动切换的时间。
      final bool switched = await ForegroundAppService.activate();
      if (!switched) {
        await Future<void>.delayed(const Duration(milliseconds: 1800));
      } else {
        // 等目标应用接住焦点。
        await Future<void>.delayed(const Duration(milliseconds: 450));
      }

      final bool ok = await KeyboardInjectService.typeCredentials(
        username: item.username,
        password: item.password,
      );
      onFeedback(
        ok ? '已填充「${item.title}」' : '填充失败：请检查辅助功能权限',
        ok,
      );
      if (!ok) {
        await _notifyPanelError(
          Platform.isMacOS
              ? '填充失败：请在 系统设置 → 隐私与安全性 → 辅助功能 中授权 KeyRing'
              : '填充失败：模拟键盘输入不可用',
        );
      }
    } finally {
      _filling = false;
    }
  }
}
