import 'dart:async';
import 'dart:convert';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../data/host_profile.dart';
import '../session/session_backend.dart';
import '../session/session_manager.dart';
import '../ssh/ssh_connection_hub.dart';
import 'host_resource_stats.dart';
import 'proc_status_parser.dart';

/// Polls Linux /proc via exec on the **shared** [SshConnectionHub] client.
///
/// - SSH / SFTP hosts only (hub must already be connected)
/// - Never opens a second SSH session
/// - Timer runs while app is resumed; pauses in background (keepalive stays)
class HostStatusMonitor extends ChangeNotifier with WidgetsBindingObserver {
  HostStatusMonitor({
    required this._hub,
    this.interval = const Duration(milliseconds: 2500),
    this.execTimeout = const Duration(seconds: 6),
  }) {
    WidgetsBinding.instance.addObserver(this);
  }

  final SshConnectionHub _hub;
  final Duration interval;
  final Duration execTimeout;

  final Map<String, HostResourceStats> _stats = {};
  final Map<String, HostStatusAccumulator> _acc = {};
  final Set<String> _activeIds = {};
  final Set<String> _sampling = {};

  Timer? _timer;
  bool _foreground = true;
  bool _disposed = false;

  HostResourceStats? statsOf(String hostId) => _stats[hostId];

  /// Replace the set of hosts that should be sampled.
  void setActiveHosts(Set<String> hostIds) {
    final next = Set<String>.from(hostIds);
    final removed = _activeIds.difference(next);
    for (final id in removed) {
      _acc.remove(id);
      _stats.remove(id);
      _sampling.remove(id);
    }
    _activeIds
      ..clear()
      ..addAll(next);
    for (final id in next) {
      _acc.putIfAbsent(id, HostStatusAccumulator.new);
    }
    _ensureTimer();
    if (removed.isNotEmpty) notifyListeners();
  }

  /// Derive active SSH hub hosts from [SessionManager].
  void syncFrom(SessionManager mgr) {
    final ids = <String>{};
    void consider(HostProfile profile, SessionPhase phase) {
      final isSshFamily = profile.protocol == HostProtocol.ssh ||
          profile.protocol == HostProtocol.sftp;
      if (!isSshFamily) return;
      if (phase != SessionPhase.connected) return;
      if (!_hub.isConnected(profile.id)) return;
      ids.add(profile.id);
    }

    for (final s in mgr.sessions) {
      consider(s.profile, s.phase);
    }
    for (final f in mgr.files) {
      consider(f.profile, f.phase);
    }
    // Also pick up hub-connected hosts even if phase races.
    for (final id in List<String>.from(ids)) {
      if (!_hub.isConnected(id)) ids.remove(id);
    }
    setActiveHosts(ids);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final fg = state == AppLifecycleState.resumed;
    if (fg == _foreground) return;
    _foreground = fg;
    _ensureTimer();
    if (fg) {
      // Immediate refresh on return to foreground.
      unawaited(_tickAll());
    }
  }

  void _ensureTimer() {
    final want = _foreground && _activeIds.isNotEmpty && !_disposed;
    if (want) {
      _timer ??= Timer.periodic(interval, (_) => unawaited(_tickAll()));
      // Kick first sample promptly.
      unawaited(_tickAll());
    } else {
      _timer?.cancel();
      _timer = null;
    }
  }

  Future<void> _tickAll() async {
    if (_disposed || !_foreground) return;
    final ids = List<String>.from(_activeIds);
    for (final id in ids) {
      await _sampleOne(id);
    }
  }

  Future<void> _sampleOne(String hostId) async {
    if (_disposed || !_foreground) return;
    if (_sampling.contains(hostId)) return;
    final client = _hub.clientOf(hostId);
    if (client == null) {
      if (_stats.remove(hostId) != null) notifyListeners();
      _activeIds.remove(hostId);
      _acc.remove(hostId);
      _ensureTimer();
      return;
    }

    _sampling.add(hostId);
    try {
      final bytes = await client
          .run(kHostStatusProbeCmd, runInPty: false, stderr: false)
          .timeout(execTimeout);
      if (_disposed) return;
      final raw = utf8.decode(bytes, allowMalformed: true);
      final acc = _acc.putIfAbsent(hostId, HostStatusAccumulator.new);
      final stats = acc.applyRaw(raw);
      if (stats != null) {
        _stats[hostId] = stats;
        notifyListeners();
      }
    } on TimeoutException {
      debugPrint('HostStatusMonitor: timeout $hostId');
    } catch (e) {
      debugPrint('HostStatusMonitor: $hostId $e');
      if (!_hub.isConnected(hostId)) {
        _stats.remove(hostId);
        _acc.remove(hostId);
        _activeIds.remove(hostId);
        notifyListeners();
        _ensureTimer();
      }
    } finally {
      _sampling.remove(hostId);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _timer?.cancel();
    _timer = null;
    _activeIds.clear();
    _stats.clear();
    _acc.clear();
    super.dispose();
  }
}

final hostStatusMonitorProvider =
    ChangeNotifierProvider<HostStatusMonitor>((ref) {
  final mgr = ref.read(sessionManagerProvider);
  final monitor = HostStatusMonitor(hub: mgr.sshHub);

  void onMgr() => monitor.syncFrom(mgr);
  mgr.addListener(onMgr);
  // Defer first sync so hub connection after connect() is visible.
  scheduleMicrotask(onMgr);

  ref.onDispose(() {
    mgr.removeListener(onMgr);
    monitor.dispose();
  });
  return monitor;
});
