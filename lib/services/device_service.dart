import 'dart:io';

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class DeviceService {
  DeviceService()
    : _storage = const FlutterSecureStorage(
        aOptions: AndroidOptions(encryptedSharedPreferences: true),
        iOptions: IOSOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
          groupId: 'group.com.siye.key_ring',
        ),
        mOptions: MacOsOptions(
          accessibility: KeychainAccessibility.first_unlock_this_device,
          groupId: 'group.com.siye.key_ring',
        ),
      );

  static const String _deviceIdKey = 'device_id_v1';
  static const String _deviceNameKey = 'device_name_v1';
  final FlutterSecureStorage _storage;

  Future<String> getOrCreateDeviceId() async {
    try {
      // Try secure storage first (works in Release builds with proper entitlements)
      String? id = await _storage.read(key: _deviceIdKey);
      if (id == null) {
        id = const Uuid().v4();
        await _storage.write(key: _deviceIdKey, value: id);
      }
      return id;
    } catch (e) {
      // Fallback to SharedPreferences for Debug builds without keychain access
      print('Secure storage unavailable, using SharedPreferences: $e');
      final prefs = await SharedPreferences.getInstance();
      String? id = prefs.getString(_deviceIdKey);
      if (id == null) {
        id = const Uuid().v4();
        await prefs.setString(_deviceIdKey, id);
      }
      return id;
    }
  }

  /// Get platform type as a short string (e.g., "Android", "macOS", "iOS")
  String getPlatformType() {
    if (Platform.isAndroid) return 'Android';
    if (Platform.isIOS) return 'iOS';
    if (Platform.isMacOS) return 'macOS';
    if (Platform.isWindows) return 'Windows';
    if (Platform.isLinux) return 'Linux';
    return 'Unknown';
  }

  /// Get or create a friendly device name (e.g., "Android-Pixel", "macOS-MacBook")
  Future<String> getOrCreateDeviceName() async {
    try {
      // Try to read existing device name
      String? name = await _storage.read(key: _deviceNameKey);
      if (name != null && name.isNotEmpty) {
        return name;
      }

      // Generate a new friendly name
      final platformType = getPlatformType();
      final deviceId = await getOrCreateDeviceId();
      // Use first 6 characters of device ID as a short identifier
      final shortId = deviceId.substring(0, 6).toUpperCase();
      name = '$platformType-$shortId';

      await _storage.write(key: _deviceNameKey, value: name);
      return name;
    } catch (e) {
      // Fallback to SharedPreferences
      final prefs = await SharedPreferences.getInstance();
      String? name = prefs.getString(_deviceNameKey);
      if (name != null && name.isNotEmpty) {
        return name;
      }

      final platformType = getPlatformType();
      final deviceId = await getOrCreateDeviceId();
      final shortId = deviceId.substring(0, 6).toUpperCase();
      name = '$platformType-$shortId';

      await prefs.setString(_deviceNameKey, name);
      return name;
    }
  }
}
