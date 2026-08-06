import '../entities/watch_item.dart';

/// Reads/writes the Home dashboard's "What to watch" strip. Every signed-in
/// user can read; only platform admins can write — enforced server-side by
/// RLS (see migration `20260806000000_watch_items.sql`), not just by which
/// screens the client happens to show the upload button on.
abstract class WatchRepository {
  Stream<List<WatchItem>> watchItems();
  Future<void> upsertItem(WatchItem item);
  Future<void> deleteItem(String id);
}
