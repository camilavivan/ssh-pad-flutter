import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/keepalive/keepalive_controller.dart';

class TerminalPlaceholderPage extends StatelessWidget {
  const TerminalPlaceholderPage({super.key, this.hostName});

  final String? hostName;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(hostName ?? '终端')),
      body: const Center(
        child: Text(
          '终端连接将在 M1 实现\n(SSH + xterm)\n保活 FGS 紧随其后（M1b）',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

class FilesPlaceholderPage extends StatelessWidget {
  const FilesPlaceholderPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('文件')),
      body: const Center(
        child: Text(
          'SFTP / FTP 文件浏览将在 M2 实现',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// Settings placeholders: battery optimization + OEM autostart (保活重中之重).
class KeepAliveSettingsPage extends ConsumerWidget {
  const KeepAliveSettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keepalive = ref.watch(keepAliveControllerProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('保活设置')),
      body: ListView(
        children: [
          const ListTile(
            title: Text('会话保活（重中之重）'),
            subtitle: Text(
              '有会话时启动前台服务（dataSync）。'
              '默认不无限自动重连。完整实现见 M1b。',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.battery_saver_outlined),
            title: const Text('忽略电池优化'),
            subtitle: const Text('调起系统电池白名单（M0 通道已通，逻辑 M1b 完善）'),
            onTap: () async {
              await keepalive.requestIgnoreBatteryOptimizations();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已请求打开电池优化设置（若平台支持）')),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.settings_suggest_outlined),
            title: const Text('厂商自启动 / 后台权限'),
            subtitle: const Text('OEM 自启动页占位（对照 KeepAliveOem）'),
            onTap: () async {
              await keepalive.openOemAutostartSettings();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已尝试打开 OEM / 应用详情设置')),
                );
              }
            },
          ),
          const ListTile(
            leading: Icon(Icons.volume_mute_outlined),
            title: Text('可选：弱音 mediaPlayback'),
            subtitle: Text('国行增强，默认关；评估 Play 政策后启用'),
          ),
        ],
      ),
    );
  }
}
