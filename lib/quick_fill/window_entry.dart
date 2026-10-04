import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:desktop_multi_window/desktop_multi_window.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../utils/theme_config.dart';

/// 快速填充小面板（独立子窗口，1Password 式）。
///
/// 运行在独立的引擎/isolate 中：
/// - 启动后及每次被宿主唤起（`refresh`）时向主窗口请求条目
///   （id/title/username/url，不含密码）
/// - 键盘优先：↑↓ 选择、回车填充、Esc 关闭（焦点在搜索框内也生效）
/// - 10 秒无操作自动隐藏；失焦隐藏
/// - 填充失败时宿主回推 `feedback` 并重新显示本面板提示原因
/// 主窗口侧见 `quick_fill_host.dart`。
Future<void> runQuickFillWindow() async {
  runApp(const QuickFillWindowApp());
}

class QuickFillWindowApp extends StatelessWidget {
  const QuickFillWindowApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'KeyRing Quick Fill',
      debugShowCheckedModeBanner: false,
      theme: ThemeConfig.appTheme,
      home: const QuickFillWindowPage(),
    );
  }
}

class _Entry {
  const _Entry(this.id, this.title, this.username, this.url, this.workspace);

  factory _Entry.fromJson(Map<String, dynamic> json) => _Entry(
    json['id'] as String? ?? '',
    json['title'] as String? ?? '',
    json['username'] as String? ?? '',
    json['url'] as String? ?? '',
    json['workspace'] as String? ?? '',
  );

  final String id;
  final String title;
  final String username;
  final String url;

  /// 所属工作区名（多个工作区时便于区分；桌面端只有全同步工作区）。
  final String workspace;
}

class QuickFillWindowPage extends StatefulWidget {
  const QuickFillWindowPage({super.key});

  @override
  State<QuickFillWindowPage> createState() => _QuickFillWindowPageState();
}

class _QuickFillWindowPageState extends State<QuickFillWindowPage>
    with WidgetsBindingObserver {
  static const Duration _idleTimeout = Duration(seconds: 10);

  /// 宿主 → 面板的命令通道（refresh/feedback/hide）。
  ///
  /// controller 通道（`mixin.one/window_controller/$windowId`）是
  /// unidirectional 模式：整条通道只允许一个引擎注册 handler——宿主已注册
  /// （用于接收 requestItems/fill），本引擎再注册会抛 CHANNEL_LIMIT_REACHED。
  /// 所以宿主→面板方向必须走这条独立通道，由本引擎注册 handler。
  static const WindowMethodChannel _cmdChannel = WindowMethodChannel(
    'keyring.quickfill/cmd',
    mode: ChannelMode.unidirectional,
  );

  WindowController? _controller;
  final TextEditingController _searchCtrl = TextEditingController();
  final ScrollController _scrollCtrl = ScrollController();
  late final FocusNode _searchFocus;

  List<_Entry> _entries = <_Entry>[];
  bool _loaded = false;
  bool _locked = true;
  bool _authenticating = false;
  int _requestGeneration = 0;
  List<Map<String, dynamic>> _lockedWorkspaces = [];
  static const _platformChannel = MethodChannel('keyring/quickfill_window');
  int _selectedIndex = 0;

  /// 底部提示行文案（填充失败原因等），null 时显示操作提示。
  String? _footerMessage;
  Timer? _idleTimer;
  Timer? _footerTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 搜索内容变化即重置选中项。
    _searchCtrl.addListener(() {
      if (mounted) setState(() => _selectedIndex = 0);
    });
    _searchFocus = FocusNode(onKeyEvent: _onSearchKey);
    _platformChannel.setMethodCallHandler((call) async {
      if (call.method == 'blur' && !_authenticating) await _hide();
    });
    _boot();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _idleTimer?.cancel();
    _platformChannel.setMethodCallHandler(null);
    _footerTimer?.cancel();
    _searchCtrl.dispose();
    _scrollCtrl.dispose();
    _searchFocus.dispose();
    super.dispose();
  }

  Future<void> _boot() async {
    try {
      final WindowController controller =
          await WindowController.fromCurrentEngine();
      if (!mounted) return;
      _controller = controller;
    } catch (_) {
      // 拿不到控制器（异常情况）：继续渲染空面板。
    }
    // 注册宿主→面板命令通道。失败只损失 refresh/feedback 推送，
    // 不阻断条目拉取，更不能让异常中断 _boot（否则永远 loading）。
    try {
      await _cmdChannel.setMethodCallHandler(_onCommand);
    } catch (_) {
      // 忽略。
    }
    await _fetchEntries();
    if (mounted) _searchFocus.requestFocus();
    _pokeIdleTimer();
  }

  /// 宿主 → 面板：refresh（每次呼起刷新条目）、feedback（填充失败原因）、hide。
  Future<dynamic> _onCommand(MethodCall call) async {
    switch (call.method) {
      case 'refresh':
        // 每次呼起都是新会话：清掉上次的搜索词与选中项再拉取。
        _searchCtrl.clear();
        await _fetchEntries();
        if (mounted) _searchFocus.requestFocus();
        _pokeIdleTimer();
        return null;
      case 'feedback':
        final dynamic args = call.arguments;
        String message = '填充失败';
        if (args is Map) {
          message = args['message'] as String? ?? message;
        }
        if (mounted) {
          setState(() => _footerMessage = message);
          _footerTimer?.cancel();
          _footerTimer = Timer(const Duration(seconds: 4), () {
            if (mounted) setState(() => _footerMessage = null);
          });
        }
        _pokeIdleTimer();
        return null;
      case 'hide':
        await _hide();
        return null;
      default:
        return null;
    }
  }

  Future<void> _fetchEntries() async {
    final generation = ++_requestGeneration;
    if (mounted) {
      setState(() {
        _entries = [];
        _lockedWorkspaces = [];
        _loaded = false;
      });
    }
    try {
      final raw = await _controller?.invokeMethod<String>('requestItems');
      if (!mounted || generation != _requestGeneration) return;
      if (raw == null) throw StateError('host unavailable');
      final decoded = jsonDecode(raw) as Map<String, dynamic>;
      setState(() {
        _locked = decoded['locked'] == true;
        _entries = [
          for (final e in decoded['items'] as List)
            _Entry.fromJson(Map<String, dynamic>.from(e as Map)),
        ];
        _lockedWorkspaces = [
          for (final w in decoded['workspaces'] as List)
            Map<String, dynamic>.from(w as Map),
        ];
        _loaded = true;
        _selectedIndex = 0;
      });
    } catch (_) {
      if (mounted && generation == _requestGeneration) {
        setState(() {
          _loaded = true;
          _locked = true;
        });
      }
    }
  }

  Future<void> _unlockApp() async {
    if (_authenticating) return;
    setState(() => _authenticating = true);
    _idleTimer?.cancel();
    try {
      final ok = await _controller?.invokeMethod<bool>('unlockApp') ?? false;
      if (!mounted) return;
      if (!ok) setState(() => _footerMessage = '验证未完成，请重试');
      await _fetchEntries();
    } finally {
      if (mounted) setState(() => _authenticating = false);
      _pokeIdleTimer();
    }
  }

  Future<void> _unlockWorkspace(Map<String, dynamic> workspace) async {
    if (_authenticating) return;
    _authenticating = true;
    _idleTimer?.cancel();
    if (workspace['mode'] == 'system') {
      try {
        final ok =
            await _controller?.invokeMethod<bool>('unlockWorkspace', {
              'id': workspace['id'],
            }) ??
            false;
        if (mounted && !ok) setState(() => _footerMessage = '系统验证未完成');
      } catch (_) {
        if (mounted) setState(() => _footerMessage = '暂时无法进行系统验证');
      } finally {
        _authenticating = false;
        await _fetchEntries();
        _pokeIdleTimer();
      }
      return;
    }
    final password = TextEditingController();
    bool busy = false;
    bool accepted = false;
    String? error;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, update) => AlertDialog(
          title: Text('解锁 ${workspace['name']}'),
          content: TextField(
            controller: password,
            autofocus: true,
            obscureText: true,
            enabled: !busy,
            decoration: InputDecoration(labelText: '本机工作区密码', errorText: error),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: busy
                  ? null
                  : () async {
                      update(() => busy = true);
                      final ok =
                          await _controller?.invokeMethod<bool>(
                            'unlockWorkspace',
                            {'id': workspace['id'], 'password': password.text},
                          ) ??
                          false;
                      if (!dialogContext.mounted) return;
                      if (ok) {
                        accepted = true;
                        Navigator.pop(dialogContext);
                      } else {
                        update(() {
                          busy = false;
                          error = '密码错误、暂时冷却或应用已锁定';
                        });
                      }
                    },
              child: Text(busy ? '验证中…' : '解锁'),
            ),
          ],
        ),
      ),
    );
    if (!accepted) {
      await _controller?.invokeMethod<void>(
        'cancelWorkspaceUnlock',
        workspace['id'],
      );
    }
    // Dialog disposal follows the exit animation.
    await Future<void>.delayed(const Duration(milliseconds: 250));
    password.dispose();
    _authenticating = false;
    await _fetchEntries();
    _pokeIdleTimer();
  }

  /// 搜索框聚焦时拦截 ↑↓/回车/Esc。
  ///
  /// 不能用 CallbackShortcuts/TextField.onSubmitted：焦点在 TextField 内时
  /// 这些键会被文本框默认行为吃掉，冒泡不到外层。
  KeyEventResult _onSearchKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    _pokeIdleTimer();
    final List<_Entry> list = _filtered;
    switch (event.logicalKey) {
      case LogicalKeyboardKey.escape:
        _hide(restoreTarget: true);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowDown:
        if (list.isNotEmpty) _moveSelection(1, list.length);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.arrowUp:
        if (list.isNotEmpty) _moveSelection(-1, list.length);
        return KeyEventResult.handled;
      case LogicalKeyboardKey.enter:
      case LogicalKeyboardKey.numpadEnter:
        if (list.isNotEmpty) {
          _fill(list[_selectedIndex.clamp(0, list.length - 1)]);
        }
        return KeyEventResult.handled;
      default:
        return KeyEventResult.ignored;
    }
  }

  void _moveSelection(int delta, int length) {
    final int next = (_selectedIndex + delta).clamp(0, length - 1);
    if (next == _selectedIndex) return;
    setState(() => _selectedIndex = next);
    _ensureSelectedVisible(next);
  }

  /// 让选中项滚进可视区（按固定行高估算即可）。
  void _ensureSelectedVisible(int index) {
    if (!_scrollCtrl.hasClients) return;
    const double itemExtent = 56;
    final double top = index * itemExtent;
    final double viewport = _scrollCtrl.position.viewportDimension;
    final double offset = _scrollCtrl.offset;
    if (top < offset) {
      _scrollCtrl.jumpTo(top);
    } else if (top + itemExtent > offset + viewport) {
      _scrollCtrl.jumpTo(top + itemExtent - viewport);
    }
  }

  Future<void> _hide({bool restoreTarget = false}) async {
    if (_authenticating) return;
    _idleTimer?.cancel();
    _requestGeneration++;
    _searchCtrl.clear();
    if (mounted) {
      setState(() {
        _entries = [];
        _lockedWorkspaces = [];
        _selectedIndex = 0;
        _footerMessage = null;
      });
    }
    await _controller?.invokeMethod<void>('panelHidden', restoreTarget);
  }

  Future<void> _fill(_Entry entry) async {
    _idleTimer?.cancel();
    try {
      await _controller?.invokeMethod<void>('fill', entry.id);
    } catch (_) {}
  }

  /// 10 秒无操作自动隐藏。
  void _pokeIdleTimer() {
    _idleTimer?.cancel();
    if (_authenticating) return;
    _idleTimer = Timer(_idleTimeout, () {
      if (mounted) _hide();
    });
  }

  /// 失焦自动隐藏（用户点了别处）。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (Platform.isMacOS || _authenticating) return;
    if (state != AppLifecycleState.resumed) {
      // inactive：窗口失去键盘焦点。稍等一拍避免误触发。
      Timer(const Duration(milliseconds: 150), () {
        if (WidgetsBinding.instance.lifecycleState !=
            AppLifecycleState.resumed) {
          _hide();
        }
      });
    }
  }

  List<_Entry> get _filtered {
    if (_searchCtrl.text.trim().isEmpty) return _entries;
    final String q = _searchCtrl.text.trim().toLowerCase();
    return _entries
        .where(
          (_Entry e) =>
              e.title.toLowerCase().contains(q) ||
              e.username.toLowerCase().contains(q) ||
              e.url.toLowerCase().contains(q),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final List<_Entry> list = _filtered;
    final int selected = list.isEmpty
        ? 0
        : _selectedIndex.clamp(0, list.length - 1);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: CallbackShortcuts(
        bindings: <ShortcutActivator, VoidCallback>{
          // 兜底（焦点在列表项等非搜索框控件时）。
          const SingleActivator(LogicalKeyboardKey.escape): () =>
              _hide(restoreTarget: true),
        },
        child: Container(
          decoration: BoxDecoration(
            color: ThemeConfig.fillColor,
            borderRadius: BorderRadius.circular(ThemeConfig.radiusCard),
            border: Border.all(color: ThemeConfig.dividerColor),
          ),
          child: Column(
            children: <Widget>[
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
                child: TextField(
                  controller: _searchCtrl,
                  focusNode: _searchFocus,
                  autofocus: true,
                  style: const TextStyle(
                    color: ThemeConfig.textColor,
                    fontSize: 15,
                  ),
                  decoration: InputDecoration(
                    hintText: '搜索账号…',
                    prefixIcon: const Icon(Icons.search, size: 18),
                    suffixIcon: _searchCtrl.text.isEmpty
                        ? null
                        : IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            onPressed: () {
                              _searchCtrl.clear();
                              _searchFocus.requestFocus();
                            },
                          ),
                  ),
                ),
              ),
              if (_loaded && _locked)
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: FilledButton.icon(
                    onPressed: _authenticating ? null : _unlockApp,
                    icon: const Icon(Icons.lock_outline),
                    label: Text(_authenticating ? '验证中…' : '解锁 KeyRing'),
                  ),
                ),
              if (_loaded && !_locked && _lockedWorkspaces.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: Wrap(
                    spacing: 8,
                    children: [
                      for (final w in _lockedWorkspaces)
                        ActionChip(
                          avatar: const Icon(Icons.lock_outline, size: 16),
                          label: Text(w['name'] as String),
                          onPressed: () => _unlockWorkspace(w),
                        ),
                    ],
                  ),
                ),
              Expanded(
                child: !_loaded
                    ? const Center(
                        child: SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : list.isEmpty
                    ? const Center(
                        child: Text(
                          '没有可用账号，请搜索或解锁工作区',
                          style: TextStyle(
                            color: ThemeConfig.secondaryTextColor,
                            fontSize: ThemeConfig.fontSizeCaption,
                          ),
                        ),
                      )
                    : ListView.builder(
                        controller: _scrollCtrl,
                        itemCount: list.length,
                        itemBuilder: (BuildContext context, int index) {
                          final _Entry e = list[index];
                          return _EntryTile(
                            entry: e,
                            highlighted: index == selected,
                            onTap: () {
                              _pokeIdleTimer();
                              _fill(e);
                            },
                            onHover: (bool hovering) {
                              if (hovering && selected != index) {
                                setState(() => _selectedIndex = index);
                              }
                            },
                          );
                        },
                      ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: const BoxDecoration(
                  border: Border(
                    top: BorderSide(color: ThemeConfig.dividerColor),
                  ),
                ),
                child: Row(
                  children: <Widget>[
                    if (_footerMessage != null)
                      Expanded(
                        child: Text(
                          _footerMessage!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: ThemeConfig.dangerColor,
                            fontSize: 11,
                          ),
                        ),
                      )
                    else
                      const Text(
                        '↑↓ 选择 · ↵ 填充 · Esc 关闭',
                        style: TextStyle(
                          color: ThemeConfig.hintTextColor,
                          fontSize: 11,
                        ),
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
}

class _EntryTile extends StatelessWidget {
  const _EntryTile({
    required this.entry,
    required this.onTap,
    this.highlighted = false,
    this.onHover,
  });

  final _Entry entry;
  final VoidCallback onTap;
  final ValueChanged<bool>? onHover;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      child: Material(
        color: highlighted ? ThemeConfig.primarySoft : Colors.transparent,
        borderRadius: BorderRadius.circular(ThemeConfig.radiusSm),
        child: InkWell(
          onTap: onTap,
          onHover: onHover,
          borderRadius: BorderRadius.circular(ThemeConfig.radiusSm),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              children: <Widget>[
                const Icon(
                  Icons.key_outlined,
                  color: ThemeConfig.primaryColor,
                  size: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: <Widget>[
                      Text(
                        entry.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          color: ThemeConfig.textColor,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      if (entry.username.isNotEmpty)
                        Text(
                          entry.username,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: ThemeConfig.secondaryTextColor,
                            fontSize: 11.5,
                          ),
                        ),
                    ],
                  ),
                ),
                if (entry.workspace.isNotEmpty) ...<Widget>[
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 6,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: ThemeConfig.primarySoft,
                      borderRadius: BorderRadius.circular(ThemeConfig.radiusSm),
                    ),
                    child: Text(
                      entry.workspace,
                      style: const TextStyle(
                        color: ThemeConfig.primaryColor,
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
