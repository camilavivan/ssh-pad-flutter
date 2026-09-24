import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/host_profile.dart';
import '../keepalive/keepalive_controller.dart';
import 'ssh_terminal_session.dart';

/// Multi-session hub: open / switch / close SSH terminals and sync FGS.
class SessionManager extends ChangeNotifier {
  SessionManager(this._keepalive);

  final KeepAliveController _keepalive;
  final List<SshTerminalSession> _sessions = [];
  String? _activeId;
  bool _disposed = false;

  List<SshTerminalSession> get sessions => List.unmodifiable(_sessions);
  String? get activeId => _activeId;

  SshTerminalSession? get active {
    if (_sessions.isEmpty) return null;
    final id = _activeId;
    if (id == null) return _sessions.last;
    for (final s in _sessions) {
      if (s.id == id) return s;
    }
    return _sessions.last;
  }

  /// Open SSH only in M1; other protocols stay placeholders at call site.
  Future<SshTerminalSession> open(HostProfile profile) async {
    if (profile.protocol != HostProtocol.ssh) {
      throw UnsupportedError(
        '${profile.protocol.label} connect lands in M2',
      );
    }
    final id =
        '${profile.id}_${DateTime.now().millisecondsSinceEpoch}_${_sessions.length}';
    final session = SshTerminalSession(id: id, profile: profile);
    session.onChanged = () {
      if (!_disposed) {
        notifyListeners();
        _syncKeepAlive();
      }
    };
    _sessions.add(session);
    _activeId = id;
    notifyListeners();
    _syncKeepAlive();

    try {
      await session.connect();
    } catch (_) {
      // Session remains listed with error phase so user can dismiss.
    }
    _syncKeepAlive();
    notifyListeners();
    return session;
  }

  void setActive(String id) {
    if (_sessions.any((s) => s.id == id)) {
      _activeId = id;
      notifyListeners();
    }
  }

  Future<void> close(String id) async {
    final i = _sessions.indexWhere((s) => s.id == id);
    if (i < 0) return;
    final s = _sessions.removeAt(i);
    await s.disconnect();
    s.dispose();
    if (_activeId == id) {
      _activeId = _sessions.isEmpty ? null : _sessions.last.id;
    }
    notifyListeners();
    await _syncKeepAlive();
  }

  Future<void> closeAll() async {
    final copy = List<SshTerminalSession>.from(_sessions);
    _sessions.clear();
    _activeId = null;
    notifyListeners();
    for (final s in copy) {
      await s.disconnect();
      s.dispose();
    }
    await _syncKeepAlive();
  }

  Future<void> _syncKeepAlive() async {
    final titles = _sessions
        .where((s) =>
            s.phase == SshSessionPhase.connected ||
            s.phase == SshSessionPhase.connecting)
        .map((s) => s.title)
        .toList();
    await _keepalive.updateSessions(titles);
  }

  @override
  void dispose() {
    _disposed = true;
    for (final s in _sessions) {
      s.dispose();
    }
    _sessions.clear();
    super.dispose();
  }
}

final sessionManagerProvider = ChangeNotifierProvider<SessionManager>((ref) {
  final keepalive = ref.watch(keepAliveControllerProvider);
  final mgr = SessionManager(keepalive);
  // Notification "Disconnect all" → clear sessions.
  keepalive.onStopRequested = () {
    mgr.closeAll();
  };
  ref.onDispose(() {
    keepalive.onStopRequested = null;
    mgr.dispose();
  });
  return mgr;
});
