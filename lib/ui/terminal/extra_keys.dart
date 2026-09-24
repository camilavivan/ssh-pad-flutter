import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../../core/session/ssh_terminal_session.dart';

/// Pad-friendly ExtraKeys strip: Esc, Tab, Ctrl (sticky), arrows, Ctrl-C.
class ExtraKeysBar extends StatefulWidget {
  const ExtraKeysBar({
    super.key,
    required this.terminal,
    this.session,
  });

  final Terminal terminal;
  final SshTerminalSession? session;

  @override
  State<ExtraKeysBar> createState() => _ExtraKeysBarState();
}

class _ExtraKeysBarState extends State<ExtraKeysBar> {
  bool _ctrlSticky = false;

  void _tap(VoidCallback action) {
    HapticFeedback.selectionClick();
    action();
  }

  void _sendKey(TerminalKey key) {
    _tap(() {
      widget.terminal.keyInput(
        key,
        ctrl: _ctrlSticky,
      );
      if (_ctrlSticky) setState(() => _ctrlSticky = false);
    });
  }

  void _sendChar(int code) {
    _tap(() {
      widget.terminal.charInput(code, ctrl: _ctrlSticky);
      if (_ctrlSticky) setState(() => _ctrlSticky = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget chip(String label, VoidCallback onPressed, {bool active = false}) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: active ? scheme.primaryContainer : scheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
          child: InkWell(
            borderRadius: BorderRadius.circular(6),
            onTap: onPressed,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: active ? scheme.onPrimaryContainer : scheme.onSurface,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Material(
      elevation: 1,
      color: scheme.surface,
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 44,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            children: [
              chip('Esc', () => _sendKey(TerminalKey.escape)),
              chip('Tab', () => _sendKey(TerminalKey.tab)),
              chip(
                'Ctrl',
                () => setState(() => _ctrlSticky = !_ctrlSticky),
                active: _ctrlSticky,
              ),
              chip('↑', () => _sendKey(TerminalKey.arrowUp)),
              chip('↓', () => _sendKey(TerminalKey.arrowDown)),
              chip('←', () => _sendKey(TerminalKey.arrowLeft)),
              chip('→', () => _sendKey(TerminalKey.arrowRight)),
              chip('Ctrl-C', () {
                _tap(() {
                  final s = widget.session;
                  if (s != null && s.isConnected) {
                    // Prefer ETX on the wire for interactive shells; kill as backup.
                    widget.terminal.charInput(0x43, ctrl: true); // ^C
                  } else {
                    _sendChar(0x43);
                  }
                });
              }),
              chip('Ctrl-D', () => _sendChar(0x44)),
              chip('Ctrl-Z', () => _sendChar(0x5a)),
            ],
          ),
        ),
      ),
    );
  }
}
