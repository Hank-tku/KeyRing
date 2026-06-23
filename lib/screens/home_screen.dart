import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'dart:async';

import 'detail_screen.dart';
import 'edit_item_screen.dart';
import '../models/password_item.dart';
import '../services/data_export_service.dart';
import '../services/password_repository.dart';
import '../services/lan_sync_service.dart';
import '../utils/theme_config.dart';
import 'package:flutter/foundation.dart';
import 'lock_screen.dart';

enum SyncState { idle, syncing, success, error, stopped }

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.repository});

  final PasswordRepository repository;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final TextEditingController _searchController;

  List<PasswordItem> _items = <PasswordItem>[];
  String _query = '';
  String? _visibleItemId;
  LanSyncService? _lan;
  final DataExportService _dataExportService = DataExportService();
  bool _exporting = false;

  // 同步状态
  SyncState _syncState = SyncState.idle;

  final List<Timer> _timers = [];

  @override
  void initState() {
    super.initState();
    _searchController = TextEditingController();

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
    // 使用根导航器确保锁定屏幕覆盖整个应用
    Navigator.of(context, rootNavigator: true).push(
      MaterialPageRoute(
        builder: (context) => LoginScreen(
          onUnlocked: () {
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

  void _copy(String text, String label) {
    Clipboard.setData(ClipboardData(text: text));
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('已复制$label'),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      );
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

  Future<void> _edit(PasswordItem item) async {
    final bool? changed = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (BuildContext context) =>
            EditItemScreen(repository: widget.repository, initial: item),
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
                                    horizontal: 32,
                                  ),
                                  decoration: BoxDecoration(
                                    color: const Color(
                                      0xFF2DD4BF,
                                    ).withValues(alpha: 0.1),
                                    borderRadius: BorderRadius.circular(16),
                                    border: Border.all(
                                      color: const Color(0xFF2DD4BF),
                                      width: 2,
                                    ),
                                  ),
                                  child: Text(
                                    code,
                                    style: const TextStyle(
                                      fontSize: 28,
                                      fontWeight: FontWeight.bold,
                                      color: Color(0xFF2DD4BF),
                                      letterSpacing: 10,
                                      fontFamily: 'monospace',
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  '等待对方输入验证码...',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.grey,
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
                await Future.delayed(const Duration(milliseconds: 1000));
                if (!mounted) {
                  onCodeEntered('');
                  return;
                }

                final String? inputCode = await showDialog<String>(
                  context: context,
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
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 12,
                              ),
                              decoration: InputDecoration(
                                hintText: '000000',
                                counterText: '',
                                filled: true,
                                fillColor: Colors.grey[100],
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: BorderSide(
                                    color: Colors.grey[300]!,
                                  ),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  borderSide: const BorderSide(
                                    color: Color(0xFF2DD4BF),
                                    width: 2,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 12),
                            const Text(
                              '输入验证码后点击确认',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
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
                            foregroundColor: Colors.red,
                          ),
                          child: const Text('取消'),
                        ),
                        TextButton(
                          onPressed: () {
                            final String code = codeController.text.trim();
                            debugPrint('User entered code: $code');
                            if (code.isEmpty) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('请输入验证码'),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                              return;
                            }
                            if (code.length != 6) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('验证码必须是6位数字'),
                                  backgroundColor: Colors.orange,
                                ),
                              );
                              return;
                            }

                            Navigator.of(context).pop(code);
                          },
                          style: TextButton.styleFrom(
                            foregroundColor: const Color(0xFF2DD4BF),
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
    final List<PasswordItem> filtered = _items.where((PasswordItem item) {
      if (_query.isEmpty) return true;
      final String q = _query.toLowerCase();
      return item.title.toLowerCase().contains(q) ||
          item.username.toLowerCase().contains(q) ||
          (item.url ?? '').toLowerCase().contains(q) ||
          (item.notes ?? '').toLowerCase().contains(q);
    }).toList();

    return Scaffold(
      appBar: AppBar(
        title: const Text('KeyRing', textAlign: TextAlign.left),
        titleTextStyle: const TextStyle(
          color: Color(0xFF2DD4BF),
          fontSize: 22,
          fontWeight: FontWeight.w500,
        ),
        actions: <Widget>[
          IconButton(
            onPressed: _exporting ? null : _exportData,
            icon: _exporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.download, color: Color(0xFF94A3B8)),
            tooltip: '导出数据',
          ),
          IconButton(
            onPressed: _syncState == SyncState.syncing ? _stopSync : _sync,
            icon: () {
              switch (_syncState) {
                case SyncState.syncing:
                  return const Icon(Icons.stop_circle, color: Colors.orange);
                case SyncState.success:
                  return const Icon(Icons.check_circle, color: Colors.green);
                case SyncState.error:
                  return const Icon(Icons.error, color: Colors.red);
                case SyncState.stopped:
                  return const Icon(Icons.sync, color: Colors.orange);
                case SyncState.idle:
                  return const Icon(Icons.sync, color: Color(0xFF94A3B8));
              }
            }(),
            tooltip: () {
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
            }(),
          ),
        ],
        flexibleSpace: Container(
          decoration: const BoxDecoration(color: Color(0xFF121A2E)),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(60),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            child: TextField(
              controller: _searchController,
              onChanged: (String v) => setState(() => _query = v.trim()),
              style: const TextStyle(color: ThemeConfig.textColor),
              decoration: InputDecoration(
                hintText: '搜索账号名/用户名/网址/备注',
                prefixIcon: const Icon(Icons.search),
                hintStyle: const TextStyle(color: Color(0xFF9CA3AF)),
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
                  borderRadius: BorderRadius.circular(20),
                  borderSide: const BorderSide(
                    color: ThemeConfig.inputBorderColor,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: const BorderSide(
                    color: ThemeConfig.inputBorderColor,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 0),
            child: Row(
              children: <Widget>[
                FilledButton.tonalIcon(
                  onPressed: _add,
                  icon: const Icon(Icons.add, size: 20),
                  label: const Text('新增'),
                  style: ButtonStyle(
                    backgroundColor: const WidgetStatePropertyAll(
                      ThemeConfig.primaryColor,
                    ),
                    padding: const WidgetStatePropertyAll<EdgeInsets>(
                      EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                    ),
                    shape: WidgetStatePropertyAll<OutlinedBorder>(
                      RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                  ),
                ),
                const Spacer(),
                Text(
                  '共 ${filtered.length} 项',
                  style: const TextStyle(color: ThemeConfig.textColor),
                ),
              ],
            ),
          ),
          const SizedBox(height: 2),
          Expanded(
            child: filtered.isEmpty
                ? _buildEmptyState()
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: filtered.length,
                    separatorBuilder: (_, __) => const SizedBox(height: 10),
                    itemBuilder: (BuildContext context, int index) {
                      final PasswordItem item = filtered[index];
                      return _buildPasswordCard(item);
                    },
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    if (_query.isNotEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: <Widget>[
            Icon(Icons.search_off, size: 64, color: Colors.grey.shade400),
            const SizedBox(height: 16),
            Text(
              '没有找到匹配的结果',
              style: Theme.of(
                context,
              ).textTheme.titleMedium?.copyWith(color: Colors.grey.shade600),
            ),
            const SizedBox(height: 8),
            Text(
              '尝试使用不同的关键词搜索',
              style: Theme.of(
                context,
              ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: <Widget>[
          Icon(Icons.lock_outline, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          Text(
            '暂未记录密码',
            style: Theme.of(
              context,
            ).textTheme.titleMedium?.copyWith(color: Colors.grey.shade600),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            '点击新增按钮，添加第一个密码记录',
            style: Theme.of(
              context,
            ).textTheme.bodyMedium?.copyWith(color: Colors.grey.shade500),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildPasswordCard(PasswordItem item) {
    return GestureDetector(
      onTap: () => _viewDetail(item),
      onLongPress: () => _delete(item),
      child: Container(
        height: 108,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          color: item.isFavorite
              ? const Color(0xFFFFE69C)
              : ThemeConfig.fillColor,
          boxShadow: [
            BoxShadow(
              color: ThemeConfig.fillColor.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Row(
            children: [
              // 内容区域
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 6),

                    // 用户名行
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            item.username.isNotEmpty ? item.username : '无用户名',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (item.username.isNotEmpty)
                          InkWell(
                            onTap: () => _copy(item.username, '用户名'),
                            child: Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Icon(
                                Icons.copy,
                                size: 14,
                                color: Colors.grey[400],
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 6),

                    // 密码行
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            _visibleItemId == item.id
                                ? item.password
                                : '••••••••',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ),
                        if (_visibleItemId == item.id)
                          InkWell(
                            onTap: () => _copy(item.password, '密码'),
                            child: Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Icon(
                                Icons.copy,
                                size: 14,
                                color: Colors.grey[400],
                              ),
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              ),

              // 操作按钮区域
              SizedBox(
                width: 150,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _buildMobileIconButton(
                      Icons.visibility,
                      _visibleItemId == item.id ? '隐藏' : '显示',
                      () => setState(
                        () => _visibleItemId = _visibleItemId == item.id
                            ? null
                            : item.id,
                      ),
                    ),
                    _buildMobileIconButton(Icons.edit, '编辑', () => _edit(item)),
                    _buildMobileIconButton(
                      Icons.delete,
                      '删除',
                      () => _delete(item),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMobileIconButton(
    IconData icon,
    String tooltip,
    VoidCallback onPressed,
  ) {
    return IconButton(
      icon: Icon(icon, size: 28),
      color: Colors.grey[300],
      onPressed: onPressed,
      tooltip: tooltip,
      padding: const EdgeInsets.all(4),
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
    );
  }
}
