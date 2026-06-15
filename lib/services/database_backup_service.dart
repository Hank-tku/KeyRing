import 'dart:io';

import 'package:path/path.dart' as p;

class DatabaseBackupService {
  Future<String?> createLegacyBackup(
    String databasePath,
    int fromVersion,
  ) async {
    final File database = File(databasePath);
    if (!await database.exists()) {
      return null;
    }

    final DateTime now = DateTime.now();
    final String timestamp =
        '${now.year.toString().padLeft(4, '0')}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}-'
        '${now.hour.toString().padLeft(2, '0')}'
        '${now.minute.toString().padLeft(2, '0')}'
        '${now.second.toString().padLeft(2, '0')}';
    final String backupPath = p.join(
      p.dirname(databasePath),
      '${p.basename(databasePath)}.backup-v$fromVersion-$timestamp',
    );

    await database.copy(backupPath);
    return backupPath;
  }
}
