import 'database_backup_service.dart';
import 'password_repository.dart';
import 'vault_metadata_service.dart';

/// 结构迁移守卫：在任何 DB 版本升级**之前**做整库文件备份。
///
/// 必须在 `PasswordRepository.init()`（触发 onUpgrade）之前运行。
class MigrationService {
  MigrationService({
    required PasswordRepository repository,
    VaultMetadataService? metadataService,
    DatabaseBackupService? backupService,
  }) : _repository = repository,
       _metadataService = metadataService ?? VaultMetadataService(),
       _backupService = backupService ?? DatabaseBackupService();

  final PasswordRepository _repository;
  final VaultMetadataService _metadataService;
  final DatabaseBackupService _backupService;

  Future<VaultMetadata> prepareCompatibility() async {
    final VaultMetadata metadata = await _metadataService.load();
    if (metadata.vaultVersion >= VaultMetadataService.currentVaultVersion) {
      return metadata;
    }

    // 即将发生 v(n → n+1) 结构迁移：先备份库文件（不存在则跳过，如全新安装）。
    final String? backupPath = await _backupService.createLegacyBackup(
      await _repository.databasePath(),
      metadata.vaultVersion,
    );
    await _metadataService.markCompatibilityPrepared(
      legacyBackupPath: backupPath,
    );
    return _metadataService.load();
  }
}
