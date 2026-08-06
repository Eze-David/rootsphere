import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../domain/entities/watch_item.dart';
import '../../domain/repositories/watch_repository.dart';

/// SharedPreferences-backed [WatchRepository] used when Supabase is not
/// configured. There's no local admin concept (local mode has no real
/// accounts), so the strip simply stays empty until Supabase is connected.
class WatchRepositoryLocal implements WatchRepository {
  WatchRepositoryLocal(this._prefs);

  final SharedPreferences _prefs;
  StreamController<List<WatchItem>>? _controller;

  static const String _key = 'watch_items_v1';

  List<WatchItem> _read() {
    final String? raw = _prefs.getString(_key);
    if (raw == null || raw.isEmpty) return <WatchItem>[];
    try {
      final List<dynamic> list = jsonDecode(raw) as List<dynamic>;
      return list
          .map((e) => WatchItem.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (_) {
      return <WatchItem>[];
    }
  }

  Future<void> _write(List<WatchItem> items) async {
    await _prefs.setString(
      _key,
      jsonEncode(items.map((i) => i.toJson()).toList()),
    );
    _controller?.add(items);
  }

  @override
  Stream<List<WatchItem>> watchItems() {
    final controller =
        _controller ??= StreamController<List<WatchItem>>.broadcast();
    scheduleMicrotask(() => controller.add(_read()));
    return controller.stream;
  }

  @override
  Future<void> upsertItem(WatchItem item) async {
    final List<WatchItem> items = _read();
    final int idx = items.indexWhere((i) => i.id == item.id);
    if (idx >= 0) {
      items[idx] = item;
    } else {
      items.add(item);
    }
    await _write(items);
  }

  @override
  Future<void> deleteItem(String id) async {
    final List<WatchItem> items = _read()..removeWhere((i) => i.id == id);
    await _write(items);
  }
}
