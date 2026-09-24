import 'dart:io' show Platform;

import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

/// Hardware / Bluetooth keyboard handler for the *active* terminal only.
///
/// Patterns inspired by ServerBox keyboard handling — rewritten in-house:
/// - Only the visible/active session registers interest (caller gates).
/// - Do **not** handle clipboard chords here (TerminalView already does);
///   otherwise Cmd/Ctrl+V pastes twice.
/// - Escape is forwarded to the terminal and consumed.
class ActiveTerminalKeyboard {
  ActiveTerminalKeyboard({
    required this.terminal,
    required this.isActive,
  });

  final Terminal terminal;
  final bool Function() isActive;

  bool get _appleKeyboard => Platform.isIOS || Platform.isMacOS;

  /// Line-editing Command chords on Apple keyboards → Ctrl letters shells know.
  static final _commandChords = <LogicalKeyboardKey, int>{
    LogicalKeyboardKey.backspace: 0x55, // ^U
    LogicalKeyboardKey.arrowLeft: 0x41, // ^A
    LogicalKeyboardKey.arrowRight: 0x45, // ^E
  };

  bool handle(KeyEvent event) {
    if (!isActive()) return false;
    if (event is! KeyDownEvent) return false;

    // Clipboard chords: leave to TerminalView shortcuts (no double paste).
    if (_appleKeyboard && HardwareKeyboard.instance.isMetaPressed) {
      final letter = _commandChords[event.logicalKey];
      if (letter != null) {
        terminal.charInput(letter, ctrl: true);
        return true;
      }
      return false;
    }

    if (event.logicalKey == LogicalKeyboardKey.escape) {
      terminal.keyInput(TerminalKey.escape);
      HapticFeedback.lightImpact();
      return true;
    }
    return false;
  }
}
