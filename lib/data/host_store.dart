import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'host_profile.dart';

const _kHostsKey = 'host_profiles_v1';

class HostStore {
  HostStore(this._prefs);

  final SharedPreferences _prefs;

  List<HostProfile> loadAll() {
    final raw = _prefs.getString(_kHostsKey);
    if (raw == null || raw.isEmpty) return [];
    final list = jsonDecode(raw) as List<dynamic>;
    return list
        .map((e) => HostProfile.fromJson(e as Map<String, dynamic>))
        .toList();
  }

  Future<void> saveAll(List<HostProfile> hosts) async {
    final encoded = jsonEncode(hosts.map((h) => h.toJson()).toList());
    await _prefs.setString(_kHostsKey, encoded);
  }

  Future<void> upsert(HostProfile host) async {
    final all = loadAll();
    final i = all.indexWhere((h) => h.id == host.id);
    if (i >= 0) {
      all[i] = host;
    } else {
      all.add(host);
    }
    await saveAll(all);
  }

  Future<void> delete(String id) async {
    final all = loadAll()..removeWhere((h) => h.id == id);
    await saveAll(all);
  }
}

final sharedPreferencesProvider = Provider<SharedPreferences>((ref) {
  throw UnimplementedError('Override with SharedPreferences instance');
});

final hostStoreProvider = Provider<HostStore>((ref) {
  return HostStore(ref.watch(sharedPreferencesProvider));
});

final hostListProvider =
    StateNotifierProvider<HostListNotifier, List<HostProfile>>((ref) {
  return HostListNotifier(ref.watch(hostStoreProvider));
});

class HostListNotifier extends StateNotifier<List<HostProfile>> {
  HostListNotifier(this._store) : super(_store.loadAll());

  final HostStore _store;

  Future<void> upsert(HostProfile host) async {
    await _store.upsert(host);
    state = _store.loadAll();
  }

  Future<void> delete(String id) async {
    await _store.delete(id);
    state = _store.loadAll();
  }

  void reload() {
    state = _store.loadAll();
  }
}
