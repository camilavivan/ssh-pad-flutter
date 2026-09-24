import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// Persisted TOFU trust entry for an SSH/SFTP host.
class TrustedHostKey {
  const TrustedHostKey({
    required this.host,
    required this.port,
    required this.keyType,
    required this.fingerprint,
    required this.trustedAt,
  });

  final String host;
  final int port;
  final String keyType;

  /// OpenSSH-style fingerprint, e.g. `SHA256:base64…`
  final String fingerprint;
  final DateTime trustedAt;

  String get identity => '$host:$port';

  Map<String, dynamic> toJson() => {
        'host': host,
        'port': port,
        'keyType': keyType,
        'fingerprint': fingerprint,
        'trustedAt': trustedAt.toIso8601String(),
      };

  factory TrustedHostKey.fromJson(Map<String, dynamic> json) {
    return TrustedHostKey(
      host: json['host'] as String? ?? '',
      port: (json['port'] as num?)?.toInt() ?? 22,
      keyType: json['keyType'] as String? ?? '',
      fingerprint: json['fingerprint'] as String? ?? '',
      trustedAt: DateTime.tryParse(json['trustedAt'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

const _kHostKeysKey = 'trusted_host_keys_v1';

/// TOFU host-key trust store (SharedPreferences JSON map).
class HostKeyStore {
  HostKeyStore(this._prefs);

  final SharedPreferences _prefs;

  Map<String, TrustedHostKey> loadAll() {
    final raw = _prefs.getString(_kHostKeysKey);
    if (raw == null || raw.isEmpty) return {};
    final map = jsonDecode(raw) as Map<String, dynamic>;
    return map.map(
      (k, v) => MapEntry(k, TrustedHostKey.fromJson(v as Map<String, dynamic>)),
    );
  }

  TrustedHostKey? lookup(String host, int port) {
    return loadAll()['$host:$port'];
  }

  Future<void> trust(TrustedHostKey entry) async {
    final all = loadAll();
    all[entry.identity] = entry;
    await _save(all);
  }

  Future<void> remove(String host, int port) async {
    final all = loadAll()..remove('$host:$port');
    await _save(all);
  }

  Future<void> _save(Map<String, TrustedHostKey> all) async {
    final encoded = jsonEncode(
      all.map((k, v) => MapEntry(k, v.toJson())),
    );
    await _prefs.setString(_kHostKeysKey, encoded);
  }
}
