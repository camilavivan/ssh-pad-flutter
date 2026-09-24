import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:xterm/xterm.dart';

import '../../core/session/session_manager.dart';
import '../../core/session/terminal_session.dart';
import '../../data/host_profile.dart';
import '../files/files_page.dart';
import 'extra_keys.dart';
import 'hardware_keyboard_handler.dart';

/// Multi-tab SSH terminal host. Sessions live in [SessionManager].
class TerminalPage extends ConsumerStatefulWidget {
  const TerminalPage({super.key});

  @override
  ConsumerState<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends ConsumerState<TerminalPage>
    with WidgetsBindingObserver {
  final _terminalFocus = FocusNode();
  ActiveTerminalKeyboard? _keyboard;
  bool _handlerRegistered = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    HardwareKeyboard.instance.addHandler(_onKey);
    _handlerRegistered = true;
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
    }
  }

  void _clearImeComposition() {
    if (!_terminalFocus.canRequestFocus) return;
    _terminalFocus.unfocus();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _terminalFocus.requestFocus();
    });
  }


  Future<void> _openFiles() async {
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
    if (mounted && mgr.sessions.isEmpty) {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _disconnectAll() async {
    await ref.read(sessionManagerProvider).closeAll();
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final mgr = ref.watch(sessionManagerProvider);
    final active = mgr.active;

    _keyboard = active == null
        ? null
        : ActiveTerminalKeyboard(
            terminal: active.terminal,
            isActive: () => mounted && mgr.active?.id == active.id,
          );

    return Scaffold(
      appBar: AppBar(
        title: Text(active?.title ?? '终端'),
        actions: [
          if (active != null)
            IconButton(
              tooltip: '断开当前',
              icon: const Icon(Icons.link_off),
              onPressed: _disconnectActive,
            ),
          PopupMenuButton<String>(
            onSelected: (v) async {
              if (v == 'all') await _disconnectAll();
              if (v == 'ime') _clearImeComposition();
              if (v == 'files') await _openFiles();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'files', child: Text('打开文件 (SFTP)')),
              PopupMenuItem(value: 'ime', child: Text('清除输入法组字')),
              PopupMenuItem(value: 'all', child: Text('断开全部会话')),
            ],
          ),
        ],
        bottom: mgr.sessions.length > 1
            ? PreferredSize(
                preferredSize: const Size.fromHeight(40),
                child: _SessionTabBar(manager: mgr),
              )
            : null,
      ),
      body: active == null
          ? const Center(child: Text('正在准备会话…'))
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
                  ),
                ),
                ExtraKeysBar(
                  terminal: active.terminal,
                  session: active,
                ),
              ],
            ),
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
                if (context.mounted && manager.sessions.isEmpty) {
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
