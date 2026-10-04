import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// 记录/恢复「热键按下时的前台应用」。
///
/// 1Password 式填充的关键：热键唤起小面板前先记住用户当时所在的 app，
/// 选择密码后自动切回该 app 再模拟键盘输入。
///
/// - macOS：NSWorkspace.frontmostApplication / activate
/// - Windows：GetForegroundWindow / SetForegroundWindow
class ForegroundAppService {
  static const MethodChannel _channel = MethodChannel('keyring/foreground');

  static bool get isSupported {
    if (kIsWeb) return false;
    return Platform.isMacOS || Platform.isWindows;
  }

  /// 在显示快速填充面板**之前**调用：记录当前前台应用。
  ///
  /// 返回是否记录到了有效的填充目标——前台是 KeyRing 自己或平台不支持
  /// 时返回 false，此时不应执行填充（避免把密码打给自己/盲打）。
  static Future<bool> remember() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('remember') ?? false;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }

  /// macOS uses a nonactivating NSPanel; never activate the application.
  static Future<void> showPanel() => _channel.invokeMethod<void>('showPanel');
  static Future<void> hidePanel() => _channel.invokeMethod<void>('hidePanel');
  static Future<void> setPanelAuthenticating(bool value) async {
    if (Platform.isMacOS) {
      await _channel.invokeMethod<void>('panelAuthenticating', value);
    }
  }

  static Future<bool> isTargetActive() async {
    if (!isSupported) return false;
    try {
      return await _channel.invokeMethod<bool>('isTargetActive') ?? false;
    } on PlatformException {
      return false;
    } on MissingPluginException {
      return false;
    }
  }

  /// 填充前调用：把记录的应用带回前台。
  ///
  /// 返回是否成功（失败时调用方应退化为倒计时让用户手动切换）。
  static Future<bool> activate() async {
    if (!isSupported) return false;
    try {
      final bool ok = await _channel.invokeMethod<bool>('activate') ?? false;
      return ok;
    } on MissingPluginException {
      return false;
    } on PlatformException {
      return false;
    }
  }
}
