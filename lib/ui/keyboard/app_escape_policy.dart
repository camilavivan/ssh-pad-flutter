import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

/// Global Esc policy for SSH Pad.
///
/// Flutter [WidgetsApp] maps Escape → [DismissIntent], which can pop routes or
/// finish the Activity on the root route. Hardware Esc must **never** act as
/// system / Flutter Back in this app.
///
/// Installed as a [FocusManager] early key handler (before focus tree /
/// Shortcuts) plus a MaterialApp shortcut override:
/// 1. Terminal sink active + focused → send ESC (0x1b) to PTY once, consume.
/// 2. Barrier-dismissible [PopupRoute] on top → [Navigator.maybePop] that
///    overlay only (menus / intentional soft dialogs), consume.
/// 3. Everywhere else → consume Escape (no shell pop / no leave-app).
///
/// Does **not** intercept [LogicalKeyboardKey.goBack] (hardware Back / gesture).
class AppEscapePolicy {
  AppEscapePolicy._();

  static TerminalEscapeSink? _terminalSink;
  static GlobalKey<NavigatorState>? _navigatorKey;
  static bool _installed = false;

  static TerminalEscapeSink? get terminalSink => _terminalSink;

  /// Wire the app [navigatorKey] so popup-route inspection / overlay pop works.
  static void bindNavigator(GlobalKey<NavigatorState> key) {
    _navigatorKey = key;
  }

  /// Register the interactive terminal as the Esc → PTY sink (or null).
  static void setTerminalSink(TerminalEscapeSink? sink) {
    _terminalSink = sink;
  }

  /// Install once on app start (idempotent).
  static void install() {
    if (_installed) return;
    _installed = true;
    FocusManager.instance.addEarlyKeyEventHandler(handleEarlyKeyEvent);
  }

  @visibleForTesting
  static void uninstall() {
    if (!_installed) return;
    _installed = false;
    FocusManager.instance.removeEarlyKeyEventHandler(handleEarlyKeyEvent);
    _terminalSink = null;
  }

  /// MaterialApp shortcuts: replace Escape→[DismissIntent] with a stop-propagation
  /// no-op so WidgetsApp cannot treat Esc as Back / root [SystemNavigator.pop].
  /// Overlay dismiss is performed explicitly in [handleEarlyKeyEvent].
  static Map<ShortcutActivator, Intent> shortcutsWithoutEscapeBack(
    Map<ShortcutActivator, Intent> base,
  ) {
    final out = <ShortcutActivator, Intent>{};
    for (final entry in base.entries) {
      final activator = entry.key;
      if (activator is SingleActivator &&
          activator.trigger == LogicalKeyboardKey.escape &&
          !activator.control &&
          !activator.shift &&
          !activator.alt &&
          !activator.meta) {
        out[activator] = const DoNothingAndStopPropagationIntent();
        continue;
      }
      out[activator] = entry.value;
    }
    out.putIfAbsent(
      const SingleActivator(LogicalKeyboardKey.escape),
      () => const DoNothingAndStopPropagationIntent(),
    );
    return out;
  }

  /// FocusManager early handler — before focus tree / Shortcuts.
  static KeyEventResult handleEarlyKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }
    if (event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }

    final sink = _terminalSink;
    if (sink != null && sink.shouldReceiveEscape()) {
      // One Esc per physical down (ignore repeat flood into PTY).
      if (event is KeyDownEvent) {
        sink.sendEscape();
      }
      return KeyEventResult.handled;
    }

    if (event is KeyDownEvent && isBarrierDismissiblePopupShowing()) {
      // Close the overlay only — never the main shell.
      _navigatorKey?.currentState?.maybePop();
      return KeyEventResult.handled;
    }

    return KeyEventResult.handled;
  }

  /// Pure decision helper for unit tests.
  static EscapeDisposition disposition({
    required bool terminalShouldReceive,
    required bool barrierDismissiblePopup,
  }) {
    if (terminalShouldReceive) return EscapeDisposition.sendToPty;
    if (barrierDismissiblePopup) return EscapeDisposition.allowOverlayDismiss;
    return EscapeDisposition.consume;
  }

  static bool isBarrierDismissiblePopupShowing() {
    final nav = _navigatorKey?.currentState;
    if (nav == null) return false;
    var found = false;
    // Inspection only — popUntil with always-true predicate does not pop.
    nav.popUntil((route) {
      if (route.isCurrent &&
          route is PopupRoute &&
          route.barrierDismissible) {
        found = true;
      }
      return true;
    });
    return found;
  }
}

enum EscapeDisposition {
  sendToPty,
  allowOverlayDismiss,
  consume,
}

/// Registered by [TerminalPage] while an interactive session can take Esc.
class TerminalEscapeSink {
  TerminalEscapeSink({
    required this.terminal,
    required this.isActive,
    required this.hasTerminalFocus,
  });

  final Terminal terminal;
  final bool Function() isActive;
  final bool Function() hasTerminalFocus;

  bool shouldReceiveEscape() => isActive() && hasTerminalFocus();

  void sendEscape() {
    terminal.keyInput(TerminalKey.escape);
    HapticFeedback.lightImpact();
  }
}
