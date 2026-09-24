import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../core/ime/ime_controller.dart';
import '../../core/session/session_manager.dart';
import '../../core/session/terminal_session.dart';
import '../../data/host_profile.dart';
import '../files/files_page.dart';
import '../pad/pad_breakpoints.dart';
import 'extra_keys.dart';
import 'hardware_keyboard_handler.dart';

/// Soft IME style: visible-password reduces suggestions / smart punctuation.
const kTerminalKeyboardType = TextInputType.visiblePassword;

/// Multi-tab SSH/Telnet terminal workspace. Sessions live in [SessionManager].
///
/// Use [embedded] when hosted inside [PadShell] (no outer Scaffold / back).
class TerminalPage extends ConsumerStatefulWidget {
  const TerminalPage({
    super.key,
    this.embedded = false,
    this.onOpenFiles,
  });

  final bool embedded;

  /// When embedded, PadShell may prefer switching pane instead of pushing.
  final VoidCallback? onOpenFiles;

  @override
  ConsumerState<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends ConsumerState<TerminalPage>
    with WidgetsBindingObserver {
  final _terminalFocus = FocusNode();
  ActiveTerminalKeyboard? _keyboard;
  bool _handlerRegistered = false;
  bool _hwKeyboard = false;
  Size? _lastViewSize;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKey);
    _handlerRegistered = true;
    WidgetsBinding.instance.addPostFrameCallback((_) => _refreshHwKeyboard());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    if (_handlerRegistered) {
      HardwareKeyboard.instance.removeHandler(_onKey);
    }
    _terminalFocus.dispose();
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    final kb = _keyboard;
    if (kb == null) return false;
    return kb.handle(event);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _clearImeComposition();
      _refreshHwKeyboard();
    }
  }

  @override
  void didChangeMetrics() {
    // Keyboard plug / rotation: re-fit rows/cols (TerminalView autoResize) +
    // force a rebuild so PTY onResize fires with new dimensions.
    final view = View.of(context);
    final size = view.physicalSize;
    if (_lastViewSize != size) {
      _lastViewSize = size;
      if (mounted) {
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _nudgeTerminalResize();
        });
      }
    }
    _refreshHwKeyboard();
  }

  void _nudgeTerminalResize() {
    final active = ref.read(sessionManagerProvider).active;
    if (active == null) return;
    // Re-assert current size to trigger dartssh2 / telnet NAWS when layout
    // settled after a metrics change.
    final t = active.terminal;
    final w = t.viewWidth;
    final h = t.viewHeight;
    if (w > 0 && h > 0) {
      t.resize(w, h);
    }
  }

  Future<void> _refreshHwKeyboard() async {
    final ime = ref.read(imeControllerProvider);
    final hw = await ime.hasHardwareKeyboard();
    if (mounted && hw != _hwKeyboard) {
      setState(() => _hwKeyboard = hw);
    }
  }

  Future<void> _clearImeComposition() async {
    if (!_terminalFocus.canRequestFocus) return;
    _terminalFocus.unfocus();
    await ref.read(imeControllerProvider).restartInput();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _terminalFocus.requestFocus();
    });
  }

  Future<void> _openFiles() async {
    if (widget.onOpenFiles != null) {
      widget.onOpenFiles!();
      return;
    }
    final active = ref.read(sessionManagerProvider).active;
    if (active == null) return;
    if (active.profile.protocol != HostProtocol.ssh &&
        active.profile.protocol != HostProtocol.sftp) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('仅 SSH/SFTP 会话可打开文件')),
      );
      return;
    }
    await openFileBrowser(context, ref, active.profile.asSftp());
  }

  Future<void> _disconnectActive() async {
    final mgr = ref.read(sessionManagerProvider);
    final active = mgr.active;
    if (active == null) return;
    await mgr.close(active.id);
    if (mounted && mgr.sessions.isEmpty && !widget.embedded) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _disconnectAll() async {
    await ref.read(sessionManagerProvider).closeAll();
    if (mounted && !widget.embedded) {
      Navigator.of(context).maybePop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final mgr = ref.watch(sessionManagerProvider);
    final active = mgr.active;

    _keyboard = active == null
        ? null
        : ActiveTerminalKeyboard(
            terminal: active.terminal,
            session: active,
            isActive: () => mounted && mgr.active?.id == active.id,
          );

    final body = active == null
        ? const Center(child: Text('选择主机连接，或等待会话准备…'))
        : Column(
            children: [
              _StatusBanner(session: active),
              Expanded(
                child: TerminalView(
                  active.terminal,
                  focusNode: _terminalFocus,
                  autofocus: true,
                  backgroundOpacity: 1,
                  padding: const EdgeInsets.all(4),
                  keyboardType: kTerminalKeyboardType,
                  deleteDetection: true,
                  hardwareKeyboardOnly: _hwKeyboard,
                ),
              ),
              ExtraKeysBar(
                terminal: active.terminal,
                session: active,
                hideForHardwareKeyboard: _hwKeyboard,
              ),
            ],
          );

    final actions = <Widget>[
      if (active != null)
        IconButton(
          tooltip: '断开当前',
          icon: const Icon(Icons.link_off),
          constraints: const BoxConstraints(
            minWidth: PadBreakpoints.minTap,
            minHeight: PadBreakpoints.minTap,
          ),
          onPressed: _disconnectActive,
        ),
      PopupMenuButton<String>(
        onSelected: (v) async {
          if (v == 'all') await _disconnectAll();
          if (v == 'ime') await _clearImeComposition();
          if (v == 'files') await _openFiles();
        },
        itemBuilder: (_) => const [
          PopupMenuItem(value: 'files', child: Text('打开文件 (SFTP)')),
          PopupMenuItem(value: 'ime', child: Text('清除输入法组字')),
          PopupMenuItem(value: 'all', child: Text('断开全部会话')),
        ],
      ),
    ];

    if (widget.embedded) {
      return Column(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: SafeArea(
              bottom: false,
              child: SizedBox(
                height: PadBreakpoints.minTap,
                child: Row(
                  children: [
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        active?.title ?? '终端',
                        style: Theme.of(context).textTheme.titleMedium,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    ...actions,
                  ],
                ),
              ),
            ),
          ),
          if (mgr.sessions.length > 1)
            SizedBox(
              height: 40,
              child: _SessionTabBar(manager: mgr),
            ),
          Expanded(child: body),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(active?.title ?? '终端'),
        actions: actions,
        bottom: mgr.sessions.length > 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(40),
                child: _SessionTabBar(manager: mgr),
              )
            : null,
      ),
      body: body,
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.session});

  final TerminalSession session;

  @override
  Widget build(BuildContext context) {
    final (label, color) = switch (session.phase) {
      SessionPhase.connecting => ('连接中…', Colors.amber),
      SessionPhase.connected => ('已连接（保活中）', Colors.green),
      SessionPhase.disconnected => ('已断开', Colors.grey),
      SessionPhase.error => (
          '错误: ${session.errorMessage ?? ""}',
          Theme.of(context).colorScheme.error,
        ),
    };
    return Material(
      color: color.withValues(alpha: 0.15),
      child: SizedBox(
        width: double.infinity,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Text(label, style: TextStyle(color: color, fontSize: 12)),
        ),
      ),
    );
  }
}

class _SessionTabBar extends StatelessWidget {
  const _SessionTabBar({required this.manager});

  final SessionManager manager;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        itemCount: manager.sessions.length,
        itemBuilder: (context, i) {
          final s = manager.sessions[i];
          final selected = s.id == manager.activeId;
          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 4),
            child: InputChip(
              selected: selected,
              label: Text(s.title, overflow: TextOverflow.ellipsis),
              onPressed: () => manager.setActive(s.id),
              onDeleted: () async {
                await manager.close(s.id);
                if (context.mounted &&
                    manager.sessions.isEmpty &&
                    Navigator.of(context).canPop()) {
                  Navigator.of(context).maybePop();
                }
              },
            ),
          );
        },
      ),
    );
  }
}
