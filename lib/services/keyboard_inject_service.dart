import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 桌面端模拟键盘输入服务（1Password 式填充的最后一步）。
///
/// 通过平台通道 `keyring/keyboard` 调用 native 实现：
/// - macOS：CGEvent 逐字符注入（需「辅助功能」权限）
/// - Windows：SendInput Unicode 注入
/// - Linux：xdotool（未安装则返回 false）
///
/// 仅桌面端可用；调用前应检查 [isAvailable]。
class KeyboardInjectService {
  static const MethodChannel _channel = MethodChannel('keyring/keyboard');

  /// 当前平台是否支持模拟输入。
  static bool get isAvailable {
    if (kIsWeb) return false;
    return Platform.isMacOS || Platform.isWindows || Platform.isLinux;
  }

  /// 按「用户名 → Tab → 密码」的顺序注入键盘输入。
  ///
  /// [username] 为空时只输入密码。返回 native 是否成功执行；
  /// 失败常见原因：macOS 未授予辅助功能权限、Linux 无 xdotool。
  static Future<bool> typeCredentials({
    required String username,
    required String password,
  }) async {
    if (!isAvailable) return false;
    try {
      final bool ok = await _channel.invokeMethod<bool>('typeCredentials', {
        'username': username,
        'password': password,
      }) ?? false;
      return ok;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      // 平台未实现（如 Linux 未配置），静默失败。
      return false;
    }
  }
}
