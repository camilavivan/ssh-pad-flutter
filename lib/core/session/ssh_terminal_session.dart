import 'dart:async';
import 'dart:convert';
import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import '../../data/host_profile.dart';

enum SshSessionPhase { connecting, connected, disconnected, error }

/// One SSH PTY shell bound to an [xterm] [Terminal].
///
/// Keepalive uses dartssh2 [SSHClient.keepAliveInterval] (~8s, JSch-like).
/// No aggressive auto-reconnect — disconnect is user-driven or process death.
class SshTerminalSession {
  SshTerminalSession({
    required this.id,
    required this.profile,
    Terminal? terminal,
  }) : terminal = terminal ?? Terminal(maxLines: 10000);

  final String id;
  final HostProfile profile;
  final Terminal terminal;

  SSHClient? _client;
  SSHSession? _shell;
  StreamSubscription<Uint8List>? _stdoutSub;
  StreamSubscription<Uint8List>? _stderrSub;
  SshSessionPhase phase = SshSessionPhase.connecting;
  String? errorMessage;
  VoidCallback? onChanged;

  bool get isConnected => phase == SshSessionPhase.connected;
  String get title {
    final name = profile.name.isNotEmpty ? profile.name : profile.host;
    return name;
  }

  Future<void> connect() async {
    phase = SshSessionPhase.connecting;
    errorMessage = null;
    _notify();
    terminal.write('\r\n* Connecting to ${profile.host}:${profile.port}…\r\n');

    try {
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
        // First-party Pad client: host key UX lands later; accept for M1.
        onVerifyHostKey: (type, key) => true,
      );
      _client = client;

      await client.authenticated;

      final shell = await client.shell(
        pty: SSHPtyConfig(
          type: 'xterm-256color',
          width: terminal.viewWidth,
          height: terminal.viewHeight,
        ),
      );
      _shell = shell;

      terminal.onOutput = (data) {
        final bytes = Uint8List.fromList(utf8.encode(data));
        shell.write(bytes);
      };
      terminal.onResize = (w, h, pw, ph) {
        try {
          shell.resizeTerminal(w, h, pw, ph);
        } catch (_) {}
      };

      _stdoutSub = shell.stdout.listen(
        (data) => terminal.write(utf8.decode(data, allowMalformed: true)),
        onError: (Object e) {
          terminal.write('\r\n* stdout error: $e\r\n');
        },
        onDone: () {
          if (phase == SshSessionPhase.connected) {
            phase = SshSessionPhase.disconnected;
            terminal.write('\r\n* Session closed by remote\r\n');
            _notify();
          }
        },
      );
      _stderrSub = shell.stderr.listen(
        (data) => terminal.write(utf8.decode(data, allowMalformed: true)),
      );

      unawaited(
        shell.done.then((_) {
          if (phase == SshSessionPhase.connected) {
            phase = SshSessionPhase.disconnected;
            terminal.write('\r\n* Shell ended\r\n');
            _notify();
          }
        }),
      );

      phase = SshSessionPhase.connected;
      terminal.write('* Connected\r\n');
      _notify();
    } catch (e, st) {
      debugPrint('SSH connect failed: $e\n$st');
      phase = SshSessionPhase.error;
      errorMessage = e.toString();
      terminal.write('\r\n* Connect failed: $e\r\n');
      await disconnect(silent: true);
      _notify();
      rethrow;
    }
  }

  /// Send Ctrl-C style interrupt if shell is up (also ExtraKeys path).
  void sendInterrupt() {
    final shell = _shell;
    if (shell == null) {
      // Fallback: write ETX so line discipline still sees ^C.
      terminal.onOutput?.call(String.fromCharCode(0x03));
      return;
    }
    try {
      shell.kill(SSHSignal.INT);
    } catch (_) {
      shell.write(Uint8List.fromList([0x03]));
    }
  }

  Future<void> disconnect({bool silent = false}) async {
    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _stdoutSub = null;
    _stderrSub = null;
    try {
      _shell?.close();
    } catch (_) {}
    _shell = null;
    try {
      _client?.close();
    } catch (_) {}
    _client = null;
    terminal.onOutput = null;
    terminal.onResize = null;
    if (!silent && phase != SshSessionPhase.error) {
      phase = SshSessionPhase.disconnected;
      _notify();
    }
  }

  void dispose() {
    unawaited(disconnect(silent: true));
  }

  void _notify() => onChanged?.call();
}
