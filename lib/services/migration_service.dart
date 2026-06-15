import 'database_backup_service.dart';
import 'password_repository.dart';
import 'vault_metadata_service.dart';

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
    if (metadata.hasExplicitVaultVersion) {
      return metadata;
    }

    if (_repository.itemsNotifier.value.isEmpty) {
      await _metadataService.markCompatibilityPrepared(needsMigration: false);
      return _metadataService.load();
    }

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
