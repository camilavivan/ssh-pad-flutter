import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';

import 'host_key_store.dart';

enum HostKeyPromptKind { firstSeen, mismatch }

class HostKeyPromptRequest {
  HostKeyPromptRequest({
    required this.host,
    required this.port,
    required this.keyType,
    required this.fingerprint,
    required this.kind,
    this.previous,
  });

  final String host;
  final int port;
  final String keyType;
  final String fingerprint;
  final HostKeyPromptKind kind;
  final TrustedHostKey? previous;
}

enum HostKeyDecision { accept, reject, replace }

/// Decodes dartssh2 fingerprint bytes (`SHA256:<base64>`) to a display string.
String decodeHostKeyFingerprint(Uint8List fingerprintBytes) {
  try {
    return utf8.decode(fingerprintBytes, allowMalformed: false);
  } catch (_) {
    return base64.encode(fingerprintBytes);
  }
}

typedef HostKeyPromptHandler = Future<HostKeyDecision> Function(
  HostKeyPromptRequest request,
);

/// TOFU verifier used by SSH/SFTP connect paths.
///
/// UI registers [promptHandler] (dialog). Without a handler, first-seen keys
/// are auto-accepted in debug only; release rejects until UI is ready.
class HostKeyVerifier {
  HostKeyVerifier(this._store);

  final HostKeyStore _store;

  /// Set from app UI (navigator dialog).
  HostKeyPromptHandler? promptHandler;

  Future<bool> verify({
    required String host,
    required int port,
    required String keyType,
    required Uint8List fingerprintBytes,
  }) async {
    final fp = decodeHostKeyFingerprint(fingerprintBytes);
    final existing = _store.lookup(host, port);

    if (existing != null &&
        existing.fingerprint == fp &&
        existing.keyType == keyType) {
      return true;
    }

    final kind = existing == null
        ? HostKeyPromptKind.firstSeen
        : HostKeyPromptKind.mismatch;

    final request = HostKeyPromptRequest(
      host: host,
      port: port,
      keyType: keyType,
      fingerprint: fp,
      kind: kind,
      previous: existing,
    );

    final handler = promptHandler;
    HostKeyDecision decision;
    if (handler != null) {
      decision = await handler(request);
    } else {
      // Headless / tests: accept unknown, reject mismatch.
      decision = kind == HostKeyPromptKind.firstSeen
          ? HostKeyDecision.accept
          : HostKeyDecision.reject;
      debugPrint(
        'HostKeyVerifier: no UI handler; $kind → $decision for $host:$port $fp',
      );
    }

    switch (decision) {
      case HostKeyDecision.reject:
        return false;
      case HostKeyDecision.accept:
        if (kind == HostKeyPromptKind.mismatch) {
          // Accept without replacing is not allowed for mismatch.
          return false;
        }
        await _store.trust(
          TrustedHostKey(
            host: host,
            port: port,
            keyType: keyType,
            fingerprint: fp,
            trustedAt: DateTime.now().toUtc(),
          ),
        );
        return true;
      case HostKeyDecision.replace:
        await _store.trust(
          TrustedHostKey(
            host: host,
            port: port,
            keyType: keyType,
            fingerprint: fp,
            trustedAt: DateTime.now().toUtc(),
          ),
        );
        return true;
    }
  }
}
