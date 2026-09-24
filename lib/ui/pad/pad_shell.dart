import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session/session_manager.dart';
import '../../data/host_profile.dart';
import '../../data/host_store.dart';
import '../files/files_page.dart';
import '../placeholders.dart';
import '../terminal/terminal_page.dart';
import 'drag_divider.dart';
import 'left_pane.dart';
import 'pad_breakpoints.dart';

const _kLeftWidthKey = 'pad_left_width_v1';

/// Adaptive Pad shell: ≥600dp split + drag divider; narrow NavigationRail.
class PadShell extends ConsumerStatefulWidget {
  const PadShell({super.key});

  @override
  ConsumerState<PadShell> createState() => _PadShellState();
}

class _PadShellState extends ConsumerState<PadShell> {
  PadSection _section = PadSection.hosts;
  double _leftWidth = PadBreakpoints.leftDefault;

  @override
  void initState() {
    super.initState();
    _loadLeftWidth();
  }

  Future<void> _loadLeftWidth() async {
    final prefs = ref.read(sharedPreferencesProvider);
    final v = prefs.getDouble(_kLeftWidthKey);
    if (v != null && mounted) {
      setState(() => _leftWidth = v);
    }
  }

  Future<void> _persistLeftWidth() async {
    final prefs = ref.read(sharedPreferencesProvider);
    await prefs.setDouble(_kLeftWidthKey, _leftWidth);
  }

  Future<void> _connectHost(HostProfile h) async {
    if (h.protocol.isDeferred) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${h.protocol.label} 将在后续版本实现（稍后）')),
      );
      return;
    }
    final mgr = ref.read(sessionManagerProvider);
    if (h.protocol == HostProtocol.sftp || h.protocol == HostProtocol.ftp) {
      setState(() => _section = PadSection.files);
      await mgr.openFiles(h);
      return;
    }
    // SSH / Telnet — switch pane instead of stacking /terminal routes.
    setState(() => _section = PadSection.terminal);
    await mgr.openTerminal(h);
  }

  Future<void> _openFilesFromTerminal() async {
    final mgr = ref.read(sessionManagerProvider);
    final active = mgr.active;
    if (active == null) return;
    if (active.profile.protocol != HostProtocol.ssh &&
        active.profile.protocol != HostProtocol.sftp) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('仅 SSH/SFTP 会话可打开文件')),
      );
      return;
    }
    setState(() => _section = PadSection.files);
    // Reuse existing file session for this host if any; else open.
    final existing = mgr.files.where((f) => f.profile.id == active.profile.id);
    if (existing.isEmpty) {
      await mgr.openFiles(active.profile.asSftp());
    } else {
      mgr.setActiveFile(existing.first.id);
    }
  }

  Widget _rightContent() {
    switch (_section) {
      case PadSection.terminal:
        return TerminalPage(
          embedded: true,
          onOpenFiles: _openFilesFromTerminal,
        );
      case PadSection.files:
        final mgr = ref.watch(sessionManagerProvider);
        if (mgr.files.isEmpty) {
          return const Center(
            child: Text('暂无文件会话\n用 SFTP/FTP 主机连接，或从终端打开文件'),
          );
        }
        return FilesPage(
          key: ValueKey(mgr.activeFileId ?? mgr.files.last.id),
          sessionId: mgr.activeFileId,
          embedded: true,
        );
      case PadSection.settings:
        return const KeepAliveSettingsPage(embedded: true);
      case PadSection.hosts:
        return LeftPane(
          section: _section,
          onSection: (s) => setState(() => _section = s),
          onConnectHost: _connectHost,
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final split = PadBreakpoints.isSplit(constraints);
        if (split) {
          final left = clampLeftWidth(_leftWidth, constraints.maxWidth);
          return Scaffold(
            body: Row(
              children: [
                SizedBox(
                  width: left,
                  child: LeftPane(
                    section: _section == PadSection.hosts
                        ? PadSection.terminal
                        : _section,
                    onSection: (s) => setState(() => _section = s),
                    onConnectHost: _connectHost,
                  ),
                ),
                DragDivider(
                  onDrag: (dx) {
                    setState(() {
                      _leftWidth =
                          clampLeftWidth(left + dx, constraints.maxWidth);
                    });
                  },
                  onDragEnd: _persistLeftWidth,
                ),
                Expanded(
                  child: _section == PadSection.hosts
                      ? TerminalPage(
                          embedded: true,
                          onOpenFiles: _openFilesFromTerminal,
                        )
                      : _rightContent(),
                ),
              ],
            ),
          );
        }

        // Narrow: NavigationRail + body (don't break phones).
        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                NavigationRail(
                  selectedIndex: _railIndex(_section),
                  onDestinationSelected: (i) {
                    setState(() => _section = _sectionFromRail(i));
                  },
                  labelType: NavigationRailLabelType.all,
                  destinations: const [
                    NavigationRailDestination(
                      icon: Icon(Icons.dns_outlined),
                      selectedIcon: Icon(Icons.dns),
                      label: Text('主机'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.terminal_outlined),
                      selectedIcon: Icon(Icons.terminal),
                      label: Text('终端'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.folder_outlined),
                      selectedIcon: Icon(Icons.folder),
                      label: Text('文件'),
                    ),
                    NavigationRailDestination(
                      icon: Icon(Icons.settings_outlined),
                      selectedIcon: Icon(Icons.settings),
                      label: Text('设置'),
                    ),
                  ],
                ),
                const VerticalDivider(width: 1),
                Expanded(child: _narrowBody()),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _narrowBody() {
    switch (_section) {
      case PadSection.hosts:
        return LeftPane(
          section: _section,
          onSection: (s) => setState(() => _section = s),
          onConnectHost: _connectHost,
          compactHeader: true,
        );
      case PadSection.terminal:
      case PadSection.files:
      case PadSection.settings:
        return _rightContent();
    }
  }

  int _railIndex(PadSection s) => switch (s) {
        PadSection.hosts => 0,
        PadSection.terminal => 1,
        PadSection.files => 2,
        PadSection.settings => 3,
      };

  PadSection _sectionFromRail(int i) => switch (i) {
        0 => PadSection.hosts,
        1 => PadSection.terminal,
        2 => PadSection.files,
        _ => PadSection.settings,
      };
}
