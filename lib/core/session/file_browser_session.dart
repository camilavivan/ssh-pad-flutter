import 'dart:async';

import 'package:flutter/foundation.dart';

import '../../data/host_profile.dart';
import '../ftp/ftp_file_backend.dart';
import '../sftp/sftp_file_backend.dart';
import '../ssh/ssh_connection_hub.dart';
import 'file_backend.dart';
import 'session_backend.dart';

/// Active SFTP/FTP browser held by [SessionManager] for FGS keepalive.
class FileBrowserSession {
  FileBrowserSession({
    required this.id,
    required this.profile,
    required this.backend,
  });

  final String id;
  final HostProfile profile;
  final FileBackend backend;

  SessionPhase phase = SessionPhase.connecting;
  String? errorMessage;
  VoidCallback? onChanged;

  bool get isConnected => phase == SessionPhase.connected;

  String get title {
    final name = profile.name.isNotEmpty ? profile.name : profile.host;
    return name;
  }

  String get keepAliveTitle => '${profile.protocol.label} $title';

  static FileBackend backendFor(
    HostProfile profile, {
    SshConnectionHub? sshHub,
  }) {
    switch (profile.protocol) {
      case HostProtocol.sftp:
        return SftpFileBackend(profile, hub: sshHub);
      case HostProtocol.ftp:
        return FtpFileBackend(profile);
      default:
        throw UnsupportedError(
          '${profile.protocol.label} is not a file protocol',
        );
    }
  }

  Future<void> connect() async {
    phase = SessionPhase.connecting;
    errorMessage = null;
    onChanged?.call();
    try {
      await backend.connect();
      phase = SessionPhase.connected;
      onChanged?.call();
    } catch (e) {
      try {
        await backend.disconnect();
      } catch (_) {}
      phase = SessionPhase.error;
      errorMessage = e.toString();
      onChanged?.call();
      rethrow;
    }
  }

  Future<void> disconnect() async {
    try {
      await backend.disconnect();
    } catch (_) {}
    if (phase != SessionPhase.error) {
      phase = SessionPhase.disconnected;
      onChanged?.call();
    }
  }

  void dispose() {
    unawaited(disconnect());
  }
}
