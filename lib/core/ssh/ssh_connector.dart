import 'dart:typed_data';

import 'package:dartssh2/dartssh2.dart';

import '../../data/host_profile.dart';
import '../security/host_key_verifier.dart';
import '../session/session_log.dart';

/// Shared SSH connect + auth + TOFU host-key check for terminal and SFTP.
class SshConnector {
  /// Optional app-wide verifier (set from main / providers).
  static HostKeyVerifier? hostKeyVerifier;

  static Future<SSHClient> connect(HostProfile profile) async {
    sessionLog.add(
      'Connecting ${profile.protocol.label} ${profile.host}:${profile.port}',
    );

    final socket = await SSHSocket.connect(
      profile.host,
      profile.port,
      timeout: const Duration(seconds: 20),
    );

    List<SSHKeyPair>? identities;
    if (profile.auth == AuthMethod.key) {
      final pem = profile.privateKey?.trim();
      if (pem == null || pem.isEmpty) {
        throw StateError('Private key is empty');
      }
      identities = SSHKeyPair.fromPem(pem, profile.passphrase);
    }

    final verifier = hostKeyVerifier;
    final client = SSHClient(
      socket,
      username: profile.username.isEmpty ? 'root' : profile.username,
      identities: identities,
      onPasswordRequest: profile.auth == AuthMethod.password
          ? () => profile.password ?? ''
          : (profile.passphrase != null && profile.passphrase!.isNotEmpty
              ? () => profile.passphrase!
              : null),
      keepAliveInterval: const Duration(seconds: 8),
      onVerifyHostKey: (type, fingerprint) async {
        if (verifier == null) {
          // Fail closed without a verifier in production paths.
          sessionLog.add(
            'Host key rejected: no verifier registered',
            level: SessionLogLevel.error,
          );
          return false;
        }
        final ok = await verifier.verify(
          host: profile.host,
          port: profile.port,
          keyType: type,
          fingerprintBytes: fingerprint,
        );
        if (ok) {
          sessionLog.add(
            'Host key OK ${profile.host}:${profile.port} '
            '${decodeHostKeyFingerprint(fingerprint)}',
          );
        } else {
          sessionLog.add(
            'Host key rejected ${profile.host}:${profile.port}',
            level: SessionLogLevel.warn,
          );
        }
        return ok;
      },
    );

    try {
      await client.authenticated;
    } catch (e) {
      sessionLog.add('Auth/connect failed: $e', level: SessionLogLevel.error);
      try {
        client.close();
      } catch (_) {}
      rethrow;
    }
    sessionLog.add('Authenticated ${profile.host}:${profile.port}');
    return client;
  }
}

/// Helper re-export for fingerprint display.
String fingerprintToString(Uint8List bytes) =>
    decodeHostKeyFingerprint(bytes);
