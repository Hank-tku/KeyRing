import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hotkey_manager/hotkey_manager.dart';
import 'package:uni_platform/uni_platform.dart';

import 'hotkey_probe_service.dart';
import 'hotkey_settings_service.dart';

/// 一次注册/重绑的结果。
enum HotkeyRegisterStatus {
  /// 注册成功。
  ok,

  /// 热键被其它应用占用（原生探测或注册失败）。
  occupied,

  /// 组合不受支持（无可靠修饰键、按键无法映射为平台键码如媒体键）。
  invalidKey,

  /// 未知/尚未注册。
  unknown,
}

/// 桌面端全局热键服务（系统级，app 常驻菜单栏时不随窗口关闭失效）。
///
/// - 热键来自用户配置（[HotkeySettingsService]），支持运行中重绑。
/// - hotkey_manager 本身不上报注册失败（原生返回值被吞），所以注册前
///   先用 [HotkeyProbe] 做原生占用预检；[lastStatus] 暴露给设置页展示。
/// - 触发时纯回调（是否弹小窗/主窗由调用方决定）。
/// - 移动端/Web 上全部 no-op。
class GlobalHotkeyService {
  GlobalHotkeyService({HotkeySettingsService? settingsService})
      : _settings = settingsService ?? HotkeySettingsService();

  final HotkeySettingsService _settings;

  HotKey? _hotKey;
  HotkeyConfig _config = HotkeyConfig.platformDefault();
  VoidCallback? _onTriggered;
  HotkeyRegisterStatus _lastStatus = HotkeyRegisterStatus.unknown;

  /// 热键是否已注册成功。
  bool get isRegistered => _hotKey != null;

  /// 当前生效的配置（含默认值）。
  HotkeyConfig get config => _config;

  /// 最近一次注册的结果（设置页据此提示"被占用/不受支持"）。
  HotkeyRegisterStatus get lastStatus => _lastStatus;

  /// 当前平台是否支持全局热键。
  static bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  }

  /// 注册全局热键（从持久化配置读取）。
  ///
  /// 失败不上抛：应用照常使用，失败原因记录在 [lastStatus] 供设置页展示。
  Future<void> init({required VoidCallback onTriggered}) async {
    if (!isSupported) return;
    _onTriggered = onTriggered;
    _config = await _settings.load();
    _lastStatus = await _register();
    debugPrint('GlobalHotkeyService.init: key=${_config.key.debugName} '
        'modifiers=${_config.modifiers.toList()} status=$_lastStatus');
  }

  /// 用户在设置里改了热键后调用：更新配置、持久化并重新注册。
  ///
  /// 先做占用预检，被占用时**不动现有热键**直接返回；注册失败则回滚
  /// 到旧配置并尽力恢复旧热键。
  Future<HotkeyRegisterStatus> rebind(HotkeyConfig newConfig) async {
    if (!isSupported || _onTriggered == null) {
      return HotkeyRegisterStatus.unknown;
    }

    // 与当前已注册的组合一致：无需重绑（预检会误判成"占用自己"）。
    if (_hotKey != null && _sameConfig(newConfig, _config)) {
      _lastStatus = HotkeyRegisterStatus.ok;
      return HotkeyRegisterStatus.ok;
    }

    final bool? available = await HotkeyProbe.isAvailable(newConfig);
    if (available == false) {
      _lastStatus = HotkeyRegisterStatus.occupied;
      return HotkeyRegisterStatus.occupied;
    }

    final HotKey? old = _hotKey;
    final HotkeyConfig previous = _config;

    _config = newConfig;
    _hotKey = null;
    try {
      if (old != null) {
        await HotKeyManager.instance.unregister(old);
      }
    } catch (_) {
      // 旧热键注销失败不阻断新注册。
    }

    if (await _register() == HotkeyRegisterStatus.ok) {
      await _settings.save(newConfig);
      return HotkeyRegisterStatus.ok;
    }

    // 注册失败回滚到旧配置（不持久化新值），并尽力恢复旧热键。
    final HotkeyRegisterStatus failure = _lastStatus;
    _config = previous;
    await _register();
    return failure;
  }

  Future<HotkeyRegisterStatus> _register() async {
    final VoidCallback? onTriggered = _onTriggered;
    if (onTriggered == null) {
      return _lastStatus = HotkeyRegisterStatus.invalidKey;
    }

    final List<HotKeyModifier> modifiers = <HotKeyModifier>[
      for (final String name in _config.modifiers)
        if (HotkeyConfig.supportedModifiers.contains(name))
          HotKeyModifier.values.firstWhere(
            (HotKeyModifier m) => m.name == name,
          ),
    ];
    if (modifiers.isEmpty) {
      return _lastStatus = HotkeyRegisterStatus.invalidKey;
    }

    // 媒体键等无法映射为平台键码：原生侧会强解包崩溃，这里必须挡下。
    if (_config.key.keyCode == null) {
      return _lastStatus = HotkeyRegisterStatus.invalidKey;
    }

    final HotKey hotKey = HotKey(
      key: _config.key,
      modifiers: modifiers,
    );

    try {
      await HotKeyManager.instance.register(
        hotKey,
        keyDownHandler: (HotKey _) async {
          // 直接回调：是否弹主窗口/小窗由调用方决定（QuickFillHost）。
          onTriggered();
        },
      );
      _hotKey = hotKey;
      return _lastStatus = HotkeyRegisterStatus.ok;
    } on Exception catch (e) {
      // 热键被其它应用占用：保持未注册状态。
      debugPrint('GlobalHotkeyService register failed: $e');
      _hotKey = null;
      return _lastStatus = HotkeyRegisterStatus.occupied;
    }
  }

  bool _sameConfig(HotkeyConfig a, HotkeyConfig b) {
    return a.key == b.key &&
        Set<String>.of(
          a.modifiers.where(HotkeyConfig.supportedModifiers.contains),
        ).containsAll(b.modifiers) &&
        Set<String>.of(
          b.modifiers.where(HotkeyConfig.supportedModifiers.contains),
        ).containsAll(a.modifiers);
  }

  Future<void> dispose() async {
    if (_hotKey != null) {
      await HotKeyManager.instance.unregister(_hotKey!);
      _hotKey = null;
    }
  }
}
