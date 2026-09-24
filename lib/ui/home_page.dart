import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../data/host_profile.dart';
import '../data/host_store.dart';
import 'host_editor.dart';
import 'placeholders.dart';

class HomePage extends ConsumerWidget {
  const HomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hosts = ref.watch(hostListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('SSH Pad'),
        actions: [
          IconButton(
            tooltip: '保活设置',
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
            tooltip: '文件（M2）',
            icon: const Icon(Icons.folder_outlined),
            onPressed: () {
              Navigator.of(context).push(
                MaterialPageRoute(
                  builder: (_) => const FilesPlaceholderPage(),
                ),
              );
            },
          ),
        ],
      ),
      body: hosts.isEmpty
          ? const Center(
              child: Text('暂无主机\n点击右下角添加', textAlign: TextAlign.center),
            )
          : ListView.separated(
              itemCount: hosts.length,
              separatorBuilder: (_, _) => const Divider(height: 1),
              itemBuilder: (context, index) {
                final h = hosts[index];
                return ListTile(
                  leading: CircleAvatar(
                    child: Text(
                      h.protocol.label.substring(0, 1),
                      style: const TextStyle(fontSize: 12),
                    ),
                  ),
                  title: Text(h.name.isEmpty ? h.host : h.name),
                  subtitle: Text(
                    '${h.protocol.label}'
                    '${h.protocol.isDeferred ? ' · 稍后' : ''}'
                    ' · ${h.host}:${h.port}',
                  ),
                  trailing: PopupMenuButton<String>(
                    onSelected: (v) async {
                      if (v == 'edit') {
                        await Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (_) => HostEditorPage(existing: h),
                          ),
                        );
                      } else if (v == 'delete') {
                        await ref.read(hostListProvider.notifier).delete(h.id);
                      } else if (v == 'connect') {
                        _connect(context, h);
                      }
                    },
                    itemBuilder: (_) => [
                      const PopupMenuItem(value: 'connect', child: Text('连接')),
                      const PopupMenuItem(value: 'edit', child: Text('编辑')),
                      const PopupMenuItem(value: 'delete', child: Text('删除')),
                    ],
                  ),
                  onTap: () => _connect(context, h),
                );
              },
            ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          Navigator.of(context).push(
            MaterialPageRoute(builder: (_) => const HostEditorPage()),
          );
        },
        child: const Icon(Icons.add),
      ),
    );
  }

  void _connect(BuildContext context, HostProfile h) {
    if (h.protocol.isDeferred) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('${h.protocol.label} 将在后续版本实现（稍后）')),
      );
      return;
    }
    if (h.protocol == HostProtocol.sftp || h.protocol == HostProtocol.ftp) {
      Navigator.of(context).push(
        MaterialPageRoute(builder: (_) => const FilesPlaceholderPage()),
      );
    } else {
      Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => TerminalPlaceholderPage(hostName: h.name),
        ),
      );
    }
  }
}
