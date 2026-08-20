import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:uni_platform/uni_platform.dart';

import 'hotkey_settings_service.dart';

/// 全局热键占用预检（原生 `keyring/hotkeycheck` 通道）。
///
/// hotkey_manager 的 register 在 macOS/Windows 上都忽略底层注册结果
/// （RegisterEventHotKey / RegisterHotKey 的返回值被吞掉），热键被其它
/// 应用占用时依然返回成功——真正的冲突检测必须自己做：
/// - macOS：Carbon RegisterEventHotKey 试注册（系统级排他）后立即注销
/// - Windows：RegisterHotKey 试注册后立即注销
/// - Linux/其余平台：无实现，返回 null（不可探测，由注册流程兜底）
class HotkeyProbe {
  const HotkeyProbe._();

  static const MethodChannel _channel = MethodChannel('keyring/hotkeycheck');

  /// 该组合当前是否可注册。
  ///
  /// 返回 null 表示平台不支持探测或按键无法映射，调用方按"可用"处理，
  /// 由后续注册流程做最终校验。
  static Future<bool?> isAvailable(HotkeyConfig config) async {
    if (kIsWeb) return null;
    if (!Platform.isMacOS && !Platform.isWindows) return null;
    // 与 hotkey_manager 相同的映射：PhysicalKeyboardKey → 平台虚拟键码。
    // 映射不出来的键（媒体键等）在原生层会被强解包崩溃，这里提前挡下。
    final int? keyCode = config.key.keyCode;
    if (keyCode == null) return null;
    try {
      return await _channel.invokeMethod<bool>('isAvailable', <String, dynamic>{
        'keyCode': keyCode,
        'modifiers': config.modifiers.toList(),
      });
    } on MissingPluginException {
      return null;
    } on PlatformException {
      return null;
    }
  }
}
