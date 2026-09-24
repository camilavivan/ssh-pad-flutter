import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:xterm/xterm.dart';

import '../../core/session/terminal_session.dart';
import '../pad/pad_breakpoints.dart';

/// Pad ExtraKeys strip styled closer to ServerBox virt-key chrome.
///
/// When [hideForHardwareKeyboard] is true the bar collapses (Bluetooth plugged).
class ExtraKeysBar extends StatefulWidget {
  const ExtraKeysBar({
    super.key,
    required this.terminal,
    this.session,
    this.hideForHardwareKeyboard = false,
  });

  final Terminal terminal;
  final TerminalSession? session;
  final bool hideForHardwareKeyboard;

  @override
  State<ExtraKeysBar> createState() => _ExtraKeysBarState();
}

class _ExtraKeysBarState extends State<ExtraKeysBar> {
  bool _ctrlSticky = false;
  bool _altSticky = false;

  void _tap(VoidCallback action) {
    HapticFeedback.selectionClick();
    action();
  }

  void _sendKey(TerminalKey key) {
    _tap(() {
      widget.terminal.keyInput(
        key,
        ctrl: _ctrlSticky,
        alt: _altSticky,
      );
      _clearMods();
    });
  }

  void _sendChar(int code) {
    _tap(() {
      widget.terminal.charInput(code, ctrl: _ctrlSticky, alt: _altSticky);
      _clearMods();
    });
  }

  void _clearMods() {
    if (_ctrlSticky || _altSticky) {
      setState(() {
        _ctrlSticky = false;
        _altSticky = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    if (widget.hideForHardwareKeyboard) {
      return const SizedBox.shrink();
    }

    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final barBg = dark ? const Color(0xFF161B22) : const Color(0xFFEEF1F4);
    final keyBg = dark ? const Color(0xFF21262D) : Colors.white;
    final keyBorder = dark ? const Color(0xFF30363D) : const Color(0xFFD0D7DE);
    final activeBg = scheme.primary.withValues(alpha: 0.22);
    final activeBorder = scheme.primary;

    Widget key(
      String label,
      VoidCallback onPressed, {
      bool active = false,
      double minWidth = 44,
    }) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Material(
          color: active ? activeBg : keyBg,
          borderRadius: BorderRadius.circular(7),
          child: InkWell(
            borderRadius: BorderRadius.circular(7),
            onTap: onPressed,
            child: Container(
              constraints: BoxConstraints(
                minWidth: minWidth,
                minHeight: PadBreakpoints.minTap - 8,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(7),
                border: Border.all(color: active ? activeBorder : keyBorder),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              alignment: Alignment.center,
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12.5,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'monospace',
                  letterSpacing: 0.2,
                  color: active ? scheme.primary : scheme.onSurface,
                  height: 1,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Material(
      color: barBg,
      elevation: 2,
      child: SafeArea(
        top: false,
        child: Container(
          decoration: BoxDecoration(
            border: Border(top: BorderSide(color: keyBorder)),
          ),
          height: PadBreakpoints.minTap + 2,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
            children: [
              key('Esc', () => _sendKey(TerminalKey.escape)),
              key('Tab', () => _sendKey(TerminalKey.tab)),
              key(
                'Ctrl',
                () => setState(() => _ctrlSticky = !_ctrlSticky),
                active: _ctrlSticky,
                minWidth: 48,
              ),
              key(
                'Alt',
                () => setState(() => _altSticky = !_altSticky),
                active: _altSticky,
                minWidth: 44,
              ),
              key('↑', () => _sendKey(TerminalKey.arrowUp), minWidth: 40),
              key('↓', () => _sendKey(TerminalKey.arrowDown), minWidth: 40),
              key('←', () => _sendKey(TerminalKey.arrowLeft), minWidth: 40),
              key('→', () => _sendKey(TerminalKey.arrowRight), minWidth: 40),
              key('Home', () => _sendKey(TerminalKey.home), minWidth: 48),
              key('End', () => _sendKey(TerminalKey.end), minWidth: 44),
              key('^C', () {
                _tap(() {
                  final s = widget.session;
                  if (s != null && s.isConnected) {
                    s.sendInterrupt();
                  } else {
                    widget.terminal.charInput(0x43, ctrl: true);
                  }
                });
              }),
              key('^D', () => _sendChar(0x44)),
              key('^Z', () => _sendChar(0x5a)),
              key('|', () => _sendChar(0x7c), minWidth: 36),
              key('~', () => _sendChar(0x7e), minWidth: 36),
            ],
          ),
        ),
      ),
    );
  }
}
