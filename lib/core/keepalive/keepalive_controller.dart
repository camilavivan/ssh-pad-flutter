import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// MethodChannel bridge to Android [SessionForegroundService].
///
/// **保活是重中之重**：M0 只搭通道与生命周期钩子；有会话后（M1b）
/// 在 inactive 即 sync FGS，避免 Android 12+ 后台无法新启前台服务。
class KeepAliveController with WidgetsBindingObserver {
  KeepAliveController() {
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler(_onPlatformCall);
  }

  static const _channel = MethodChannel('com.sshtab.ssh_pad_flutter/keepalive');

  /// Session ids currently considered "alive" (empty in M0).
  List<String> _sessionIds = const [];

  bool _disposed = false;

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
  }

  /// Update active sessions and push to native FGS.
  Future<void> updateSessions(List<String> sessionIds) async {
    _sessionIds = List.unmodifiable(sessionIds);
    await _syncNative();
  }

  Future<void> _syncNative() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('updateSessions', {
        'sessions': _sessionIds,
        'count': _sessionIds.length,
      });
    } on MissingPluginException {
      // Analyzer / desktop: channel may be absent.
      debugPrint('KeepAlive: channel missing (non-Android or stub)');
    } catch (e, st) {
      debugPrint('KeepAlive sync failed: $e\n$st');
    }
  }

  Future<void> requestIgnoreBatteryOptimizations() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('requestIgnoreBatteryOptimizations');
    } catch (e) {
      debugPrint('KeepAlive battery request failed: $e');
    }
  }

  Future<void> openOemAutostartSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('openOemAutostartSettings');
    } catch (e) {
      debugPrint('KeepAlive OEM settings failed: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Sync early on inactive (not only paused) so FGS can start while still
    // allowed under Android 12+ background restrictions.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.resumed) {
      _syncNative();
    }
  }

  Future<dynamic> _onPlatformCall(MethodCall call) async {
    switch (call.method) {
      case 'stopRequested':
        // User tapped Stop on the FGS notification — clear sessions (M1b).
        _sessionIds = const [];
        return null;
      default:
        return null;
    }
  }
}

final keepAliveControllerProvider = Provider<KeepAliveController>((ref) {
  final c = KeepAliveController();
  ref.onDispose(c.dispose);
  return c;
});
