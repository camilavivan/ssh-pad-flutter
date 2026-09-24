import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../../core/session/terminal_session.dart';

/// Hardware / Bluetooth keyboard handler for the *active* terminal only.
///
/// Patterns inspired by ServerBox keyboard handling — rewritten in-house:
/// - Only the visible/active session registers interest (caller gates).
/// - Do **not** handle clipboard chords here (TerminalView already does);
///   otherwise Cmd/Ctrl+V pastes twice.
/// - Plain **Ctrl-C = SIGINT** (ETX / channel signal), never copy.
/// - Escape is **not** handled here — [AppEscapePolicy] is the single Esc→PTY
///   path (avoids double 0x1b and Flutter Escape→Back).
class ActiveTerminalKeyboard {
  ActiveTerminalKeyboard({
    required this.terminal,
    required this.isActive,
    this.session,
  });

  final Terminal terminal;
  final bool Function() isActive;
  final TerminalSession? session;

  bool get _appleKeyboard => Platform.isIOS || Platform.isMacOS;

  /// Line-editing Command chords on Apple keyboards → Ctrl letters shells know.
  static final _commandChords = <LogicalKeyboardKey, int>{
    LogicalKeyboardKey.backspace: 0x55, // ^U
    LogicalKeyboardKey.arrowLeft: 0x41, // A
    LogicalKeyboardKey.arrowRight: 0x45, // E
  };

  bool handle(KeyEvent event) {
    if (!isActive()) return false;
    if (event is! KeyDownEvent) return false;

    // Clipboard chords: leave to TerminalView shortcuts (no double paste).
    // Copy on Android/desktop is Ctrl+Shift+C — plain Ctrl+C must stay SIGINT.
    if (_appleKeyboard && HardwareKeyboard.instance.isMetaPressed) {
      final letter = _commandChords[event.logicalKey];
      if (letter != null) {
        terminal.charInput(letter, ctrl: true);
        return true;
      }
      return false;
    }

    // Ctrl-C → interrupt (SIGINT / ETX). Consume so nothing treats it as copy.
    if (HardwareKeyboard.instance.isControlPressed &&
        !HardwareKeyboard.instance.isShiftPressed &&
        !HardwareKeyboard.instance.isAltPressed &&
        !HardwareKeyboard.instance.isMetaPressed &&
        event.logicalKey == LogicalKeyboardKey.keyC) {
      final s = session;
      if (s != null && s.isConnected) {
        s.sendInterrupt();
      } else {
        terminal.charInput(0x43, ctrl: true);
      }
      return true;
    }

    // Escape: owned by AppEscapePolicy (global). Do not send here.
    return false;
  }
}
