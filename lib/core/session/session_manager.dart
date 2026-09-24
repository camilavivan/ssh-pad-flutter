import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/host_profile.dart';
import '../keepalive/keepalive_controller.dart';
import '../telnet/telnet_terminal_session.dart';
import 'file_browser_session.dart';
import 'ssh_terminal_session.dart';
import 'terminal_session.dart';

/// Multi-session hub: SSH/Telnet terminals + SFTP/FTP browsers; syncs FGS.
class SessionManager extends ChangeNotifier {
  SessionManager(this._keepalive);

  final KeepAliveController _keepalive;
  final List<TerminalSession> _terminals = [];
  final List<FileBrowserSession> _files = [];
  String? _activeTerminalId;
  String? _activeFileId;
  bool _disposed = false;

  List<TerminalSession> get terminals => List.unmodifiable(_terminals);
  List<FileBrowserSession> get files => List.unmodifiable(_files);

  /// Back-compat alias used by terminal UI.
  List<TerminalSession> get sessions => terminals;

  String? get activeId => _activeTerminalId;
  String? get activeFileId => _activeFileId;

  TerminalSession? get active {
    if (_terminals.isEmpty) return null;
    final id = _activeTerminalId;
    if (id == null) return _terminals.last;
    for (final s in _terminals) {
      if (s.id == id) return s;
    }
    return _terminals.last;
  }

  FileBrowserSession? get activeFile {
    if (_files.isEmpty) return null;
    final id = _activeFileId;
    if (id == null) return _files.last;
    for (final s in _files) {
      if (s.id == id) return s;
    }
    return _files.last;
  }

  Future<TerminalSession> openTerminal(HostProfile profile) async {
    if (!profile.protocol.isTerminal) {
      throw UnsupportedError(
        '${profile.protocol.label} is not a terminal protocol',
      );
    }
    final id =
        '${profile.id}_${DateTime.now().millisecondsSinceEpoch}_${_terminals.length}';
    final TerminalSession session = profile.protocol == HostProtocol.telnet
        ? TelnetTerminalSession(id: id, profile: profile)
        : SshTerminalSession(id: id, profile: profile);

    session.onChanged = () {
      if (!_disposed) {
        notifyListeners();
        _syncKeepAlive();
      }
    };
    _terminals.add(session);
    _activeTerminalId = id;
    notifyListeners();
    _syncKeepAlive();

    try {
      await session.connect();
    } catch (_) {
      // Keep listed with error phase so user can dismiss.
    }
    _syncKeepAlive();
    notifyListeners();
    return session;
  }

  /// Back-compat for M1 call sites.
  Future<TerminalSession> open(HostProfile profile) => openTerminal(profile);

  Future<FileBrowserSession> openFiles(HostProfile profile) async {
    if (!profile.protocol.isFile) {
      throw UnsupportedError(
        '${profile.protocol.label} is not a file protocol',
      );
    }
    final id =
        'file_${profile.id}_${DateTime.now().millisecondsSinceEpoch}_${_files.length}';
    final session = FileBrowserSession(
      id: id,
      profile: profile,
      backend: FileBrowserSession.backendFor(profile),
    );
    session.onChanged = () {
      if (!_disposed) {
        notifyListeners();
        _syncKeepAlive();
      }
    };
    _files.add(session);
    _activeFileId = id;
    notifyListeners();
    _syncKeepAlive();

    try {
      await session.connect();
    } catch (_) {}
    _syncKeepAlive();
    notifyListeners();
    return session;
  }

  void setActive(String id) {
    if (_terminals.any((s) => s.id == id)) {
      _activeTerminalId = id;
      notifyListeners();
    }
  }

  void setActiveFile(String id) {
    if (_files.any((s) => s.id == id)) {
      _activeFileId = id;
      notifyListeners();
    }
  }

  Future<void> close(String id) async {
    final i = _terminals.indexWhere((s) => s.id == id);
    if (i < 0) return;
    final s = _terminals.removeAt(i);
    await s.disconnect();
    s.dispose();
    if (_activeTerminalId == id) {
      _activeTerminalId = _terminals.isEmpty ? null : _terminals.last.id;
    }
    notifyListeners();
    await _syncKeepAlive();
  }

  Future<void> closeFile(String id) async {
    final i = _files.indexWhere((s) => s.id == id);
    if (i < 0) return;
    final s = _files.removeAt(i);
    await s.disconnect();
    s.dispose();
    if (_activeFileId == id) {
      _activeFileId = _files.isEmpty ? null : _files.last.id;
    }
    notifyListeners();
    await _syncKeepAlive();
  }

  Future<void> closeAll() async {
    final terms = List<TerminalSession>.from(_terminals);
    final files = List<FileBrowserSession>.from(_files);
    _terminals.clear();
    _files.clear();
    _activeTerminalId = null;
    _activeFileId = null;
    notifyListeners();
    for (final s in terms) {
      await s.disconnect();
      s.dispose();
    }
    for (final s in files) {
      await s.disconnect();
      s.dispose();
    }
    await _syncKeepAlive();
  }

  Future<void> _syncKeepAlive() async {
    final titles = <String>[
      ..._terminals
          .where((s) =>
              s.phase == SessionPhase.connected ||
              s.phase == SessionPhase.connecting)
          .map((s) => s.keepAliveTitle),
      ..._files
          .where((s) =>
              s.phase == SessionPhase.connected ||
              s.phase == SessionPhase.connecting)
          .map((s) => s.keepAliveTitle),
    ];
    await _keepalive.updateSessions(titles);
  }

  @override
  void dispose() {
    _disposed = true;
    for (final s in _terminals) {
      s.dispose();
    }
    for (final s in _files) {
      s.dispose();
    }
    _terminals.clear();
    _files.clear();
    super.dispose();
  }
}

final sessionManagerProvider = ChangeNotifierProvider<SessionManager>((ref) {
  final keepalive = ref.watch(keepAliveControllerProvider);
  final mgr = SessionManager(keepalive);
  keepalive.onStopRequested = () {
    mgr.closeAll();
  };
  ref.onDispose(() {
    keepalive.onStopRequested = null;
    mgr.dispose();
  });
  return mgr;
});
