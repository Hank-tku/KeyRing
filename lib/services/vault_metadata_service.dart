import 'package:shared_preferences/shared_preferences.dart';

class VaultMetadata {
  const VaultMetadata({
    required this.vaultVersion,
    required this.protocolVersion,
    required this.hasExplicitVaultVersion,
    required this.needsMigration,
    this.legacyBackupPath,
  });

  final int vaultVersion;
  final int protocolVersion;
  final bool hasExplicitVaultVersion;
  final bool needsMigration;
  final String? legacyBackupPath;
}

class VaultMetadataService {
  static const int currentVaultVersion = 1;
  static const int currentProtocolVersion = 1;

  static const String _vaultVersionKey = 'vault_version';
  static const String _needsMigrationKey = 'vault_needs_migration';
  static const String _legacyBackupPathKey = 'vault_legacy_backup_path';

  Future<VaultMetadata> load() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    final int? storedVaultVersion = prefs.getInt(_vaultVersionKey);
    final bool hasExplicitVaultVersion = storedVaultVersion != null;

    return VaultMetadata(
      vaultVersion: storedVaultVersion ?? currentVaultVersion,
      protocolVersion: currentProtocolVersion,
      hasExplicitVaultVersion: hasExplicitVaultVersion,
      needsMigration:
          prefs.getBool(_needsMigrationKey) ?? !hasExplicitVaultVersion,
      legacyBackupPath: prefs.getString(_legacyBackupPathKey),
    );
  }

  Future<void> markCompatibilityPrepared({
    bool needsMigration = true,
    String? legacyBackupPath,
  }) async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_vaultVersionKey, currentVaultVersion);
    await prefs.setBool(_needsMigrationKey, needsMigration);
    if (legacyBackupPath != null) {
      await prefs.setString(_legacyBackupPathKey, legacyBackupPath);
    }
  }

  Future<void> clearMigrationNeeded() async {
    final SharedPreferences prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_needsMigrationKey, false);
  }
}
