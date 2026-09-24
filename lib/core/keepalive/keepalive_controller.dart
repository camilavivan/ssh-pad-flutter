import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../data/host_store.dart';

const _kWeakAudioKey = 'keepalive_weak_audio_v1';
const _kBatteryPromptedKey = 'keepalive_battery_prompted_v1';
const _kNotifPromptedKey = 'keepalive_notif_prompted_v1';

/// MethodChannel bridge to Android [SessionForegroundService].
///
/// Product semantics: keep sessions across app switch; disconnect only on user
/// action (incl. notification Stop) or process death; no silent reconnect loop.
///
/// Weak audio (mediaPlayback AudioTrack) defaults **ON** — same-process Dart
/// SSH is frozen by many CN OEMs without it. User can disable in settings.
class KeepAliveController extends ChangeNotifier with WidgetsBindingObserver {
  KeepAliveController(this._prefs) {
    WidgetsBinding.instance.addObserver(this);
    _channel.setMethodCallHandler(_onPlatformCall);
    // Default ON when unset: required for CN OEM keepalive with same-process Dart.
    _weakAudio = _prefs.getBool(_kWeakAudioKey) ?? true;
  }

  static const _channel = MethodChannel('com.sshtab.ssh_pad_flutter/keepalive');

  final SharedPreferences _prefs;

  /// Session titles currently considered alive.
  List<String> _sessionTitles = const [];

  bool _weakAudio = true;
  bool _disposed = false;
  bool _firstConnectHooksDone = false;

  /// Invoked when user taps Disconnect on the FGS notification.
  VoidCallback? onStopRequested;

  bool get weakAudioEnabled => _weakAudio;

  Future<void> setWeakAudioEnabled(bool value) async {
    _weakAudio = value;
    await _prefs.setBool(_kWeakAudioKey, value);
    notifyListeners();
    await _syncNative();
  }

  @override
  void dispose() {
    if (_disposed) return;
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Update active sessions and push to native FGS (wake/wifi locks held there).
  /// Starts FGS at connect time (not only on background).
  Future<void> updateSessions(List<String> sessionTitles) async {
    _sessionTitles = List.unmodifiable(sessionTitles);
    if (sessionTitles.isNotEmpty) {
      await _runFirstConnectHooks();
    }
    await _syncNative();
  }

  /// Notification + battery whitelist once on first live session.
  Future<void> _runFirstConnectHooks() async {
    if (_firstConnectHooksDone || !Platform.isAndroid) return;
    _firstConnectHooksDone = true;
    try {
      if (!(_prefs.getBool(_kNotifPromptedKey) ?? false)) {
        await requestNotificationPermission();
        await _prefs.setBool(_kNotifPromptedKey, true);
      }
      if (!(_prefs.getBool(_kBatteryPromptedKey) ?? false)) {
        final ignoring = await isIgnoringBatteryOptimizations();
        if (!ignoring) {
          await requestIgnoreBatteryOptimizations();
        }
        await _prefs.setBool(_kBatteryPromptedKey, true);
      }
    } catch (e) {
      debugPrint('KeepAlive first-connect hooks: $e');
    }
  }

  Future<void> _syncNative() async {
    if (!Platform.isAndroid) return;
    try {
      debugPrint(
        'KeepAlive sync n=${_sessionTitles.length} weakAudio=$_weakAudio',
      );
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

  Future<void> ensureKeepAlive() async {
    if (!Platform.isAndroid || _sessionTitles.isEmpty) return;
    try {
      await _channel.invokeMethod<void>('ensureKeepAlive');
    } catch (e) {
      debugPrint('KeepAlive ensure failed: $e');
      await _syncNative();
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

  Future<bool> isIgnoringBatteryOptimizations() async {
    if (!Platform.isAndroid) return true;
    try {
      final ok =
          await _channel.invokeMethod<bool>('isIgnoringBatteryOptimizations');
      return ok ?? false;
    } catch (_) {
      return false;
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
      final ok =
          await _channel.invokeMethod<bool>('requestNotificationPermission');
      return ok ?? false;
    } catch (e) {
      debugPrint('KeepAlive notification permission failed: $e');
      return false;
    }
  }

  Future<void> openOverlayPermissionSettings() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod<void>('openOverlayPermissionSettings');
    } catch (e) {
      debugPrint('KeepAlive overlay settings failed: $e');
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Sync early on inactive so FGS can start while still allowed under
    // Android 12+ background start restrictions. Do not tear down sessions.
    if (state == AppLifecycleState.inactive) {
      debugPrint('KeepAlive lifecycle=inactive → sync+ensure');
      _syncNative();
      ensureKeepAlive();
    } else if (state == AppLifecycleState.paused) {
      debugPrint('KeepAlive lifecycle=paused → ensure');
      ensureKeepAlive();
    } else if (state == AppLifecycleState.resumed) {
      debugPrint('KeepAlive lifecycle=resumed → sync');
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

final keepAliveControllerProvider =
    ChangeNotifierProvider<KeepAliveController>((ref) {
  final prefs = ref.watch(sharedPreferencesProvider);
  final c = KeepAliveController(prefs);
  ref.onDispose(c.dispose);
  return c;
});
