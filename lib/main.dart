import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';

import 'quick_fill/quick_fill_host.dart';
import 'quick_fill/window_entry.dart';
import 'screens/home_screen.dart';
import 'screens/lock_screen.dart';
import 'screens/settings_screen.dart';
import 'services/app_lock_state.dart';
import 'services/global_hotkey_service.dart';
import 'services/migration_service.dart';
import 'services/password_repository.dart';
import 'utils/app_shortcuts.dart';
import 'utils/theme_config.dart';

Future<void> main(List<String> args) async {
  // desktop_multi_window 子窗口入口：独立 isolate，只跑快速填充面板。
  if (args.isNotEmpty && args.first == 'multi_window') {
    await runQuickFillWindow();
    return;
  }

  WidgetsFlutterBinding.ensureInitialized();

  // Initialize sqflite for desktop platforms
  if (!kIsWeb) {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    // 桌面端初始化窗口管理（全局热键唤起、关闭隐藏到菜单栏需要）。
    if (Platform.isMacOS || Platform.isWindows || Platform.isLinux) {
      await windowManager.ensureInitialized();
    }
  }

  final PasswordRepository repository = PasswordRepository();

  await repository.init();
  await MigrationService(repository: repository).prepareCompatibility();
  runApp(KeyRingApp(repository: repository));
}

class KeyRingApp extends StatefulWidget {
  const KeyRingApp({super.key, required this.repository});

  final PasswordRepository repository;

  @override
  State<KeyRingApp> createState() => _KeyRingAppState();
}

/// 桌面常驻模式（借鉴 1Password）：
/// - 菜单栏托盘常驻，关闭主窗口只是隐藏，不退出进程
/// - 系统级全局热键在任意应用中唤起「快速填充小面板」（独立窗口）
/// - 小面板选择密码后自动切回原应用并模拟键盘输入
class _KeyRingAppState extends State<KeyRingApp>
    with WindowListener, TrayListener {
  bool _unlocked = false;
  final ShortcutBus _shortcutBus = ShortcutBus();
  final GlobalHotkeyService _hotkeyService = GlobalHotkeyService();
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();
  QuickFillHost? _quickFillHost;

  static bool get _isDesktop =>
      !kIsWeb && (Platform.isMacOS || Platform.isWindows || Platform.isLinux);

  @override
  void initState() {
    super.initState();
    if (!_isDesktop) return;

    windowManager.addListener(this);
    // 点关闭按钮 = 隐藏到菜单栏（真正退出走托盘菜单）。
    windowManager.setPreventClose(true);

    TrayManager.instance.addListener(this);
    _initTray();

    _hotkeyService.init(onTriggered: _toggleQuickFill);
  }

  @override
  void dispose() {
    if (_isDesktop) {
      windowManager.removeListener(this);
      TrayManager.instance.removeListener(this);
      TrayManager.instance.destroy();
    }
    _quickFillHost?.dispose();
    _hotkeyService.dispose();
    _shortcutBus.dispose();
    super.dispose();
  }

  /// 快速填充小窗宿主（首次使用时创建，需要 repository 与反馈通道）。
  ///
  /// 填充发生时用户在其它应用，反馈保持静默（不打断目标应用）；
  /// 失败信息走日志，后续可升级为系统通知。
  QuickFillHost _ensureQuickFillHost() {
    return _quickFillHost ??= QuickFillHost(
      repository: widget.repository,
      onFeedback: (String message, bool success) {
        debugPrint('quick fill: $message');
      },
    );
  }

  Future<void> _toggleQuickFill() async {
    // 锁定状态下热键绝不弹出条目列表：只唤起主窗口（其上已是解锁界面）。
    if (AppLockState.isLocked) {
      await _showMainWindow();
      return;
    }
    await _ensureQuickFillHost().toggle();
  }

  /// 托盘菜单（Clipy 式：功能入口 + 分隔 + 设置 + 退出）。
  ///
  /// 快速填充一项动态带上当前热键（每次弹出前重建，保证提示最新）。
  Menu _buildTrayMenu() {
    final bool mac = Platform.isMacOS;
    final String hotkey = GlobalHotkeyService.isSupported
        ? _hotkeyService.config.describe()
        : '';
    return Menu(
      items: <MenuItem>[
        MenuItem(key: 'show', label: '打开 KeyRing'),
        MenuItem(
          key: 'quick_fill',
          // macOS 的 NSMenu 中 tab 后的文字会右对齐显示，等效系统快捷键样式。
          label: mac && hotkey.isNotEmpty
              ? '快速填充…\t$hotkey'
              : '快速填充…',
        ),
        MenuItem(key: 'lock', label: '立即锁定'),
        MenuItem.separator(),
        MenuItem(key: 'settings', label: '设置…'),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: '退出 KeyRing'),
      ],
    );
  }

  Future<void> _initTray() async {
    try {
      await TrayManager.instance.setIcon('assets/tray/tray_icon.png');
      await TrayManager.instance.setToolTip('KeyRing');
      await TrayManager.instance.setContextMenu(_buildTrayMenu());
    } catch (_) {
      // 托盘初始化失败不影响主流程。
    }
  }

  /// 弹出托盘菜单（每次弹出前重建，热键等动态项保持最新）。
  Future<void> _popTrayMenu() async {
    try {
      await TrayManager.instance.setContextMenu(_buildTrayMenu());
    } catch (_) {
      // 重建失败时沿用旧菜单。
    }
    try {
      await TrayManager.instance.popUpContextMenu();
    } catch (_) {
      // 弹出失败不影响其它功能。
    }
  }

  Future<void> _showMainWindow() async {
    await windowManager.show();
    await windowManager.restore();
    await windowManager.focus();
  }

  /// 托盘「设置…」：唤起主窗口并进入设置页。
  ///
  /// 锁定时不直接推设置页（避免叠在解锁页上方、绕过解锁流程），
  /// 只展示主窗口让用户先解锁。
  Future<void> _openSettings() async {
    await _showMainWindow();
    if (AppLockState.isLocked) return;
    _navigatorKey.currentState?.push(
      MaterialPageRoute<void>(
        builder: (_) => SettingsScreen(hotkeyService: _hotkeyService),
      ),
    );
  }

  // ---- WindowListener：关闭按钮隐藏而非退出 ----

  @override
  void onWindowClose() {
    windowManager.hide();
  }

  // ---- TrayListener：菜单栏交互 ----

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'show':
        _showMainWindow();
      case 'quick_fill':
        _toggleQuickFill();
      case 'lock':
        _shortcutBus.fire(AppShortcutAction.lockNow);
      case 'settings':
        _openSettings();
      case 'quit':
        windowManager.destroy();
    }
  }

  @override
  void onTrayIconMouseDown() {
    if (Platform.isMacOS) {
      // macOS 上 tray_manager 不会自动弹菜单（原生按钮 action 未接线，
      // 菜单仅在 popUpContextMenu 调用期间挂载），必须显式弹出。
      _popTrayMenu();
    } else {
      // Windows 左键直接打开主窗口，右键由系统弹菜单。
      _showMainWindow();
    }
  }

  @override
  void onTrayIconRightMouseDown() {
    // macOS 右键同样弹出菜单；Windows 右键弹菜单（默认行为）。
    if (Platform.isMacOS) {
      _popTrayMenu();
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KeyRing',
      navigatorKey: _navigatorKey,
      theme: ThemeConfig.appTheme,
      builder: (BuildContext context, Widget? child) {
        // 应用级快捷键根节点：autofocus 的 Focus 让按键在未聚焦任何
        // 可交互控件时也能命中；TextField 等未消费的组合键会冒泡至此。
        return Container(
          decoration: const BoxDecoration(color: ThemeConfig.mainBgColor),
          child: Focus(
            autofocus: true,
            child: Shortcuts(
              shortcuts: buildAppShortcuts(_shortcutBus),
              child: Actions(
                actions: buildAppActions(),
                child: child ?? const SizedBox.shrink(),
              ),
            ),
          ),
        );
      },
      home: _unlocked
          ? HomeScreen(
              repository: widget.repository,
              shortcutBus: _shortcutBus,
              hotkeyService: _hotkeyService,
            )
          : LoginScreen(onUnlocked: () {
              AppLockState.markUnlocked();
              setState(() => _unlocked = true);
            }),
      // 定义命名路由表
      routes: {
        '/home': (context) => HomeScreen(
              repository: widget.repository,
              shortcutBus: _shortcutBus,
              hotkeyService: _hotkeyService,
            ),
      },
    );
  }
}
