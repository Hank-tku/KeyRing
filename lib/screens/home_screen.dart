import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:file_picker/file_picker.dart';
import 'dart:async';

import 'detail_screen.dart';
import 'edit_item_screen.dart';
import 'import/import_hub_sheet.dart';
import 'settings_screen.dart';
import '../models/password_item.dart';
import '../services/app_lock_state.dart';
import '../services/data_export_service.dart';
import '../services/global_hotkey_service.dart';
import '../services/import_merger.dart';
import '../services/password_repository.dart';
import '../services/lan_sync_service.dart';
import '../utils/app_shortcuts.dart';
import '../utils/import_validation.dart';
import '../utils/theme_config.dart';
import '../widgets/shared/app_card.dart';
import '../widgets/shared/copy_button.dart';
import 'package:flutter/foundation.dart';
import 'lock_screen.dart';

enum SyncState { idle, syncing, success, error, stopped }


class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.repository,
    this.shortcutBus,
    this.hotkeyService,
  });

  final PasswordRepository repository;

  /// 应用级快捷键总线（可选；为空时快捷键不生效）。
  final ShortcutBus? shortcutBus;

  /// 桌面端全局热键服务（可选；设置页用于自定义热键）。
  final GlobalHotkeyService? hotkeyService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final TextEditingController _searchController;
  late final FocusNode _searchFocus;

  List<PasswordItem> _items = <PasswordItem>[];
  String _query = '';
  String? _visibleItemId;
  LanSyncService? _lan;
  final DataExportService _dataExportService = DataExportService();
  bool _exporting = false;

  // 筛选状态
  bool _onlyFavorites = false;

  // 同步状态
  SyncState _syncState = SyncState.idle;

  final List<Timer> _timers = [];

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();
    _searchFocus = FocusNode();

    widget.shortcutBus?.addListener(_onShortcut);
    widget.repository.itemsNotifier.addListener(_onItemsChanged);

    _items = widget.repository.itemsNotifier.value;
    // Initialize LAN service but don't start it yet
    _lan = LanSyncService(repository: widget.repository);

    // 添加应用生命周期监听
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    // Cancel all timers
    for (final timer in _timers) {
      timer.cancel();
    }
    widget.shortcutBus?.removeListener(_onShortcut);
    _searchFocus.dispose();
    _searchController.dispose();
    _lan?.dispose();

    // Remove lifecycle observer
    WidgetsBinding.instance.removeObserver(this);

    super.dispose();
  }

  // 应用生命周期状态变化回调
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    if (kDebugMode) {
      debugPrint('应用查看生命周期状态变化: $state');
    }

    // 当应用从后台回到前台时，重新锁定屏幕
    if (state == AppLifecycleState.paused) {
      // 应用进入后台，可以在这里做一些处理（如记录时间）
      if (kDebugMode) {
        debugPrint('后台');
      }
      // 显示锁定屏幕
      _showLockScreen();
    } else if (state == AppLifecycleState.resumed) {
      // 应用回到前台，显示锁定屏幕
      if (kDebugMode) {
        debugPrint('前台，重新锁定');
      }
    } else if (state == AppLifecycleState.inactive) {
      if (kDebugMode) {
        debugPrint('非活跃状态');
      }
    } else if (state == AppLifecycleState.detached) {
      if (kDebugMode) {
        debugPrint('分离状态');
      }
    }
  }

  // 显示锁定屏幕的方法
  void _showLockScreen() {
    // 标记全局锁定状态：全局热键/快速填充等入口据此拒绝泄漏条目。
    AppLockState.markLocked();
    // 使用根导航器确保锁定屏幕覆盖整个应用
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (context) => LoginScreen(
          onUnlocked: () {
            AppLockState.markUnlocked();
            // 解锁后关闭锁定屏幕
            Navigator.of(context).pop();
          },
        ),
      ),
    );
  }

  void _onItemsChanged() {
    if (mounted) {
      setState(() => _items = widget.repository.itemsNotifier.value);
    }
  }

  /// 按搜索词 + 收藏筛选。返回过滤后（未排序）的列表。
  List<PasswordItem> _applyFilters(List<PasswordItem> source) {
    return source.where((PasswordItem item) {
      if (_onlyFavorites && !item.isFavorite) return false;
      if (_query.isEmpty) return true;
      final String q = _query.toLowerCase();
      return item.title.toLowerCase().contains(q) ||
          item.username.toLowerCase().contains(q) ||
          (item.url ?? '').toLowerCase().contains(q) ||
          (item.notes ?? '').toLowerCase().contains(q);
    }).toList();
  }

  /// 对已过滤列表排序：默认按修改时间倒序（最近改的在前），收藏置顶。
  List<PasswordItem> _applySort(List<PasswordItem> items) {
    final List<PasswordItem> copy = List<PasswordItem>.of(items);
    copy.sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    // 收藏项始终置顶
    copy.sort((a, b) {
      final int fav = (b.isFavorite ? 1 : 0) - (a.isFavorite ? 1 : 0);
      return fav;
    });
    return copy;
  }

  /// 切换收藏状态。
  Future<void> _toggleFavorite(PasswordItem item) async {
    try {
      final PasswordItem updated =
          item.copyWith(isFavorite: !item.isFavorite);
      await widget.repository.updateItem(updated);
    } catch (e) {
      if (mounted) {
        _showSnackBar('操作失败: $e', ThemeConfig.dangerColor);
      }
    }
  }

  Future<void> _add() async {
    final bool? changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) =>
            EditItemScreen(repository: widget.repository),
      ),
    );
    if (changed == true && mounted) {
      setState(() {});
    }
  }

  void _resetAllSync() {
    setState(() => _syncState = SyncState.idle);
    _lan?.resetServer();
  }

  Future<void> _viewDetail(PasswordItem item) async {
    _resetAllSync();
    final bool? changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) =>
            DetailScreen(item: item, repository: widget.repository),
      ),
    );
    if (changed == true && mounted) {
      setState(() {});
    }
  }

  Future<void> _delete(PasswordItem item) async {
    final bool? confirm = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除"${item.title}"吗？此操作无法撤销。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('删除'),
          ),
        ],
      ),
    );

    if (confirm == true) {
      try {
        await widget.repository.removeItem(item.id);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('已删除"${item.title}"'),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('删除失败: $e'),
              backgroundColor: Colors.red,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          );
        }
      }
    }
  }

  // Future<void> _toggleFavorite(PasswordItem item) async {
  //   try {
  //     final PasswordItem updated = item.copyWith(isFavorite: !item.isFavorite);
  //     await widget.repository.updateItem(updated);
  //   } catch (e) {
  //     if (mounted) {
  //       ScaffoldMessenger.of(context).showSnackBar(
  //         SnackBar(
  //           content: Text('操作失败: $e'),
  //           backgroundColor: Colors.red,
  //           behavior: SnackBarBehavior.floating,
  //           shape: RoundedRectangleBorder(
  //             borderRadius: BorderRadius.circular(8),
  //           ),
  //         ),
  //       );
  //     }
  //   }
  // }

  Future<void> _sync() async {
    if (!mounted) return;

    setState(() => _syncState = SyncState.syncing);

    try {
      final Map<String, dynamic>? result = await _lan?.discoverAndSyncOnce(
        // Server callback: Display code generated by server
        onServerCodeDisplay:
            (String deviceName, String code, Function(bool) onResponse) async {
              if (!mounted) {
                onResponse(false);
                return;
              }

              try {
                WidgetsBinding.instance.addPostFrameCallback((_) async {
                  try {
                    if (!mounted) {
                      onResponse(false);
                      return;
                    }

                    // This device is the SERVER - display the generated code
                    final bool? approved = await showDialog<bool>(
                      context: context,
                      barrierDismissible: false,
                      useRootNavigator: true, // Force use of root navigator
                      builder: (BuildContext context) {
                        return AlertDialog(
                          title: const Text('同步验证码'),
                          content: SingleChildScrollView(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text('设备 "$deviceName" 请求同步'),
                                const SizedBox(height: 20),
                                const Text(
                                  '请输入验证码:',
                                  style: TextStyle(
                                    fontSize: 16,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 20,
                                    horizontal: 24,
                                  ),
                                  decoration: BoxDecoration(
                                    color: ThemeConfig.primarySoft,
                                    borderRadius: BorderRadius.circular(ThemeConfig.radiusCard),
                                    border: Border.all(
                                      color: ThemeConfig.primaryColor.withValues(alpha: 0.4),
                                      width: 2,
                                    ),
                                  ),
                                  child: Text(
                                    code,
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: ThemeConfig.primaryColor,
                                      letterSpacing: 8,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  '等待对方输入验证码...',
                                  style: TextStyle(
                                    fontSize: ThemeConfig.fontSizeBody,
                                    color: ThemeConfig.secondaryTextColor,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                          actions: <Widget>[
                            TextButton(
                              onPressed: () {
                                Navigator.of(context).pop(false);
                                debugPrint('关闭同步相关');
                                if (mounted) {
                                  setState(
                                    () => _syncState = SyncState.stopped,
                                  );
                                }
                                _lan?.stopSync();
                              },
                              style: TextButton.styleFrom(
                                foregroundColor: Colors.red,
                              ),
                              child: const Text('取消同步'),
                            ),
                          ],
                        );
                      },
                    );

                    onResponse(approved ?? false);
                  } catch (e) {
                    if (mounted) {
                      onResponse(false);
                    }
                  }
                });
              } catch (e) {
                if (mounted) {
                  onResponse(false);
                }
              } finally {
                // Removed setState here to prevent issues
              }
            },
        onSyncSuccess: () {
          if (mounted) {
            Navigator.of(context, rootNavigator: true).pop();
            setState(() => _syncState = SyncState.success);
            _showSnackBar('同步成功', Colors.green);
          }
        },
        onCompatibilityWarning: (String message) {
          if (mounted) {
            _showSnackBar(message, Colors.orange);
          }
        },
        // Client callback: Input code shown on server
        onClientCodeInput:
            (String deviceName, Function(String) onCodeEntered) async {
              if (!mounted) {
                onCodeEntered('');
                return;
              }
              final TextEditingController codeController =
                  TextEditingController();

              try {
                // 让出当前帧再弹窗，避免阻塞 UI 线程。
                // 原来的 Future.delayed(1000ms) 是"用睡眠等连接就绪"，
                // 导致客户端验证码弹窗总是慢 1 秒。
                if (!mounted) {
                  onCodeEntered('');
                  return;
                }
                final NavigatorState rootNav =
                    Navigator.of(context, rootNavigator: true);
                await WidgetsBinding.instance.endOfFrame;
                if (!mounted) {
                  onCodeEntered('');
                  return;
                }

                final String? inputCode = await showDialog<String>(
                  context: rootNav.context,
                  barrierDismissible: false,
                  useRootNavigator: true, // Force use of root navigator
                  builder: (BuildContext context) {
                    return AlertDialog(
                      title: const Text('输入验证码'),
                      content: SingleChildScrollView(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text('正在连接设备 "$deviceName"'),
                            const SizedBox(height: 20),
                            const Text(
                              '请输入验证码:',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 16),
                            TextField(
                              controller: codeController,
                              autofocus: true,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              maxLength: 6,
                              style: const TextStyle(
                                fontSize: 24,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 6,
                                color: ThemeConfig.textColor,
                              ),
                              decoration: InputDecoration(
                                hintText: '000000',
                                counterText: '',
                                filled: true,
                                fillColor: ThemeConfig.fillColor,
                                hintStyle: const TextStyle(
                                  color: ThemeConfig.hintTextColor,
                                  letterSpacing: 6,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(ThemeConfig.radiusMd),
                                  borderSide: const BorderSide(
                                    color: ThemeConfig.dividerColor,
                                  ),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(ThemeConfig.radiusMd),
                                  borderSide: const BorderSide(
                                    color: ThemeConfig.dividerColor,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(ThemeConfig.radiusMd),
                                  borderSide: BorderSide(
                                    color: ThemeConfig.primaryColor,
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              '输入验证码后点击确认',
                              style: TextStyle(
                                fontSize: ThemeConfig.fontSizeCaption,
                                color: ThemeConfig.secondaryTextColor,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      actions: <Widget>[
                        TextButton(
                          onPressed: () {
                            debugPrint('取消同步关闭连接');
                            Navigator.of(context).pop(null);
                            _stopSync();
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: ThemeConfig.dangerColor,
                          ),
                          child: const Text('取消'),
                        ),
                        TextButton(
                          onPressed: () {
                            final String code = codeController.text.trim();
                            if (code.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text('请输入验证码'),
                                  backgroundColor: ThemeConfig.warningColor,
                                ),
                              );
                              return;
                            }
                            if (code.length != 6) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: const Text('验证码必须是6位数字'),
                                  backgroundColor: ThemeConfig.warningColor,
                                ),
                              );
                              return;
                            }

                            Navigator.of(context).pop(code);
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: ThemeConfig.primaryColor,
                          ),
                          child: const Text('确认'),
                        ),
                      ],
                    );
                  },
                );

                onCodeEntered(inputCode ?? '');
              } catch (e) {
                debugPrint('验证码输瑞错误: $e');
                onCodeEntered('');
              } finally {
                // codeController.dispose();
              }
            },
      );

      if (!mounted) return;

      // Handle sync results
      final String status = result?['status'];
      final String message = result?['message'] ?? '同步完成';

      // 状态配置映射
      final Map<String, List<dynamic>> statusMaps = {
        'success': [SyncState.success, Colors.green],
        'pending': [null, Colors.blue],
        'error': [SyncState.error, Colors.red],
        'stopped': [SyncState.stopped, Colors.orange],
      };
      final List? config = statusMaps[status];
      if (config != null) {
        if (config[0] != null && mounted) {
          setState(() => _syncState = config[0]);
        }
        if (mounted) {
          _showSnackBar(message, config[1]);
        }
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _syncState = SyncState.error);
      _showSnackBar('同步失败: $e', Colors.red);
    }
  }

  Future<void> _stopSync() async {
    if (!mounted) return;
    await _lan?.stopSync();
    if (!mounted) return;
    setState(() => _syncState = SyncState.stopped);
    _showSnackBar('同步已停止', Colors.orange);
  }

  Future<void> _exportData() async {
    if (_exporting) return;

    final bool? confirmed = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('导出数据'),
        content: const Text('导出的 JSON 文件会包含完整账号、用户名、密码和备注。请只保存到你信任的位置，并妥善保管。'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('确认导出'),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) return;

    setState(() => _exporting = true);
    try {
      final DataExportResult result = await _dataExportService.exportJson(
        widget.repository.itemsNotifier.value,
      );
      if (!mounted) return;
      await Clipboard.setData(ClipboardData(text: result.path));
      _showSnackBar('已导出 ${result.itemCount} 条数据，路径已复制', Colors.green);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('导出失败: $e', Colors.red);
    } finally {
      if (mounted) {
        setState(() => _exporting = false);
      }
    }
  }

  /// 导入 JSON 文件并合并到当前保险库。
  /// 先展示格式说明，用户确认后选择文件，再按 newer-wins 合并。
  Future<void> _importData() async {
    // 第一步：展示导入格式说明（含 JSON 示例 + 字段解释）。
    final bool? wantPick = await showDialog<bool>(
      context: context,
      builder: (BuildContext context) => AlertDialog(
        title: const Text('导入数据'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              const Text(
                '从 KeyRing 导出的 JSON 文件导入密码条目。支持两种格式：',
                style: TextStyle(fontSize: ThemeConfig.fontSizeBody),
              ),
              const SizedBox(height: ThemeConfig.space12),
              const Text(
                '合并规则',
                style: TextStyle(
                  fontSize: ThemeConfig.fontSizeBody,
                  fontWeight: FontWeight.w600,
                  color: ThemeConfig.primaryColor,
                ),
              ),
              const SizedBox(height: ThemeConfig.space4),
              Text(
                '• 相同账号（按 ID 匹配）：以较新的修改时间为准\n'
                '• 新账号：作为新增添加\n'
                '• 更旧的条目：自动跳过',
                style: const TextStyle(
                  fontSize: ThemeConfig.fontSizeCaption,
                  color: ThemeConfig.secondaryTextColor,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: ThemeConfig.space12),
              const Text(
                '文件示例',
                style: TextStyle(
                  fontSize: ThemeConfig.fontSizeBody,
                  fontWeight: FontWeight.w600,
                  color: ThemeConfig.primaryColor,
                ),
              ),
              const SizedBox(height: ThemeConfig.space4),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(ThemeConfig.space12),
                decoration: BoxDecoration(
                  color: ThemeConfig.mainBgColor,
                  borderRadius: BorderRadius.circular(ThemeConfig.radiusSm),
                  border: Border.all(color: ThemeConfig.dividerColor),
                ),
                child: SelectableText(
                  '{\n'
                  '  "app": "KeyRing",\n'
                  '  "items": [\n'
                  '    {\n'
                  '      "id": "唯一标识",\n'
                  '      "title": "GitHub",\n'
                  '      "username": "name@xx.com",\n'
                  '      "password": "你的密码",\n'
                  '      "url": "https://github.com",\n'
                  '      "notes": "备注（可选）",\n'
                  '      "isFavorite": 0\n'
                  '    }\n'
                  '  ]\n'
                  '}',
                  style: const TextStyle(
                    fontFamily: 'monospace',
                    fontSize: 11,
                    height: 1.5,
                    color: ThemeConfig.secondaryTextColor,
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('取消'),
          ),
          FilledButton.icon(
            onPressed: () => Navigator.of(context).pop(true),
            icon: const Icon(Icons.folder_open_outlined, size: 18),
            label: const Text('选择文件'),
          ),
        ],
      ),
    );
    if (wantPick != true || !mounted) return;

    // 第二步：选择 JSON 文件。
    final FilePickerResult? picked = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: <String>['json'],
      withData: false,
    );
    if (picked == null || picked.files.single.path == null) return;
    if (!mounted) return;

    final String filePath = picked.files.single.path!;

    try {
      final List<PasswordItem> incoming =
          await _dataExportService.importJson(filePath);
      final (:valid, :invalid) = const ImportValidator().filter(incoming);
      final ImportSummary summary =
          await ImportMerger(widget.repository).merge(valid);
      // 合并器不感知无效项，补回展示。
      final ImportSummary full = ImportSummary(
        added: summary.added,
        updated: summary.updated,
        skipped: summary.skipped,
        invalid: invalid,
      );
      if (!mounted) return;
      _showSnackBar('导入完成：$full', ThemeConfig.successColor);
    } catch (e) {
      if (!mounted) return;
      _showSnackBar('导入失败: $e', ThemeConfig.dangerColor);
    }
  }

  /// 打开统一导入入口面板。
  ///
  /// 文件导入走 [_importData]（复用既有 JSON 流程），扫码与截图跳转各自页面，
  /// 完成后通过回调刷新提示。供 PopupMenu 与应用内快捷键共用。
  Future<void> _openImportHub() async {
    await ImportHubSheet.show(
      context,
      repository: widget.repository,
      onPickFile: () {
        // 先关闭底部弹层，再走文件导入流程。
        Navigator.of(context).pop();
        _importData();
      },
      onResult: (String? message) {
        if (message == null) return;
        if (!mounted) return;
        final bool isError =
            message.startsWith('二维码内无有效条目') || message.contains('失败');
        _showSnackBar(
          message,
          isError ? ThemeConfig.dangerColor : ThemeConfig.successColor,
        );
      },
    );
  }

  /// 应用级快捷键动作分发。
  void _onShortcut() {
    final AppShortcutAction? action = widget.shortcutBus?.consume();
    if (action == null || !mounted) return;
    switch (action) {
      case AppShortcutAction.openImport:
        _openImportHub();
      case AppShortcutAction.exportData:
        _exportData();
      case AppShortcutAction.focusSearch:
        _searchFocus.requestFocus();
      case AppShortcutAction.lockNow:
        _showLockScreen();
      case AppShortcutAction.quickFill:
        // 全局热键由 App 层的 QuickFillHost 处理（独立小窗），此处不响应。
        break;
    }
  }

  void _showSnackBar(String message, Color backgroundColor) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: backgroundColor,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        duration: const Duration(seconds: 4),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final List<PasswordItem> filtered = _applyFilters(_items);
    final List<PasswordItem> sorted = _applySort(filtered);

    return Scaffold(
      appBar: AppBar(
        title: const Text('KeyRing'),
        titleTextStyle: const TextStyle(
          color: ThemeConfig.primaryColor,
          fontSize: ThemeConfig.fontSizeTitle,
          fontWeight: FontWeight.w500,
        ),
        actions: <Widget>[
          IconButton(
            onPressed: _syncState == SyncState.syncing ? _stopSync : _sync,
            icon: _buildSyncIcon(),
            color: _buildSyncIconColor(),
            tooltip: _buildSyncTooltip(),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            tooltip: '更多',
            onSelected: (String value) {
              switch (value) {
                case 'lock':
                  _showLockScreen();
                  break;
                case 'export':
                  _exportData();
                  break;
                case 'import':
                  _openImportHub();
                  break;
                case 'settings':
                  // 未注入热键服务（异常路径）时不进设置页，避免误建
                  // 一个未 init 的服务实例导致"注册失败"误导提示。
                  final GlobalHotkeyService? hotkeyService =
                      widget.hotkeyService;
                  if (hotkeyService != null) {
                    Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => SettingsScreen(
                          hotkeyService: hotkeyService,
                        ),
                      ),
                    );
                  }
                  break;
              }
            },
            itemBuilder: (BuildContext context) =>
                <PopupMenuEntry<String>>[
              const PopupMenuItem<String>(
                value: 'lock',
                child: ListTile(
                  leading: Icon(Icons.lock_outline),
                  title: Text('立即锁定'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'settings',
                child: ListTile(
                  leading: Icon(Icons.settings_outlined),
                  title: Text('设置'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              const PopupMenuDivider(),
              const PopupMenuItem<String>(
                value: 'import',
                child: ListTile(
                  leading: Icon(Icons.upload_outlined),
                  title: Text('导入数据'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
              const PopupMenuItem<String>(
                value: 'export',
                child: ListTile(
                  leading: Icon(Icons.download_outlined),
                  title: Text('导出数据'),
                  contentPadding: EdgeInsets.zero,
                  dense: true,
                ),
              ),
            ],
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: TextField(
              controller: _searchController,
              focusNode: _searchFocus,
              onChanged: (String v) => setState(() => _query = v.trim()),
              style: const TextStyle(color: ThemeConfig.textColor),
              decoration: InputDecoration(
                hintText: '搜索账号名/用户名/网址/备注',
                prefixIcon: const Icon(Icons.search),
                hintStyle: const TextStyle(color: ThemeConfig.hintTextColor),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _query = '');
                        },
                      )
                    : null,
                filled: true,
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(ThemeConfig.radiusMd),
                  borderSide: const BorderSide(
                    color: ThemeConfig.inputBorderColor,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(ThemeConfig.radiusMd),
                  borderSide: const BorderSide(
                    color: ThemeConfig.primaryColor,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 6,
                  vertical: 6,
                ),
              ),
            ),
          ),
        ),
      ),
      body: Column(
        children: <Widget>[
          // 筛选与排序工具栏
          _buildToolbar(sorted.length),
          Expanded(
            child: sorted.isEmpty
                ? _buildEmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.fromLTRB(
                      12,
                      4,
                      12,
                      80,
                    ), // 底部留白避开 FAB
                    itemCount: sorted.length,
                    separatorBuilder: (_, __) =>
                        const SizedBox(height: ThemeConfig.space8),
                    itemBuilder: (BuildContext context, int index) {
                      final PasswordItem item = sorted[index];
                      return _buildPasswordCard(item);
                    },
                  ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _add,
        icon: const Icon(Icons.add),
        label: const Text('新增'),
        tooltip: '新增密码',
      ),
    );
  }

  /// 构建筛选工具栏（仅收藏筛选 + 计数）。
  /// 列表默认按修改时间倒序，不再提供排序切换。
  Widget _buildToolbar(int count) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
      child: Row(
        children: <Widget>[
          FilterChip(
            label: const Text('收藏'),
            selected: _onlyFavorites,
            onSelected: (bool v) => setState(() => _onlyFavorites = v),
            selectedColor: ThemeConfig.primarySoft,
            checkmarkColor: ThemeConfig.primaryColor,
            labelStyle: TextStyle(
              color: _onlyFavorites
                  ? ThemeConfig.primaryColor
                  : ThemeConfig.secondaryTextColor,
            ),
            side: BorderSide(
              color: _onlyFavorites
                  ? ThemeConfig.primaryColor.withValues(alpha: 0.4)
                  : ThemeConfig.inputBorderColor,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(ThemeConfig.radiusPill),
            ),
            showCheckmark: false,
            avatar: Icon(
              _onlyFavorites ? Icons.bookmark : Icons.bookmark_border,
              size: 18,
              color: _onlyFavorites
                  ? ThemeConfig.favoriteColor
                  : ThemeConfig.secondaryTextColor,
            ),
          ),
          const Spacer(),
          Text(
            '共 $count 项',
            style: const TextStyle(
              color: ThemeConfig.hintTextColor,
              fontSize: ThemeConfig.fontSizeCaption,
            ),
          ),
        ],
      ),
    );
  }

  Icon _buildSyncIcon() {
    switch (_syncState) {
      case SyncState.syncing:
        return const Icon(Icons.stop_circle_outlined);
      case SyncState.success:
        return const Icon(Icons.check_circle_outlined);
      case SyncState.error:
        return const Icon(Icons.error_outline);
      case SyncState.stopped:
      case SyncState.idle:
        return const Icon(Icons.sync);
    }
  }

  Color _buildSyncIconColor() {
    switch (_syncState) {
      case SyncState.syncing:
      case SyncState.stopped:
        return ThemeConfig.warningColor;
      case SyncState.success:
        return ThemeConfig.successColor;
      case SyncState.error:
        return ThemeConfig.dangerColor;
      case SyncState.idle:
        return ThemeConfig.secondaryTextColor;
    }
  }

  String _buildSyncTooltip() {
    switch (_syncState) {
      case SyncState.syncing:
        return '停止同步';
      case SyncState.success:
        return '同步成功，点击重新同步';
      case SyncState.error:
        return '同步失败，点击重新同步';
      case SyncState.stopped:
        return '同步已停止，点击重新同步';
      case SyncState.idle:
        return '局域网同步';
    }
  }

  Widget _buildEmptyState() {
    if (_query.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            const Icon(
              Icons.search_off,
              size: 64,
              color: ThemeConfig.secondaryTextColor,
            ),
            const SizedBox(height: ThemeConfig.space16),
            Text(
              '没有找到匹配的结果',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: ThemeConfig.hintTextColor,
                  ),
            ),
            const SizedBox(height: ThemeConfig.space8),
            Text(
              '尝试使用不同的关键词搜索',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: ThemeConfig.hintTextColor,
                  ),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          const Icon(
            Icons.lock_outline,
            size: 64,
            color: ThemeConfig.secondaryTextColor,
          ),
          const SizedBox(height: ThemeConfig.space16),
          Text(
            '暂未记录密码',
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  color: ThemeConfig.hintTextColor,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: ThemeConfig.space8),
          Text(
            '点击右下角按钮，添加第一个密码记录',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: ThemeConfig.hintTextColor,
                ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordCard(PasswordItem item) {
    final bool revealed = _visibleItemId == item.id;

    // 用 Dismissible 包裹卡片，左滑露出删除。
    return Dismissible(
      key: ValueKey<String>(item.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (_) async {
        await _delete(item);
        return false; // 由 _delete 内部处理实际删除，Dismissible 不自行移除
      },
      background: Container(
        alignment: Alignment.centerRight,
        padding: const EdgeInsets.only(right: ThemeConfig.space24),
        decoration: BoxDecoration(
          color: ThemeConfig.dangerColor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(ThemeConfig.radiusCard),
        ),
        child: const Icon(
          Icons.delete_outline,
          color: ThemeConfig.dangerColor,
        ),
      ),
      child: AppCard(
        onTap: () => _viewDetail(item),
        onLongPress: () {
          // 长按改为触感反馈切收藏，不再直接弹删除框（防误触）。
          HapticFeedback.mediumImpact();
          _toggleFavorite(item);
        },
        backgroundColor: item.isFavorite
            ? ThemeConfig.primarySoft
            : null,
        borderColor: item.isFavorite
            ? ThemeConfig.favoriteColor.withValues(alpha: 0.4)
            : null,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            // 标题行 + 收藏 bookmark
            Row(
              children: <Widget>[
                Expanded(
                  child: Text(
                    item.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ThemeConfig.textColor,
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _toggleFavorite(item),
                  icon: Icon(
                    item.isFavorite
                        ? Icons.bookmark
                        : Icons.bookmark_border,
                    size: 22,
                    color: item.isFavorite
                        ? ThemeConfig.favoriteColor
                        : ThemeConfig.secondaryTextColor,
                  ),
                  tooltip: item.isFavorite ? '取消收藏' : '收藏',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
              ],
            ),
            const SizedBox(height: ThemeConfig.space8),
            // 用户名行
            Row(
              children: <Widget>[
                Icon(
                  Icons.person_outline,
                  size: 16,
                  color: ThemeConfig.hintTextColor,
                ),
                const SizedBox(width: ThemeConfig.space8),
                Expanded(
                  child: Text(
                    item.username.isNotEmpty ? item.username : '无用户名',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ThemeConfig.textColor,
                      fontSize: ThemeConfig.fontSizeBody,
                    ),
                  ),
                ),
                if (item.username.isNotEmpty)
                  CopyButton(
                    text: item.username,
                    label: '用户名',
                    iconSize: 16,
                  ),
              ],
            ),
            const SizedBox(height: ThemeConfig.space8),
            // 密码行：常驻眼睛 + 复制（不用先点眼睛才出现复制）
            Row(
              children: <Widget>[
                Icon(
                  Icons.lock_outline,
                  size: 16,
                  color: ThemeConfig.hintTextColor,
                ),
                const SizedBox(width: ThemeConfig.space8),
                Expanded(
                  child: Text(
                    revealed
                        ? item.password
                        : '•' * (item.password.length.clamp(6, 12)),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: ThemeConfig.textColor,
                      fontSize: ThemeConfig.fontSizeBody,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => setState(
                    () => _visibleItemId = revealed ? null : item.id,
                  ),
                  icon: Icon(
                    revealed ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                    size: 18,
                    color: ThemeConfig.secondaryTextColor,
                  ),
                  tooltip: revealed ? '隐藏密码' : '显示密码',
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(
                    minWidth: 32,
                    minHeight: 32,
                  ),
                ),
                CopyButton(text: item.password, label: '密码', iconSize: 16),
              ],
            ),
            // 网址来源（有 url 时展示）
            if (item.url != null && item.url!.isNotEmpty) ...<Widget>[
              const SizedBox(height: ThemeConfig.space8),
              Row(
                children: <Widget>[
                  Icon(
                    Icons.language,
                    size: 16,
                    color: ThemeConfig.hintTextColor,
                  ),
                  const SizedBox(width: ThemeConfig.space8),
                  Expanded(
                    child: Text(
                      _hostFromUrl(item.url!),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: ThemeConfig.hintTextColor,
                        fontSize: ThemeConfig.fontSizeCaption,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// 从 url 中提取 host 用于卡片展示（如 https://github.com/x → github.com）。
  String _hostFromUrl(String url) {
    try {
      final Uri? uri = Uri.tryParse(url);
      if (uri != null && uri.host.isNotEmpty) {
        return uri.host;
      }
    } catch (_) {
      // 解析失败，回退到原始字符串
    }
    return url;
  }
}
