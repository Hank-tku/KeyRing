// login_screen.dart
import 'package:flutter/material.dart';
import 'package:local_auth/local_auth.dart';
import 'auth_service.dart';
import 'passcode_screen.dart';
// import 'package:flutter_native_splash/flutter_native_splash.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key, required this.onUnlocked});

  final VoidCallback onUnlocked;

  @override
  _LoginScreenState createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final AuthService _authService = AuthService();
  bool _isCheckingBiometrics = true;
  bool _canUseFingerprint = false;

  @override
  void initState() {
    super.initState();
    _checkBiometricSupport();
    // Future.delayed(Duration(seconds: 1000), () {
    //   FlutterNativeSplash.remove();
    // });
  }

  // 在初始化时检查设备是否支持指纹
  Future<void> _checkBiometricSupport() async {
    final bool canAuthenticate = await _authService.canUseBiometrics();
    setState(() {
      _canUseFingerprint = canAuthenticate;
      _isCheckingBiometrics = false;
    });
    // 如果支持，可以尝试自动弹出指纹验证（根据你的UX设计决定）
    // if (_canUseFingerprint) {
    //   _authenticateWithFingerprint();
    // }
  }

  Future<void> _authenticateWithFingerprint() async {
    try {
      // 1. 检查设备支持
      final bool canAuthenticate = await _authService.canUseBiometrics();
      if (!canAuthenticate) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('设备不支持指纹识别')));
        return;
      }

      // 2. 获取可用识别类型（调试用）
      final List<BiometricType> availableBiometrics = await _authService
          .getAvailableBiometrics();

      // 3. 执行认证
      final bool authenticated = await _authService
          .authenticateWithBiometrics();

      // 4. 处理结果
      if (authenticated) {
        widget.onUnlocked(); // 注意：小写 w
      } else {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('验证失败，请重试或使用密码解锁')));
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('认证出错: $e')));
    }
  }

  void _authenticateWithPasscode() {
    // 导航到密码解锁界面
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => PasscodeScreen(
          onCorrect: () {
            // 密码验证成功
            // Navigator.of(context).pop();
            widget.onUnlocked();
            // Navigator.of(context).pushReplacementNamed('/home');
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.lock, color: Color(0xFF2DD4BF), size: 68),
            const Text(
              'KeyRing',
              style: TextStyle(
                fontSize: 30,
                color: Color(0xFFF3F4F6),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 10),
            const Text(
              '安全地管理您的所有密码',
              style: TextStyle(fontSize: 16, color: Color(0xFF9CA3AF)),
            ),
            const SizedBox(height: 50),
            if (_isCheckingBiometrics) ...{
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              const Text('检查安全验证方式...'),
            } else ...{
              // 优先显示指纹解锁按钮（如果设备支持）
              if (_canUseFingerprint) ...{
                ElevatedButton.icon(
                  onPressed: _authenticateWithFingerprint,
                  icon: const Icon(Icons.fingerprint),
                  label: const Text('指纹解锁'),
                ),
                const SizedBox(height: 20),
                TextButton(
                  onPressed: _authenticateWithPasscode,
                  child: const Text('使用密码解锁'),
                ),
              } else ...{
                // 设备不支持指纹，直接显示密码解锁
                ElevatedButton(
                  onPressed: _authenticateWithPasscode,
                  child: const Text('密码解锁'),
                ),
              },
            },
          ],
        ),
      ),
    );
  }
}
