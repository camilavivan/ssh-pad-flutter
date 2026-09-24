import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/session/session_manager.dart';
import '../../core/session/session_backend.dart';
import '../../data/host_profile.dart';
import '../../data/host_store.dart';
import '../theme.dart';
import '../host_editor.dart';
import '../placeholders.dart';
import 'pad_breakpoints.dart';

enum PadSection { hosts, terminal, files, settings }

/// Left / host list pane: node cards, live sessions, section chips.
class LeftPane extends ConsumerWidget {
  const LeftPane({
    super.key,
    required this.section,
    required this.onSection,
    required this.onConnectHost,
    this.compactHeader = false,
  });

  final PadSection section;
  final ValueChanged<PadSection> onSection;
  final Future<void> Function(HostProfile host) onConnectHost;
  final bool compactHeader;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hosts = ref.watch(hostListProvider);
    final mgr = ref.watch(sessionManagerProvider);
    final themeMode = ref.watch(themeModeProvider);
    final scheme = Theme.of(context).colorScheme;

    return Material(
      color: scheme.surface,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _Header(
            themeMode: themeMode,
            onToggleTheme: () {
              final next = themeMode == ThemeMode.dark
                  ? ThemeMode.light
                  : ThemeMode.dark;
              ref.read(themeModeProvider.notifier).state = next;
            },
            onSettings: () => onSection(PadSection.settings),
            compact: compactHeader,
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: Wrap(
              spacing: 4,
              children: [
                _NavChip(
                  label: '终端',
                  selected: section == PadSection.terminal,
                  onTap: () => onSection(PadSection.terminal),
                ),
                _NavChip(
                  label: '文件',
                  selected: section == PadSection.files,
                  enabled: mgr.files.isNotEmpty ||
                      mgr.active?.profile.protocol == HostProtocol.ssh,
                  onTap: () => onSection(PadSection.files),
                ),
                _NavChip(
                  label: '主机',
                  selected: section == PadSection.hosts,
                  onTap: () => onSection(PadSection.hosts),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(10, 0, 10, 16),
              children: [
                Text('节点', style: Theme.of(context).textTheme.labelLarge),
                const SizedBox(height: 6),
                if (hosts.isEmpty && mgr.sessions.isEmpty)
                  Text(
                    '还没有保存的主机',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                for (final h in hosts) ...[
                  _HostCard(
                    host: h,
                    sessionPhase: _phaseForHost(mgr, h),
                    selected: _isSelected(mgr, h),
                    onTap: () => onConnectHost(h),
                    onEdit: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => HostEditorPage(existing: h),
                        ),
                      );
                    },
                    onDelete: () =>
                        ref.read(hostListProvider.notifier).delete(h.id),
                    onCloseSession: () async {
                      final id = _sessionIdForHost(mgr, h);
                      if (id != null) await mgr.close(id);
                    },
                  ),
                  const SizedBox(height: 6),
                ],
                if (mgr.sessions.isNotEmpty) ...[
                  const Divider(height: 24),
                  Text('会话', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 6),
                  for (final s in mgr.sessions) ...[
                    _SessionCard(
                      title: s.keepAliveTitle,
                      phase: s.phase,
                      selected: s.id == mgr.activeId,
                      onSelect: () {
                        mgr.setActive(s.id);
                        onSection(PadSection.terminal);
                      },
                      onClose: () => mgr.close(s.id),
                    ),
                    const SizedBox(height: 6),
                  ],
                ],
                if (mgr.files.isNotEmpty) ...[
                  const Divider(height: 24),
                  Text('文件会话', style: Theme.of(context).textTheme.labelLarge),
                  const SizedBox(height: 6),
                  for (final f in mgr.files) ...[
                    _SessionCard(
                      title: f.keepAliveTitle,
                      phase: f.phase,
                      selected: f.id == mgr.activeFileId,
                      onSelect: () {
                        mgr.setActiveFile(f.id);
                        onSection(PadSection.files);
                      },
                      onClose: () => mgr.closeFile(f.id),
                    ),
                    const SizedBox(height: 6),
                  ],
                ],
              ],
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: FilledButton.tonalIcon(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(PadBreakpoints.minTap),
                ),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const HostEditorPage(),
                    ),
                  );
                },
                icon: const Icon(Icons.add),
                label: const Text('新建主机'),
              ),
            ),
          ),
        ],
      ),
    );
  }

  static SessionPhase? _phaseForHost(SessionManager mgr, HostProfile h) {
    for (final s in mgr.sessions) {
      if (s.profile.id == h.id) return s.phase;
    }
    for (final s in mgr.files) {
      if (s.profile.id == h.id) return s.phase;
    }
    return null;
  }

  static String? _sessionIdForHost(SessionManager mgr, HostProfile h) {
    for (final s in mgr.sessions) {
      if (s.profile.id == h.id) return s.id;
    }
    return null;
  }

  static bool _isSelected(SessionManager mgr, HostProfile h) {
    final a = mgr.active;
    if (a != null && a.profile.id == h.id) return true;
    final f = mgr.activeFile;
    if (f != null && f.profile.id == h.id) return true;
    return false;
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.themeMode,
    required this.onToggleTheme,
    required this.onSettings,
    required this.compact,
  });

  final ThemeMode themeMode;
  final VoidCallback onToggleTheme;
  final VoidCallback onSettings;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    // Top guard: SafeArea + floor so OEM zero-inset still leaves tappable chrome.
    final topInset = MediaQuery.paddingOf(context).top;
    final guard = topInset > 0 ? 0.0 : PadBreakpoints.statusBarFloor;
    return Padding(
      padding: EdgeInsets.only(top: guard),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: PadBreakpoints.minTap,
          child: Row(
            children: [
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  compact ? 'Pad' : 'SSH Pad',
                  style: Theme.of(context).textTheme.titleSmall,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                tooltip: '切换主题',
                constraints: const BoxConstraints(
                  minWidth: PadBreakpoints.minTap,
                  minHeight: PadBreakpoints.minTap,
                ),
                icon: Icon(
                  themeMode == ThemeMode.dark
                      ? Icons.light_mode
                      : Icons.dark_mode,
                ),
                onPressed: onToggleTheme,
              ),
              IconButton(
                tooltip: '保活设置',
                constraints: const BoxConstraints(
                  minWidth: PadBreakpoints.minTap,
                  minHeight: PadBreakpoints.minTap,
                ),
                icon: const Icon(Icons.shield_outlined),
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => const KeepAliveSettingsPage(),
                    ),
                  );
                },
              ),
              IconButton(
                tooltip: '设置',
                constraints: const BoxConstraints(
                  minWidth: PadBreakpoints.minTap,
                  minHeight: PadBreakpoints.minTap,
                ),
                icon: const Icon(Icons.settings_outlined),
                onPressed: onSettings,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavChip extends StatelessWidget {
  const _NavChip({
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: enabled ? (_) => onTap() : null,
      visualDensity: VisualDensity.compact,
    );
  }
}

class _HostCard extends StatelessWidget {
  const _HostCard({
    required this.host,
    required this.sessionPhase,
    required this.selected,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
    required this.onCloseSession,
  });

  final HostProfile host;
  final SessionPhase? sessionPhase;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;
  final VoidCallback onCloseSession;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final live = sessionPhase == SessionPhase.connected ||
        sessionPhase == SessionPhase.connecting;
    final title = host.name.isEmpty ? host.host : host.name;
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.18)
          : scheme.surfaceContainerHighest.withValues(alpha: 0.55),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: onTap,
        onLongPress: onEdit,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 16,
                child: Text(
                  host.protocol.label.substring(0, 1),
                  style: const TextStyle(fontSize: 11),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, overflow: TextOverflow.ellipsis),
                    Text(
                      '${host.protocol.label}'
                      '${host.protocol.isDeferred ? ' · 稍后' : ''}'
                      ' · ${host.host}:${host.port}',
                      style: Theme.of(context).textTheme.bodySmall,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (sessionPhase != null)
                      Text(
                        _phaseLabel(sessionPhase!),
                        style: TextStyle(
                          fontSize: 11,
                          color: live ? Colors.green : scheme.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
              if (live)
                IconButton(
                  tooltip: '断开',
                  icon: const Icon(Icons.close, size: 18),
                  constraints: const BoxConstraints(
                    minWidth: PadBreakpoints.minTap,
                    minHeight: PadBreakpoints.minTap,
                  ),
                  onPressed: onCloseSession,
                ),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'edit') onEdit();
                  if (v == 'delete') onDelete();
                  if (v == 'connect') onTap();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'connect', child: Text('连接')),
                  PopupMenuItem(value: 'edit', child: Text('编辑')),
                  PopupMenuItem(value: 'delete', child: Text('删除')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  static String _phaseLabel(SessionPhase p) => switch (p) {
        SessionPhase.connecting => '连接中',
        SessionPhase.connected => '已连接',
        SessionPhase.disconnected => '已断开',
        SessionPhase.error => '错误',
      };
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.title,
    required this.phase,
    required this.selected,
    required this.onSelect,
    required this.onClose,
  });

  final String title;
  final SessionPhase phase;
  final bool selected;
  final VoidCallback onSelect;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: selected
          ? scheme.primary.withValues(alpha: 0.18)
          : scheme.surfaceContainerHighest.withValues(alpha: 0.4),
      borderRadius: BorderRadius.circular(10),
      child: ListTile(
        dense: true,
        title: Text(title, overflow: TextOverflow.ellipsis),
        subtitle: Text(_HostCard._phaseLabel(phase)),
        selected: selected,
        onTap: onSelect,
        trailing: IconButton(
          icon: const Icon(Icons.close, size: 18),
          onPressed: onClose,
        ),
      ),
    );
  }
}
