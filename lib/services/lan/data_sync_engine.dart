import '../../models/password_item.dart';
import '../password_repository.dart';

class DataSyncEngine {
  final PasswordRepository _repository;

  DataSyncEngine(this._repository);

  Future<void> syncItemByTimestamp(PasswordItem remoteItem) async {
    final List<PasswordItem> localItems = _repository.itemsNotifier.value;
    final PasswordItem? local = _findItemById(localItems, remoteItem.id);

    if (local == null) {
      await _repository.addItem(remoteItem);
      print('Added new item: ${remoteItem.id}');
    } else if (remoteItem.updatedAt.isAfter(local.updatedAt)) {
      await _repository.updateItem(remoteItem);
      print('Updated item: ${remoteItem.id}');
    } else {
      print('Local item is newer or same, skipping: ${remoteItem.id}');
    }
  }

  Future<void> syncMultipleItems(List<PasswordItem> remoteItems) async {
    int addedCount = 0;
    int updatedCount = 0;
    int skippedCount = 0;

    for (final remoteItem in remoteItems) {
      final List<PasswordItem> localItems = _repository.itemsNotifier.value;
      final PasswordItem? local = _findItemById(localItems, remoteItem.id);

      if (local == null) {
        await _repository.addItem(remoteItem);
        addedCount++;
      } else if (remoteItem.updatedAt.isAfter(local.updatedAt)) {
        await _repository.updateItem(remoteItem);
        updatedCount++;
      } else {
        skippedCount++;
      }
    }

    print(
      'Sync completed: $addedCount added, $updatedCount updated, $skippedCount skipped',
    );
  }

  List<Map<String, dynamic>> getLocalDataForSync() {
    return _repository.itemsNotifier.value.map((item) => item.toMap()).toList();
  }

  int getLocalItemCount() {
    return _repository.itemsNotifier.value.length;
  }

  PasswordItem? _findItemById(List<PasswordItem> items, String id) {
    for (final item in items) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }
}
