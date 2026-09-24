import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/host_store.dart';

const _kWeakAudioKey = 'keepalive_weak_audio_v1';

/// MethodChannel bridge to Android [SessionForegroundService].
///
/// Product semantics: keep sessions across app switch; disconnect only on user
/// action (incl. notification Stop) or process death; no silent reconnect loop.
class KeepAliveController with WidgetsBindingObserver {
  KeepAliveController(this._prefs) {
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler(_onPlatformCall);
    _weakAudio = _prefs.getBool(_kWeakAudioKey) ?? false;
  }

  static const _channel = MethodChannel('com.sshtab.ssh_pad_flutter/keepalive');

  final SharedPreferences _prefs;

  /// Session titles currently considered alive.
  List<String> _sessionTitles = const [];

  bool _weakAudio = false;
  bool _disposed = false;

  /// Invoked when user taps Disconnect on the FGS notification.
  VoidCallback? onStopRequested;

  bool get weakAudioEnabled => _weakAudio;

  Future<void> setWeakAudioEnabled(bool value) async {
    _weakAudio = value;
    await _prefs.setBool(_kWeakAudioKey, value);
    await _syncNative();
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
  }

  /// Update active sessions and push to native FGS (wake/wifi locks held there).
  Future<void> updateSessions(List<String> sessionTitles) async {
    _sessionTitles = List.unmodifiable(sessionTitles);
    await _syncNative();
  }

  Future<void> _syncNative() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('updateSessions', {
        'sessions': _sessionTitles,
        'count': _sessionTitles.length,
        'title': _sessionTitles.isEmpty
            ? ''
            : (_sessionTitles.length == 1
                ? _sessionTitles.first
                : '${_sessionTitles.length} 个会话'),
        'weakAudio': _weakAudio,
      });
    } on MissingPluginException {
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

  Future<bool> requestNotificationPermission() async {
    if (!Platform.isAndroid) return true;
    try {
      final ok = await _channel.invokeMethod<bool>('requestNotificationPermission');
      return ok ?? false;
    } catch (e) {
      debugPrint('KeepAlive notification permission failed: $e');
      return false;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Sync early on inactive so FGS can start while still allowed under
    // Android 12+ background restrictions.
    if (state == AppLifecycleState.inactive ||
        state == AppLifecycleState.paused ||
        state == AppLifecycleState.resumed) {
      _syncNative();
    }
  }

  Future<dynamic> _onPlatformCall(MethodCall call) async {
    switch (call.method) {
      case 'stopRequested':
        _sessionTitles = const [];
        onStopRequested?.call();
        return null;
      default:
        return null;
    }
  }
}

final keepAliveControllerProvider = Provider<KeepAliveController>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final c = KeepAliveController(prefs);
  ref.onDispose(c.dispose);
  return c;
});
