import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session/session_backend.dart';
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
    if (!h.protocol.isMvp) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('不支持的协议：${h.protocol.label}，请编辑主机改为 SSH/SFTP/TELNET/FTP')),
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
    // Attaches SFTP channel on the existing SSHClient (no second auth).
    await mgr.openFiles(active.profile);
  }

  /// When user switches to Files while an SSH shell is up, attach SFTP
  /// on the shared connection instead of showing an empty stub.
  Future<void> _ensureFilesForActiveSsh() async {
    final mgr = ref.read(sessionManagerProvider);
    if (mgr.files.isNotEmpty) return;
    final active = mgr.active;
    if (active == null) return;
    if (active.profile.protocol != HostProtocol.ssh) return;
    if (active.phase != SessionPhase.connected &&
        active.phase != SessionPhase.connecting) {
      return;
    }
    await mgr.openFiles(active.profile);
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
          // Kick off attach if an SSH shell is already connected.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _ensureFilesForActiveSsh();
          });
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.folder_off_outlined, size: 40,
                    color: Theme.of(context).colorScheme.onSurfaceVariant),
                const SizedBox(height: 12),
                const Text('暂无文件会话', style: TextStyle(fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(
                  '用 SFTP/FTP 主机连接，或从已连接的 SSH 打开文件',
                  style: Theme.of(context).textTheme.bodySmall,
                  textAlign: TextAlign.center,
                ),
              ],
            ),
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
        final scheme = Theme.of(context).colorScheme;
        return Scaffold(
          body: SafeArea(
            child: Row(
              children: [
                NavigationRail(
                  selectedIndex: _railIndex(_section),
                  onDestinationSelected: (i) {
                    setState(() => _section = _sectionFromRail(i));
                  },
                  // Theme supplies minWidth 56 + selected labels (ServerBox-like).
                  labelType: NavigationRailLabelType.selected,
                  groupAlignment: -0.9,
                  backgroundColor: scheme.surfaceContainerHighest,
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
                VerticalDivider(
                  width: 1,
                  color: scheme.outline.withValues(alpha: 0.45),
                ),
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
