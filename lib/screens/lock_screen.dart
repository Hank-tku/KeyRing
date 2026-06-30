import 'dart:async';

import 'package:flutter/material.dart';

import '../utils/theme_config.dart';
import 'auth_service.dart';
import 'passcode_screen.dart';

/// 应用锁定/解锁页。
///
/// 解锁方式委托给系统 local_auth（指纹 / 设备密码）。
/// 进入页面后自动唤起认证，无需用户手动点击。
/// 为缓解暴力尝试，对失败做计数与临时冷却。
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onUnlocked});

  final VoidCallback onUnlocked;

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();
  bool _isCheckingBiometrics = true;
  bool _canUseFingerprint = false;
  bool _autoAuthTried = false;

  // 失败计数与冷却（缓解暴力重试）。
  int _failCount = 0;
  bool _coolingDown = false;
  int _cooldownSeconds = 0;
  Timer? _cooldownTimer;

  static const int _maxFailures = 5;
  static const int _cooldownDurationSeconds = 30;

  @override
  void initState() {
    super.initState();
    _checkBiometricSupport();
  }

  @override
  void dispose() {
    _cooldownTimer?.cancel();
    super.dispose();
  }

  Future<void> _checkBiometricSupport() async {
    final bool canAuthenticate = await _authService.canUseBiometrics();
    if (!mounted) return;
    setState(() {
      _canUseFingerprint = canAuthenticate;
      _isCheckingBiometrics = false;
    });
    // 检测完成后自动唤起认证。
    if (canAuthenticate) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _autoAuthenticate());
    }
  }

  /// 打开页面后默认自动唤起认证（指纹优先，否则系统密码）。
  Future<void> _autoAuthenticate() async {
    if (_autoAuthTried || !mounted || _coolingDown) return;
    _autoAuthTried = true;
    if (_canUseFingerprint) {
      await _authenticateWithFingerprint();
    } else {
      _authenticateWithPasscode();
    }
  }

  void _startCooldown() {
    setState(() {
      _coolingDown = true;
      _cooldownSeconds = _cooldownDurationSeconds;
    });
    _cooldownTimer?.cancel();
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (Timer t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() {
        _cooldownSeconds--;
        if (_cooldownSeconds <= 0) {
          _coolingDown = false;
          _failCount = 0;
          t.cancel();
        }
      });
    });
  }

  void _onAuthResult(bool success) {
    if (success) {
      widget.onUnlocked();
    } else if (mounted) {
      setState(() => _failCount++);
      if (_failCount >= _maxFailures) {
        _startCooldown();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('尝试次数过多，请 $_cooldownDurationSeconds 秒后再试'),
            backgroundColor: ThemeConfig.warningColor,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('验证失败，请重试'),
            backgroundColor: ThemeConfig.dangerColor,
          ),
        );
      }
    }
  }

  Future<void> _authenticateWithFingerprint() async {
    if (_coolingDown) return;
    try {
      final bool authenticated = await _authService.authenticateWithBiometrics();
      if (!mounted) return;
      _onAuthResult(authenticated);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('认证出错: $e')),
      );
    }
  }

  void _authenticateWithPasscode() {
    if (_coolingDown) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (BuildContext context) => PasscodeScreen(
          onCorrect: widget.onUnlocked,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: <Color>[
              ThemeConfig.mainBgColor,
              Color(0xFF0B0D12),
            ],
          ),
        ),
        child: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: ThemeConfig.space32,
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: <Widget>[
                  // 钥匙环 logo
                  _buildLogo(),
                  const SizedBox(height: ThemeConfig.space20),
                  // 双色标题
                  RichText(
                    text: const TextSpan(
                      style: TextStyle(
                        fontSize: 32,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 2,
                        color: ThemeConfig.textColor,
                      ),
                      children: <InlineSpan>[
                        TextSpan(text: 'Key'),
                        TextSpan(
                          text: 'Ring',
                          style: TextStyle(color: ThemeConfig.primaryColor),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: ThemeConfig.space8),
                  const Text(
                    '安全地管理您的所有密码',
                    style: TextStyle(
                      fontSize: ThemeConfig.fontSizeSubtitle,
                      color: ThemeConfig.secondaryTextColor,
                    ),
                  ),
                  const SizedBox(height: ThemeConfig.space32 * 2),
                  if (_isCheckingBiometrics)
                    const _AutoAuthHint()
                  else
                    _buildUnlockButtons(),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// 钥匙环 logo：圆环 + 钥匙柄 + 齿，呼应应用名。
  Widget _buildLogo() {
    return Container(
      width: 92,
      height: 92,
      decoration: BoxDecoration(
        color: ThemeConfig.primarySoft,
        borderRadius: BorderRadius.circular(ThemeConfig.space24),
        border: Border.all(
          color: ThemeConfig.primaryColor.withValues(alpha: 0.3),
        ),
      ),
      alignment: Alignment.center,
      child: CustomPaint(
        size: const Size(52, 52),
        painter: _KeyRingLogoPainter(color: ThemeConfig.primaryColor),
      ),
    );
  }

  Widget _buildUnlockButtons() {
    final bool disabled = _coolingDown;
    final String? cooldownHint =
        disabled ? '($_cooldownSeconds 秒后可重试)' : null;

    return Column(
      children: <Widget>[
        if (_canUseFingerprint) ...<Widget>[
          // 指纹解锁：紧凑主按钮（不再全宽）
          SizedBox(
            width: 220,
            child: FilledButton.icon(
              onPressed: disabled ? null : _authenticateWithFingerprint,
              icon: const Icon(Icons.fingerprint),
              label: Text(
                cooldownHint != null ? '指纹解锁 $cooldownHint' : '指纹解锁',
                style: const TextStyle(
                  fontSize: ThemeConfig.fontSizeSubtitle,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: ThemeConfig.primaryColor,
                foregroundColor: const Color(0xFF0B0D12),
                disabledBackgroundColor:
                    ThemeConfig.primaryColor.withValues(alpha: 0.3),
                padding: const EdgeInsets.symmetric(vertical: ThemeConfig.space12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ThemeConfig.radiusMd),
                ),
              ),
            ),
          ),
          const SizedBox(height: ThemeConfig.space12),
          // 密码解锁：次级描边按钮
          SizedBox(
            width: 220,
            child: OutlinedButton.icon(
              onPressed: disabled ? null : _authenticateWithPasscode,
              icon: const Icon(Icons.key_outlined),
              label: const Text('密码解锁'),
              style: OutlinedButton.styleFrom(
                foregroundColor: ThemeConfig.textColor,
                side: const BorderSide(color: ThemeConfig.dividerColor),
                padding: const EdgeInsets.symmetric(vertical: ThemeConfig.space12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ThemeConfig.radiusMd),
                ),
              ),
            ),
          ),
        ] else
          SizedBox(
            width: 220,
            child: FilledButton.icon(
              onPressed: disabled ? null : _authenticateWithPasscode,
              icon: const Icon(Icons.key_outlined),
              label: Text(
                cooldownHint != null ? '密码解锁 $cooldownHint' : '密码解锁',
                style: const TextStyle(
                  fontSize: ThemeConfig.fontSizeSubtitle,
                  fontWeight: FontWeight.w600,
                ),
              ),
              style: FilledButton.styleFrom(
                backgroundColor: ThemeConfig.primaryColor,
                foregroundColor: const Color(0xFF0B0D12),
                disabledBackgroundColor:
                    ThemeConfig.primaryColor.withValues(alpha: 0.3),
                padding: const EdgeInsets.symmetric(vertical: ThemeConfig.space12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(ThemeConfig.radiusMd),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// 自动唤起认证时的脉冲提示。
class _AutoAuthHint extends StatefulWidget {
  const _AutoAuthHint();

  @override
  State<_AutoAuthHint> createState() => _AutoAuthHintState();
}

class _AutoAuthHintState extends State<_AutoAuthHint>
    with TickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: <Widget>[
        Row(
          mainAxisSize: MainAxisSize.min,
          children: List<Widget>.generate(3, (int i) {
            return AnimatedBuilder(
              animation: _controller,
              builder: (BuildContext context, Widget? child) {
                // 三个点错峰闪烁
                final double t =
                    (_controller.value + i * 0.33) % 1.0;
                final double opacity = 0.3 + 0.7 * (0.5 - (t - 0.5).abs());
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 3),
                  child: Opacity(
                    opacity: opacity.clamp(0.2, 1.0),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                        color: ThemeConfig.primaryColor,
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                );
              },
            );
          }),
        ),
        const SizedBox(height: ThemeConfig.space12),
        const Text(
          '正在自动唤起认证...',
          style: TextStyle(color: ThemeConfig.secondaryTextColor),
        ),
      ],
    );
  }
}

/// 钥匙环 logo 绘制：一个环 + 钥匙柄 + 两个齿。
class _KeyRingLogoPainter extends CustomPainter {
  _KeyRingLogoPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.075
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    // 圆环（钥匙头）
    final double cx = size.width * 0.36;
    final double cy = size.height * 0.34;
    final double r = size.width * 0.2;
    canvas.drawCircle(Offset(cx, cy), r, paint);
    canvas.drawCircle(Offset(cx, cy), r * 0.38, paint);

    // 钥匙柄（从环延伸到右下）
    final double startX = cx + r * 0.7;
    final double startY = cy + r * 0.7;
    final double endX = size.width * 0.9;
    final double endY = size.height * 0.88;
    canvas.drawLine(Offset(startX, startY), Offset(endX, endY), paint);

    // 两个齿
    canvas.drawLine(
      Offset(endX - size.width * 0.12, endY - size.width * 0.12),
      Offset(endX - size.width * 0.04, endY - size.width * 0.04),
      paint,
    );
    canvas.drawLine(
      Offset(endX - size.width * 0.2, endY - size.width * 0.04),
      Offset(endX - size.width * 0.14, endY + size.width * 0.04),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _KeyRingLogoPainter oldDelegate) =>
      oldDelegate.color != color;
}
