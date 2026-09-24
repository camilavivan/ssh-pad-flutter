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
/// Shortcuts) plus MaterialApp shortcut / action overrides:
/// 1. Barrier-dismissible [PopupRoute] on top → [Navigator.maybePop] that
///    overlay only (menus / soft dialogs). Overlay wins so Esc always closes
///    a menu even if a terminal session is active underneath.
/// 2. Terminal sink active and allowed to receive → send ESC (0x1b) to PTY
///    once per physical down (no KeyRepeat flood; no TerminalView double-send).
/// 3. Everywhere else → consume Escape (no shell pop / no leave-app).
///
/// Also maps **Ctrl+[** → Esc when the terminal sink may receive (classic vi
/// alias). xterm's Ctrl handler only covers A–Z, so this is required.
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

  /// MaterialApp actions: neutralize [DismissIntent] even if something invokes
  /// it without going through our Esc shortcut override.
  static Map<Type, Action<Intent>> actionsWithoutEscapeBack(
    Map<Type, Action<Intent>> base,
  ) {
    return <Type, Action<Intent>>{
      ...base,
      DismissIntent: DoNothingAction(consumesKey: true),
    };
  }

  /// FocusManager early handler — before focus tree / Shortcuts / TerminalView.
  static KeyEventResult handleEarlyKeyEvent(KeyEvent event) {
    if (event is! KeyDownEvent && event is! KeyRepeatEvent) {
      return KeyEventResult.ignored;
    }

    // Ctrl+[ → Esc alias for vi (xterm Ctrl handler is A–Z only).
    if (_isCtrlBracketLeft(event)) {
      final sink = _terminalSink;
      if (sink != null && sink.shouldReceiveEscape()) {
        if (event is KeyDownEvent) {
          sink.sendEscape();
        }
        return KeyEventResult.handled;
      }
      return KeyEventResult.ignored;
    }

    if (event.logicalKey != LogicalKeyboardKey.escape) {
      return KeyEventResult.ignored;
    }

    // Bare Esc only for policy paths; modified Esc is still consumed so it
    // cannot become Back, but is not forwarded as a plain 0x1b.
    final modified = HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed ||
        HardwareKeyboard.instance.isMetaPressed;

    if (!modified &&
        event is KeyDownEvent &&
        isBarrierDismissiblePopupShowing()) {
      // Close the overlay only — never the main shell / page route.
      _navigatorKey?.currentState?.maybePop();
      return KeyEventResult.handled;
    }

    final sink = _terminalSink;
    if (!modified && sink != null && sink.shouldReceiveEscape()) {
      // One Esc per physical down (ignore repeat flood into PTY).
      if (event is KeyDownEvent) {
        sink.sendEscape();
      }
      return KeyEventResult.handled;
    }

    // Consume (including modified Esc) — never DismissIntent / Back.
    return KeyEventResult.handled;
  }

  static bool _isCtrlBracketLeft(KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.bracketLeft) return false;
    if (!HardwareKeyboard.instance.isControlPressed) return false;
    if (HardwareKeyboard.instance.isShiftPressed) return false;
    if (HardwareKeyboard.instance.isAltPressed) return false;
    if (HardwareKeyboard.instance.isMetaPressed) return false;
    return true;
  }

  /// Pure decision helper for unit tests (mirrors [handleEarlyKeyEvent] order).
  static EscapeDisposition disposition({
    required bool terminalShouldReceive,
    required bool barrierDismissiblePopup,
  }) {
    // Overlay first — menus must close even with an active terminal underneath.
    if (barrierDismissiblePopup) return EscapeDisposition.allowOverlayDismiss;
    if (terminalShouldReceive) return EscapeDisposition.sendToPty;
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

  /// True when an [EditableText] (TextField / form) owns primary focus.
  /// Used so Esc while editing a host form is not injected into a background PTY.
  static bool primaryFocusIsEditableText() {
    final primary = FocusManager.instance.primaryFocus;
    final ctx = primary?.context;
    if (ctx == null) return false;
    if (ctx.widget is EditableText) return true;
    return ctx.findAncestorWidgetOfExactType<EditableText>() != null;
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

  /// Deliver Esc to PTY when the session is active and either the terminal has
  /// focus, or focus is on non-editable chrome (pad split left pane, tab bar).
  /// Skip when a text field owns focus (host editor / search) so typing Esc
  /// there does not poke a background shell.
  bool shouldReceiveEscape() {
    if (!isActive()) return false;
    if (hasTerminalFocus()) return true;
    return !AppEscapePolicy.primaryFocusIsEditableText();
  }

  void sendEscape() {
    terminal.keyInput(TerminalKey.escape);
    HapticFeedback.lightImpact();
  }
}
