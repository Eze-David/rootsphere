import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../../core/config/supabase_config.dart';
import '../../../../core/storage/preferences_provider.dart';
import '../../data/repositories/watch_repository_local.dart';
import '../../data/repositories/watch_repository_supabase.dart';
import '../../data/services/watch_storage_service.dart';
import '../../domain/entities/watch_item.dart';
import '../../domain/repositories/watch_repository.dart';

/// Watch-items repository: Supabase-backed when configured, local
/// (SharedPreferences) otherwise.
final watchRepositoryProvider = Provider<WatchRepository>((ref) {
  if (SupabaseConfig.isReady) {
    return WatchRepositorySupabase(SupabaseConfig.client);
  }
  final prefs = ref.watch(sharedPreferencesProvider);
  return WatchRepositoryLocal(prefs);
});

final watchStorageServiceProvider = Provider<WatchStorageService>((ref) {
  return WatchStorageService();
});

/// The "What to watch" strip, live-updating.
final watchItemsProvider = StreamProvider<List<WatchItem>>((ref) {
  return ref.watch(watchRepositoryProvider).watchItems();
});
