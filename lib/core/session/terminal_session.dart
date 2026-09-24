import 'package:flutter/foundation.dart';
import 'package:xterm/xterm.dart';

import '../../data/host_profile.dart';
import 'session_backend.dart';

export 'session_backend.dart' show SessionPhase;

/// UI-facing terminal session bound to an [xterm] [Terminal].
abstract class TerminalSession {
  String get id;
  HostProfile get profile;
  Terminal get terminal;
  SessionPhase get phase;
  String? get errorMessage;
  VoidCallback? onChanged;

  bool get isConnected => phase == SessionPhase.connected;

  String get title {
    final name = profile.name.isNotEmpty ? profile.name : profile.host;
    return name;
  }

  /// Protocol label prefix for tab / FGS (e.g. "SSH lab", "TELNET router").
  String get keepAliveTitle => '${profile.protocol.label} $title';

  Future<void> connect();
  Future<void> disconnect({bool silent = false});
  void dispose();

  /// Ctrl-C / interrupt — SSH may use channel signal; Telnet sends ETX.
  void sendInterrupt();
}
