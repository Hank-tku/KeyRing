import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hotkey_manager/hotkey_manager.dart';

import '../services/global_hotkey_service.dart';
import '../services/hotkey_settings_service.dart';
import '../utils/theme_config.dart';

/// 设置页：桌面端全局热键的自定义录制。
///
/// 借鉴 1Password：录制新组合即时生效（占用预检失败会提示并保持原热键），
/// 支持恢复平台默认热键。
class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.hotkeyService});

  final GlobalHotkeyService hotkeyService;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  HotkeyConfig get _config => widget.hotkeyService.config;
  bool _saving = false;

  /// 修饰键本身的物理键：录制器在"只按住修饰键还没按主键"时也会回调，
  /// 这些过渡事件直接忽略，等用户继续按主键。
  /// （PhysicalKeyboardKey 重载了 ==，不能放进 const 集合。）
  static final Set<PhysicalKeyboardKey> _modifierKeys =
      <PhysicalKeyboardKey>{
    PhysicalKeyboardKey.controlLeft,
    PhysicalKeyboardKey.controlRight,
    PhysicalKeyboardKey.shiftLeft,
    PhysicalKeyboardKey.shiftRight,
    PhysicalKeyboardKey.altLeft,
    PhysicalKeyboardKey.altRight,
    PhysicalKeyboardKey.metaLeft,
    PhysicalKeyboardKey.metaRight,
  };

  Future<void> _apply(HotkeyConfig newConfig) async {
    if (_saving) return;
    if (!newConfig.hasValidModifiers) {
      _toast('请至少按住一个修饰键（⇧⌘⌥⌃），再按一个普通按键');
      return;
    }
    final String? reserved = _reservedCombinationError(newConfig);
    if (reserved != null) {
      _toast(reserved);
      return;
    }
    setState(() => _saving = true);
    final HotkeyRegisterStatus status =
        await widget.hotkeyService.rebind(newConfig);
    if (!mounted) return;
    setState(() => _saving = false);
    switch (status) {
      case HotkeyRegisterStatus.ok:
        _toast('热键已更新：${newConfig.describe()}', true);
      case HotkeyRegisterStatus.occupied:
        _toast('注册失败：热键被其它应用占用，已保留原热键');
      case HotkeyRegisterStatus.invalidKey:
        _toast('该组合不能作为全局热键，请用字母/数字/F 功能键等普通按键');
      case HotkeyRegisterStatus.unknown:
        _toast('注册失败，请重试');
    }
  }

  /// 系统级保留组合拦截（注册了也会被系统吃掉或干扰系统行为）。
  String? _reservedCombinationError(HotkeyConfig c) {
    final Set<String> mods = c.modifiers;
    if (Platform.isMacOS) {
      if (c.key == PhysicalKeyboardKey.space &&
          mods.length == 1 &&
          mods.contains('meta')) {
        return '⌘Space 是系统快捷键（Spotlight/输入法切换），请换个组合';
      }
      if (c.key == PhysicalKeyboardKey.tab && mods.contains('meta')) {
        return '⌘Tab 是系统快捷键（应用切换），请换个组合';
      }
    } else if (Platform.isWindows) {
      if (c.key == PhysicalKeyboardKey.keyL &&
          mods.length == 1 &&
          mods.contains('meta')) {
        return 'Win+L 是系统快捷键（锁定电脑），请换个组合';
      }
    }
    return null;
  }

  void _toast(String message, [bool success = false]) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor:
            success ? ThemeConfig.successColor : ThemeConfig.dangerColor,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  String? get _statusError {
    if (widget.hotkeyService.isRegistered) return null;
    return switch (widget.hotkeyService.lastStatus) {
      HotkeyRegisterStatus.occupied => '当前热键注册失败：可能被其它应用占用，请重新录制',
      HotkeyRegisterStatus.invalidKey => '当前热键组合不受支持，请重新录制',
      _ => null,
    };
  }

  @override
  Widget build(BuildContext context) {
    final bool desktopSupported = GlobalHotkeyService.isSupported;

    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(ThemeConfig.space16),
        children: <Widget>[
          const Text(
            '全局快捷键',
            style: TextStyle(
              fontSize: ThemeConfig.fontSizeSubtitle,
              fontWeight: FontWeight.w600,
              color: ThemeConfig.textColor,
            ),
          ),
          const SizedBox(height: ThemeConfig.space4),
          const Text(
            '在任意应用中按下即可唤起 KeyRing 快速填充（需保持 KeyRing 在菜单栏运行）',
            style: TextStyle(
              fontSize: ThemeConfig.fontSizeCaption,
              color: ThemeConfig.secondaryTextColor,
            ),
          ),
          const SizedBox(height: ThemeConfig.space16),
          if (!desktopSupported)
            Container(
              padding: const EdgeInsets.all(ThemeConfig.space12),
              decoration: BoxDecoration(
                color: ThemeConfig.surfaceColor,
                borderRadius: BorderRadius.circular(ThemeConfig.radiusMd),
              ),
              child: const Text(
                '全局快捷键仅支持桌面端（macOS / Windows / Linux）。',
                style: TextStyle(color: ThemeConfig.secondaryTextColor),
              ),
            )
          else ...<Widget>[
            Container(
              padding: const EdgeInsets.all(ThemeConfig.space16),
              decoration: BoxDecoration(
                color: ThemeConfig.fillColor,
                borderRadius: BorderRadius.circular(ThemeConfig.radiusMd),
                border: Border.all(color: ThemeConfig.dividerColor),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Row(
                    children: <Widget>[
                      const Expanded(
                        child: Text(
                          '当前热键',
                          style: TextStyle(
                            fontWeight: FontWeight.w600,
                            color: ThemeConfig.textColor,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: ThemeConfig.primarySoft,
                          borderRadius: BorderRadius.circular(
                            ThemeConfig.radiusSm,
                          ),
                        ),
                        child: Text(
                          _config.describe(),
                          style: const TextStyle(
                            color: ThemeConfig.primaryColor,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (_statusError != null) ...<Widget>[
                    const SizedBox(height: ThemeConfig.space8),
                    Text(
                      _statusError!,
                      style: const TextStyle(
                        fontSize: ThemeConfig.fontSizeCaption,
                        color: ThemeConfig.dangerColor,
                      ),
                    ),
                  ],
                  const SizedBox(height: ThemeConfig.space16),
                  const Text(
                    '点击下方区域并按下新组合键即可录制（单独按 Esc 取消）',
                    style: TextStyle(
                      fontSize: ThemeConfig.fontSizeCaption,
                      color: ThemeConfig.secondaryTextColor,
                    ),
                  ),
                  const SizedBox(height: ThemeConfig.space8),
                  GestureDetector(
                    onTap: () {},
                    child: Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: ThemeConfig.surfaceColor,
                        borderRadius: BorderRadius.circular(
                          ThemeConfig.radiusMd,
                        ),
                        border: Border.all(color: ThemeConfig.inputBorderColor),
                      ),
                      child: _saving
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: ThemeConfig.primaryColor,
                              ),
                            )
                          : HotKeyRecorder(
                              initalHotKey: _toHotKey(_config),
                              onHotKeyRecorded: (HotKey hk) {
                                final PhysicalKeyboardKey key =
                                    hk.key as PhysicalKeyboardKey;
                                // 只按了修饰键本身（录制器的过渡回调）：忽略，
                                // 等用户继续按主键，避免误弹错误提示。
                                if (_modifierKeys.contains(key)) return;
                                // 单独按 Esc = 取消录制，保留原热键。
                                if (key == PhysicalKeyboardKey.escape &&
                                    (hk.modifiers ?? const <HotKeyModifier>[])
                                        .isEmpty) {
                                  return;
                                }
                                // 录制即应用。
                                _apply(_fromHotKey(hk));
                              },
                            ),
                    ),
                  ),
                  const SizedBox(height: ThemeConfig.space12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _saving
                          ? null
                          : () => _apply(HotkeyConfig.platformDefault()),
                      icon: const Icon(Icons.restart_alt, size: 18),
                      label: const Text('恢复默认'),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  HotKey _toHotKey(HotkeyConfig config) {
    return HotKey(
      key: config.key,
      modifiers: <HotKeyModifier>[
        for (final String name in config.modifiers)
          if (HotKeyModifier.values
              .any((HotKeyModifier m) => m.name == name))
            HotKeyModifier.values.firstWhere(
              (HotKeyModifier m) => m.name == name,
            ),
      ],
    );
  }

  HotkeyConfig _fromHotKey(HotKey hotKey) {
    return HotkeyConfig(
      key: hotKey.key as PhysicalKeyboardKey,
      // 只保留可靠修饰键（capsLock/fn 剔除）。
      modifiers: <String>{
        for (final HotKeyModifier m in hotKey.modifiers ?? <HotKeyModifier>[])
          if (HotkeyConfig.supportedModifiers.contains(m.name)) m.name,
      },
    );
  }
}
