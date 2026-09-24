import 'dart:async';
import 'dart:convert';

import 'package:dartssh2/dartssh2.dart';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import '../../data/host_profile.dart';
import 'terminal_factory.dart';
import 'terminal_session.dart';

/// One SSH PTY shell bound to an [xterm] [Terminal].
///
/// Keepalive uses dartssh2 [SSHClient.keepAliveInterval] (~8s, JSch-like).
/// No aggressive auto-reconnect — disconnect is user-driven or process death.
class SshTerminalSession implements TerminalSession {
  SshTerminalSession({
    required this.id,
    required this.profile,
    Terminal? terminal,
  }) : terminal = terminal ?? createPadTerminal();

  @override
  final String id;
  @override
  final HostProfile profile;
  @override
  final Terminal terminal;

  SSHClient? _client;
  SSHSession? _shell;
  StreamSubscription<Uint8List>? _stdoutSub;
  StreamSubscription<Uint8List>? _stderrSub;

  @override
  SessionPhase phase = SessionPhase.connecting;
  @override
  String? errorMessage;

  @override
  VoidCallback? onChanged;

  @override
  bool get isConnected => phase == SessionPhase.connected;

  @override
  String get title {
    final name = profile.name.isNotEmpty ? profile.name : profile.host;
    return name;
  }

  @override
  String get keepAliveTitle => '${profile.protocol.label} $title';






  @override
  Future<void> connect() async {
    phase = SessionPhase.connecting;
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
        // First-party Pad client: host key UX lands later; accept for M1/M2.
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
        shell.write(Uint8List.fromList(utf8.encode(data)));
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
          if (phase == SessionPhase.connected) {
            phase = SessionPhase.disconnected;
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
          if (phase == SessionPhase.connected) {
            phase = SessionPhase.disconnected;
            terminal.write('\r\n* Shell ended\r\n');
            _notify();
          }
        }),
      );

      phase = SessionPhase.connected;
      terminal.write('* Connected\r\n');
      _notify();
    } catch (e, st) {
      debugPrint('SSH connect failed: $e\n$st');
      phase = SessionPhase.error;
      errorMessage = e.toString();
      terminal.write('\r\n* Connect failed: $e\r\n');
      await disconnect(silent: true);
      _notify();
      rethrow;
    }
  }

  @override
  void sendInterrupt() {
    final shell = _shell;
    if (shell == null) {
      terminal.onOutput?.call(String.fromCharCode(0x03));
      return;
    }
    try {
      shell.kill(SSHSignal.INT);
    } catch (_) {
      shell.write(Uint8List.fromList([0x03]));
    }
  }

  @override
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
    if (!silent && phase != SessionPhase.error) {
      phase = SessionPhase.disconnected;
      _notify();
    }
  }

  @override
  void dispose() {
    unawaited(disconnect(silent: true));
  }

  void _notify() => onChanged?.call();
}
