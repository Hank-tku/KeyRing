// passcode_screen.dart
import 'package:flutter/material.dart';
import 'auth_service.dart'; // 导入您的认证服务

class PasscodeScreen extends StatefulWidget {
  final VoidCallback onCorrect;

  const PasscodeScreen({super.key, required this.onCorrect});

  @override
  State<PasscodeScreen> createState() => _PasscodeScreenState();
}

class _PasscodeScreenState extends State<PasscodeScreen> {
  final AuthService _authService = AuthService();
  bool _isVerifying = false;

  Future<void> _verifySystemPassword() async {
    setState(() {
      _isVerifying = true;
    });

    try {
      // 调用系统密码验证（注意：这里设置 biometricOnly: false 允许使用设备密码）
      final bool authenticated = await _authService
          .authenticateWithSystemPassword();

      if (authenticated) {
        // 验证成功，先关闭当前页面，再回调
        Navigator.of(context).pop();
        widget.onCorrect();
      } else {
        // 验证失败
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('密码验证失败，请重试')));
      }
    } catch (e) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('验证出错: $e')));
    } finally {
      setState(() {
        _isVerifying = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    // 页面打开后自动触发系统密码验证
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _verifySystemPassword();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('系统密码验证'),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (_isVerifying) ...{
              const CircularProgressIndicator(),
              const SizedBox(height: 20),
              const Text('等待系统密码验证...'),
            } else ...{
              const Icon(Icons.lock, size: 64),
              const SizedBox(height: 20),
              const Text('需要验证系统密码'),
              const SizedBox(height: 20),
              ElevatedButton(
                onPressed: _verifySystemPassword,
                child: const Text('重新验证系统密码'),
              ),
            },
          ],
        ),
      ),
    );
  }
}
