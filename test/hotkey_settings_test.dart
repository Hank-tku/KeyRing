import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:key_ring/services/app_lock_state.dart';
import 'package:key_ring/services/hotkey_settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('HotkeyConfig', () {
    test('toJson/fromJson 往返保留键与修饰键', () {
      final HotkeyConfig config = HotkeyConfig(
        key: PhysicalKeyboardKey.keyA,
        modifiers: const <String>{'meta', 'shift'},
      );
      final HotkeyConfig? restored =
          HotkeyConfig.fromJson(jsonDecode(jsonEncode(config.toJson()))
              as Map<String, dynamic>);

      expect(restored, isNotNull);
      expect(restored!.key, PhysicalKeyboardKey.keyA);
      expect(restored.modifiers, <String>{'meta', 'shift'});
    });

    test('fromJson 拒绝未知键码 / 非法结构', () {
      expect(HotkeyConfig.fromJson(<String, dynamic>{'keyId': 999999999}), isNull);
      expect(
        HotkeyConfig.fromJson(<String, dynamic>{
          'keyId': PhysicalKeyboardKey.space.usbHidUsage,
          'modifiers': 'not-a-list',
        }),
        isNull,
      );
    });

    test('hasValidModifiers 剔除 capsLock/fn 后仍有可靠修饰键才算有效', () {
      expect(
        const HotkeyConfig(
          key: PhysicalKeyboardKey.space,
          modifiers: <String>{'meta', 'shift'},
        ).hasValidModifiers,
        isTrue,
      );
      // capsLock/fn 不可靠：单独出现视为无效。
      expect(
        const HotkeyConfig(
          key: PhysicalKeyboardKey.space,
          modifiers: <String>{'capsLock'},
        ).hasValidModifiers,
        isFalse,
      );
      // 混入可靠修饰键则整体可用。
      expect(
        const HotkeyConfig(
          key: PhysicalKeyboardKey.space,
          modifiers: <String>{'fn', 'control'},
        ).hasValidModifiers,
        isTrue,
      );
    });

    test('describe 按平台输出可读组合', () {
      const HotkeyConfig config = HotkeyConfig(
        key: PhysicalKeyboardKey.space,
        modifiers: <String>{'meta', 'shift'},
      );
      // 测试宿主为 macOS；其它平台符号不同，仅断言包含键名。
      final String text = config.describe();
      expect(text.contains('Space'), isTrue);
      expect(text, isNot(contains('meta')));
      expect(text, isNot(contains('shift')));
    });
  });

  group('HotkeySettingsService.load', () {
    test('损坏/无修饰键的持久化配置回退平台默认', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'global_hotkey_config': 'not-json{{{',
      });
      final HotkeyConfig config = await HotkeySettingsService().load();
      expect(
        config.modifiers,
        HotkeyConfig.platformDefault().modifiers,
      );

      // 无有效修饰键的配置也回退。
      SharedPreferences.setMockInitialValues(<String, Object>{
        'global_hotkey_config': jsonEncode(<String, dynamic>{
          'keyId': PhysicalKeyboardKey.space.usbHidUsage,
          'modifiers': <String>['capsLock'],
        }),
      });
      final HotkeyConfig config2 = await HotkeySettingsService().load();
      expect(config2.hasValidModifiers, isTrue);
    });

    test('正常配置原样读回', () async {
      SharedPreferences.setMockInitialValues(<String, Object>{
        'global_hotkey_config': jsonEncode(<String, dynamic>{
          'keyId': PhysicalKeyboardKey.keyJ.usbHidUsage,
          'modifiers': <String>['control', 'alt'],
        }),
      });
      final HotkeyConfig config = await HotkeySettingsService().load();
      expect(config.key, PhysicalKeyboardKey.keyJ);
      expect(config.modifiers, <String>{'control', 'alt'});
    });
  });

  group('AppLockState', () {
    test('初始锁定，标记后可切换', () {
      AppLockState.markUnlocked();
      expect(AppLockState.isLocked, isFalse);
      AppLockState.markLocked();
      expect(AppLockState.isLocked, isTrue);
      // 恢复默认，避免影响其它用例。
      AppLockState.markUnlocked();
      AppLockState.markLocked();
    });
  });
}
