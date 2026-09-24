import 'dart:async';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';

import '../../data/host_profile.dart';
import '../session/session_log.dart';
import 'ssh_connector.dart';

/// One authenticated [SSHClient] per host profile id.
///
/// Terminal tabs open additional shell channels; Files uses [SSHClient.sftp]
/// on the **same** client. Disconnecting the host tears down the transport
/// and every channel attached to it.
class SshConnectionHub {
  final Map<String, _HubEntry> _entries = {};

  /// Stable key: [HostProfile.id] (shared across SSH ↔ SFTP protocol flip).
  String keyFor(HostProfile profile) => profile.id;

  bool isConnected(String hostId) {
    final e = _entries[hostId];
    return e != null && !e.client.isClosed;
  }

  SSHClient? clientOf(String hostId) {
    final e = _entries[hostId];
    if (e == null || e.client.isClosed) return null;
    return e.client;
  }

  /// Ensure a live [SSHClient] for [profile]. Reuses an existing connection
  /// when present; otherwise TCP+auth via [SshConnector].
  Future<SSHClient> ensureClient(HostProfile profile) async {
    final key = keyFor(profile);
    final existing = _entries[key];
    if (existing != null && !existing.client.isClosed) {
      sessionLog.add(
        'Reusing SSH connection ${profile.host}:${profile.port} '
        '(shells=${existing.shellRefs} sftp=${existing.sftpRefs})',
      );
      return existing.client;
    }
    if (existing != null) {
      _entries.remove(key);
    }

    final client = await SshConnector.connect(profile);
    final entry = _HubEntry(client: client, profile: profile);
    _entries[key] = entry;

    unawaited(
      client.done.then((_) {
        if (identical(_entries[key], entry)) {
          _entries.remove(key);
          sessionLog.add(
            'SSH connection closed ${profile.host}:${profile.port}',
          );
        }
      }),
    );

    return client;
  }

  void retainShell(String hostId) {
    final e = _entries[hostId];
    if (e == null) return;
    e.shellRefs++;
  }

  void retainSftp(String hostId) {
    final e = _entries[hostId];
    if (e == null) return;
    e.sftpRefs++;
  }

  /// Drop one shell ref. Closes the transport only when no shells/SFTP remain.
  Future<void> releaseShell(String hostId) async {
    final e = _entries[hostId];
    if (e == null) return;
    if (e.shellRefs > 0) e.shellRefs--;
    await _maybeClose(hostId);
  }

  /// Drop one SFTP ref. Does **not** close the transport while shells remain.
  Future<void> releaseSftp(String hostId) async {
    final e = _entries[hostId];
    if (e == null) return;
    if (e.sftpRefs > 0) e.sftpRefs--;
    await _maybeClose(hostId);
  }

  /// Force-close this host's SSHClient (all shells + SFTP die with it).
  Future<void> disconnect(String hostId) async {
    final e = _entries.remove(hostId);
    if (e == null) return;
    e.shellRefs = 0;
    e.sftpRefs = 0;
    try {
      e.client.close();
    } catch (err) {
      debugPrint('SshConnectionHub.disconnect: $err');
    }
  }

  Future<void> disconnectAll() async {
    final keys = List<String>.from(_entries.keys);
    for (final k in keys) {
      await disconnect(k);
    }
  }

  Future<void> _maybeClose(String hostId) async {
    final e = _entries[hostId];
    if (e == null) return;
    if (e.shellRefs > 0 || e.sftpRefs > 0) return;
    await disconnect(hostId);
  }
}

class _HubEntry {
  _HubEntry({required this.client, required this.profile});

  final SSHClient client;
  final HostProfile profile;
  int shellRefs = 0;
  int sftpRefs = 0;
}
