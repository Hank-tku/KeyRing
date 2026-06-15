import '../../models/password_item.dart';

enum SyncResolution { add, update, skip }

class SyncConflictResolver {
  SyncResolution resolve({
    required PasswordItem remote,
    required PasswordItem? local,
  }) {
    if (local == null) {
      return SyncResolution.add;
    }
    if (remote.updatedAt.isAfter(local.updatedAt)) {
      return SyncResolution.update;
    }
    return SyncResolution.skip;
  }

  PasswordItem? findLocal(List<PasswordItem> localItems, String id) {
    for (final PasswordItem item in localItems) {
      if (item.id == id) {
        return item;
      }
    }
    return null;
  }
}
