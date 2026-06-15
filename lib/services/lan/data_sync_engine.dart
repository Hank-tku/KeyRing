import 'package:flutter/foundation.dart';

import '../../models/password_item.dart';
import '../password_repository.dart';
import 'sync_conflict_resolver.dart';

class DataSyncEngine {
  DataSyncEngine(this._repository, {SyncConflictResolver? conflictResolver})
    : _conflictResolver = conflictResolver ?? SyncConflictResolver();

  final PasswordRepository _repository;
  final SyncConflictResolver _conflictResolver;

  Future<void> syncItemByTimestamp(PasswordItem remoteItem) async {
    final List<PasswordItem> localItems = _repository.itemsNotifier.value;
    final PasswordItem? local = _conflictResolver.findLocal(
      localItems,
      remoteItem.id,
    );

    switch (_conflictResolver.resolve(remote: remoteItem, local: local)) {
      case SyncResolution.add:
        await _repository.upsertPreserveTimestamps(remoteItem);
        debugPrint('Added new item: ${remoteItem.id}');
        break;
      case SyncResolution.update:
        await _repository.upsertPreserveTimestamps(remoteItem);
        debugPrint('Updated item: ${remoteItem.id}');
        break;
      case SyncResolution.skip:
        debugPrint('Local item is newer or same, skipping: ${remoteItem.id}');
    }
  }

  Future<void> syncMultipleItems(List<PasswordItem> remoteItems) async {
    int addedCount = 0;
    int updatedCount = 0;
    int skippedCount = 0;

    for (final remoteItem in remoteItems) {
      final List<PasswordItem> localItems = _repository.itemsNotifier.value;
      final PasswordItem? local = _conflictResolver.findLocal(
        localItems,
        remoteItem.id,
      );

      switch (_conflictResolver.resolve(remote: remoteItem, local: local)) {
        case SyncResolution.add:
          await _repository.upsertPreserveTimestamps(remoteItem);
          addedCount++;
          break;
        case SyncResolution.update:
          await _repository.upsertPreserveTimestamps(remoteItem);
          updatedCount++;
          break;
        case SyncResolution.skip:
          skippedCount++;
      }
    }

    debugPrint(
      'Sync completed: $addedCount added, $updatedCount updated, $skippedCount skipped',
    );
  }

  List<Map<String, dynamic>> getLocalDataForSync() {
    return _repository.itemsNotifier.value.map((item) => item.toMap()).toList();
  }

  int getLocalItemCount() {
    return _repository.itemsNotifier.value.length;
  }
}
