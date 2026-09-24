import 'dart:async';
import 'dart:convert';

import 'package:ctelnet/ctelnet.dart';
import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import '../../data/host_profile.dart';
import '../session/terminal_session.dart';

/// Telnet option codes (RFC 854 / 855 / 1091 / 1073).
class _Opt {
  static const echo = 1;
  static const sga = 3; // Suppress Go Ahead
  static const ttype = 24;
  static const naws = 31;
}

/// Telnet session bound to the same [xterm] [Terminal] as SSH.
///
/// Uses [ctelnet] with basic ECHO / SGA / TTYPE / NAWS negotiation so echo
/// works on typical LAN gear. Cleartext — warned in the host editor.
class TelnetTerminalSession implements TerminalSession {
  TelnetTerminalSession({
    required this.id,
    required this.profile,
    Terminal? terminal,
  }) : terminal = terminal ?? Terminal(maxLines: 10000);

  @override
  final String id;
  @override
  final HostProfile profile;
  @override
  final Terminal terminal;

  CTelnetClient? _client;
  StreamSubscription<Message>? _sub;

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
    terminal.write(
      '\r\n* TELNET connecting to ${profile.host}:${profile.port}…\r\n',
    );
    terminal.write('* Warning: Telnet is cleartext\r\n');

    final wait = Completer<void>();

    final client = CTelnetClient(
      host: profile.host,
      port: profile.port,
      timeout: const Duration(seconds: 20),
      onConnect: () {
        if (!wait.isCompleted) wait.complete();
      },
      onDisconnect: () {
        if (phase == SessionPhase.connected) {
          phase = SessionPhase.disconnected;
          terminal.write('\r\n* Telnet disconnected\r\n');
          _notify();
        }
      },
      onError: (dynamic error) {
        if (!wait.isCompleted) {
          wait.completeError(error);
        } else if (phase == SessionPhase.connected) {
          phase = SessionPhase.error;
          errorMessage = error.toString();
          terminal.write('\r\n* Telnet error: $error\r\n');
          _notify();
        }
      },
    );
    _client = client;

    try {
      final stream = await client.connect();
      if (stream == null) {
        throw StateError('Telnet connect returned no stream');
      }

      _sub = stream.listen(
        _onMessage,
        onError: (Object e) {
          terminal.write('\r\n* stream error: $e\r\n');
        },
        onDone: () {
          if (phase == SessionPhase.connected) {
            phase = SessionPhase.disconnected;
            terminal.write('\r\n* Telnet stream closed\r\n');
            _notify();
          }
        },
      );

      await wait.future.timeout(const Duration(seconds: 20));

      // Proactive offers so servers that wait for negotiation wake up.
      client.doo(_Opt.echo);
      client.doo(_Opt.sga);
      client.will(_Opt.sga);
      client.will(_Opt.ttype);
      client.will(_Opt.naws);
      _sendNaws();

      terminal.onOutput = (data) {
        _client?.send(data);
      };
      terminal.onResize = (w, h, pw, ph) {
        _sendNaws(cols: w, rows: h);
      };

      phase = SessionPhase.connected;
      terminal.write('* Telnet connected — login in the terminal\r\n');
      _notify();
    } catch (e, st) {
      debugPrint('Telnet connect failed: $e\n$st');
      phase = SessionPhase.error;
      errorMessage = e.toString();
      terminal.write('\r\n* Connect failed: $e\r\n');
      await disconnect(silent: true);
      _notify();
      rethrow;
    }
  }

  void _onMessage(Message msg) {
    _negotiate(msg);
    if (msg.isText) {
      terminal.write(msg.text);
    }
  }

  void _negotiate(Message msg) {
    final client = _client;
    if (client == null || !msg.isCommand) return;

    if (msg.will(_Opt.echo) || msg.will(_Opt.sga)) {
      if (msg.will(_Opt.echo)) client.doo(_Opt.echo);
      if (msg.will(_Opt.sga)) client.doo(_Opt.sga);
    }
    if (msg.doo(_Opt.sga)) client.will(_Opt.sga);
    if (msg.doo(_Opt.ttype)) client.will(_Opt.ttype);
    if (msg.doo(_Opt.naws)) {
      client.will(_Opt.naws);
      _sendNaws();
    }
    if (msg.doo(_Opt.echo)) {
      // We do not local-echo.
      client.wont(_Opt.echo);
    }

    // SB TERMINAL-TYPE SEND → IS xterm-256color
    final ttypeData = msg.subnegotiation(_Opt.ttype);
    if (ttypeData != null &&
        ttypeData.isNotEmpty &&
        ttypeData.first == Symbols.send) {
      final name = ascii.encode('xterm-256color');
      client.subnegotiate(_Opt.ttype, [Symbols.iss, ...name]);
    }
  }

  void _sendNaws({int? cols, int? rows}) {
    final c = (cols ?? terminal.viewWidth).clamp(1, 0xffff);
    final r = (rows ?? terminal.viewHeight).clamp(1, 0xffff);
    _client?.subnegotiate(_Opt.naws, [
      (c >> 8) & 0xff,
      c & 0xff,
      (r >> 8) & 0xff,
      r & 0xff,
    ]);
  }

  @override
  void sendInterrupt() {
    _client?.sendBytes([0x03]);
  }

  @override
  Future<void> disconnect({bool silent = false}) async {
    await _sub?.cancel();
    _sub = null;
    try {
      await _client?.disconnect();
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
