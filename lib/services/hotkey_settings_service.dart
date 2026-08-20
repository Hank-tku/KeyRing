import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// 全局热键的用户配置（可自定义）。
///
/// 持久化为 JSON：`{"modifiers":["meta","shift"],"keyId":44}`
/// 缺省时按平台给默认值（macOS: Cmd+Shift+Space，其余: Ctrl+Shift+Space）。
class HotkeyConfig {
  const HotkeyConfig({
    required this.key,
    required this.modifiers,
  });

  /// 可靠、可跨平台注册的修饰键（capsLock/fn 在原生层不可控，不收）。
  static const Set<String> supportedModifiers = <String>{
    'meta',
    'control',
    'shift',
    'alt',
  };

  /// 热键主键（物理键，跨键盘布局稳定）。
  final PhysicalKeyboardKey key;

  /// 修饰键集合（来自 hotkey_manager 的 HotKeyModifier.name）。
  final Set<String> modifiers;

  /// 剔除不支持的修饰键后是否仍可用（至少一个可靠修饰键）。
  bool get hasValidModifiers =>
      modifiers.any(supportedModifiers.contains);

  /// 平台默认热键。
  factory HotkeyConfig.platformDefault() {
    final bool mac =
        !kIsWeb && Platform.isMacOS;
    return HotkeyConfig(
      key: PhysicalKeyboardKey.space,
      modifiers: <String>{
        mac ? 'meta' : 'control',
        'shift',
      },
    );
  }

  Map<String, dynamic> toJson() => <String, dynamic>{
        'keyId': key.usbHidUsage,
        'modifiers': modifiers.toList(),
      };

  static HotkeyConfig? fromJson(Map<String, dynamic> json) {
    final dynamic keyId = json['keyId'];
    if (keyId is! int) return null;
    final PhysicalKeyboardKey? key =
        PhysicalKeyboardKey.findKeyByCode(keyId);
    if (key == null) return null;
    final dynamic mods = json['modifiers'];
    if (mods is! List) return null;
    return HotkeyConfig(
      key: key,
      modifiers: <String>{
        for (final dynamic m in mods)
          if (m is String) m,
      },
    );
  }

  /// 人类可读描述，如 "⇧⌘Space" / "Ctrl+Shift+Space"。
  String describe() {
    final bool mac = !kIsWeb && Platform.isMacOS;
    final Map<String, String> symbols = <String, String>{
      'meta': mac ? '⌘' : 'Win',
      'control': mac ? '⌃' : 'Ctrl',
      'shift': mac ? '⇧' : 'Shift',
      'alt': mac ? '⌥' : 'Alt',
    };
    final List<String> parts = <String>[
      for (final String m in modifiers)
        symbols[m] ?? m,
    ];
    parts.add(key.debugName ?? 'Key');
    return parts.join(mac ? '' : '+');
  }
}

/// 全局热键配置的读写（shared_preferences）。
class HotkeySettingsService {
  static const String _prefKey = 'global_hotkey_config';

  Future<HotkeyConfig> load() async {
    try {
      final SharedPreferences prefs = await SharedPreferences.getInstance();
      final String? raw = prefs.getString(_prefKey);
      if (raw != null) {
        final dynamic decoded = jsonDecode(raw);
        if (decoded is Map<String, dynamic>) {
          final HotkeyConfig? config = HotkeyConfig.fromJson(decoded);
          // 损坏/手工改坏的配置（键映射不出来、没有可靠修饰键）回退默认。
          if (config != null && config.hasValidModifiers) {
            return config;
          }
        }
      }
    } catch (_) {
      // 损坏的配置回退默认。
    }
    return HotkeyConfig.platformDefault();
  }

  Future<void> save(HotkeyConfig config) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefKey, jsonEncode(config.toJson()));
  }
}
