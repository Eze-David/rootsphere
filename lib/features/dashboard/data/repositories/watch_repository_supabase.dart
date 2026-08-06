import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../../core/error/failure.dart';
import '../../domain/entities/watch_item.dart';
import '../../domain/repositories/watch_repository.dart';

/// Supabase-backed [WatchRepository]. RLS lets every signed-in user read the
/// table but only platform admins write to it (see
/// `20260806000000_watch_items.sql`).
class WatchRepositorySupabase implements WatchRepository {
  WatchRepositorySupabase(this._client);

  final SupabaseClient _client;

  SupabaseQueryBuilder get _items => _client.from('watch_items');

  @override
  Stream<List<WatchItem>> watchItems() {
    return _items
        .stream(primaryKey: <String>['id'])
        .order('sort_order')
        .map(
          (rows) => rows.map(WatchItem.fromJson).toList()
            ..sort((a, b) {
              final int bySort = a.sortOrder.compareTo(b.sortOrder);
              if (bySort != 0) return bySort;
              final DateTime ad = a.createdAt ?? DateTime(0);
              final DateTime bd = b.createdAt ?? DateTime(0);
              return bd.compareTo(ad);
            }),
        );
  }

  @override
  Future<void> upsertItem(WatchItem item) async {
    try {
      await _items.upsert(item.toJson());
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }

  @override
  Future<void> deleteItem(String id) async {
    try {
      await _items.delete().eq('id', id);
    } on PostgrestException catch (e) {
      throw ServerFailure(e.message);
    }
  }
}
