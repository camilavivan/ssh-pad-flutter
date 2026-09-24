import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/keepalive/keepalive_controller.dart';

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

/// Keepalive settings: battery, OEM autostart, notification, optional weak audio.
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
              '有 SSH 会话时启动同进程前台服务（dataSync），'
              '持有 PARTIAL_WAKE_LOCK + WifiLock。'
              '切应用不断开；仅用户断开或杀进程结束。'
              '默认不无限自动重连。',
            ),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('通知权限（Android 13+）'),
            subtitle: const Text('前台服务通知需要通知权限'),
            onTap: () async {
              final ok = await keepalive.requestNotificationPermission();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(ok ? '通知权限已授予或已有' : '未授予通知权限'),
                  ),
                );
              }
            },
          ),
          ListTile(
            leading: const Icon(Icons.battery_saver_outlined),
            title: const Text('忽略电池优化'),
            subtitle: const Text('调起系统电池白名单'),
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
            subtitle: const Text('OEM 自启动页（小米/华为/OPPO/vivo 等）'),
            onTap: () async {
              await keepalive.openOemAutostartSettings();
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('已尝试打开 OEM / 应用详情设置')),
                );
              }
            },
          ),
          SwitchListTile(
            secondary: const Icon(Icons.volume_mute_outlined),
            title: const Text('弱音 mediaPlayback（可选）'),
            subtitle: const Text(
              '国行 ROM 增强保活；默认关。'
              '开启后用极弱 AudioTrack（无 MediaSession）。'
              '上架 Play 前请评估政策。',
            ),
            value: keepalive.weakAudioEnabled,
            onChanged: (v) async {
              await keepalive.setWeakAudioEnabled(v);
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(v ? '已开启弱音保活' : '已关闭弱音保活')),
                );
              }
            },
          ),
        ],
      ),
    );
  }
}
