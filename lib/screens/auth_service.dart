// auth_service.dart
import 'package:local_auth/local_auth.dart';
// 删除旧的导入，替换为以下两行
import 'package:local_auth_android/local_auth_android.dart';
import 'package:local_auth_darwin/local_auth_darwin.dart';

class AuthService {
  final LocalAuthentication _localAuth = LocalAuthentication();

  // 检查设备是否支持生物识别或密码验证
  Future<bool> canUseBiometrics() async {
    try {
      return await _localAuth.canCheckBiometrics;
    } catch (e) {
      return false;
    }
  }

  // auth_service.dart
  Future<bool> authenticateWithBiometrics() async {
    try {
      // 定义中文提示信息
      const androidAuthMessages = AndroidAuthMessages(
        cancelButton: '取消',
        goToSettingsButton: '去设置',
        goToSettingsDescription: '需要设置指纹以进行验证',
        biometricNotRecognized: '指纹未识别，请重试',
        biometricHint: '',
        biometricSuccess: '指纹识别成功',
        signInTitle: '验证身份',
      );

      final bool authenticated = await _localAuth.authenticate(
        localizedReason: '请进行身份验证以解锁应用', // 认证理由
        authMessages: [androidAuthMessages], // 应用自定义提示
        options: const AuthenticationOptions(
          biometricOnly: true,
          useErrorDialogs: true,
          stickyAuth: true,
        ),
      );

      return authenticated;
    } catch (e) {
      return false;
    }
  }

  // 新增：执行系统密码验证（允许使用设备密码）
  Future<bool> authenticateWithSystemPassword() async {
    try {
      return await _localAuth.authenticate(
        localizedReason: '请使用系统密码解锁应用',
        options: const AuthenticationOptions(
          biometricOnly: false, // 设置为 false 允许使用设备密码
          useErrorDialogs: true,
          stickyAuth: true,
        ),
      );
    } catch (e) {
      return false;
    }
  }

  // 获取可用的生物识别类型
  Future<List<BiometricType>> getAvailableBiometrics() async {
    try {
      return await _localAuth.getAvailableBiometrics();
    } catch (e) {
      return [];
    }
  }
}
