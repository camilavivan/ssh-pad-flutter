import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/keepalive/keepalive_controller.dart';
import 'session_log_panel.dart';

/// Keepalive settings: battery, OEM autostart, notification, weak audio.
class KeepAliveSettingsPage extends ConsumerWidget {
  const KeepAliveSettingsPage({super.key, this.embedded = false});

  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keepalive = ref.watch(keepAliveControllerProvider);
    final body = ListView(
      children: [
        const ListTile(
          title: Text('会话保活（重中之重）'),
          subtitle: Text(
            '有终端/文件会话时立即启动同进程前台服务（mediaPlayback|dataSync），'
            '持有 PARTIAL_WAKE_LOCK + WifiLock，并默认开启弱音 AudioTrack。'
            '切应用不断开；仅用户断开或杀进程结束。'
            '默认不无限自动重连。',
          ),
        ),
        ListTile(
          leading: const Icon(Icons.notifications_outlined),
          title: const Text('通知权限（Android 13+）'),
          subtitle: const Text('前台服务通知需要通知权限；首次连接会自动请求'),
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
          subtitle: const Text('调起系统电池白名单；首次连接会自动请求'),
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
        ListTile(
          leading: const Icon(Icons.picture_in_picture_alt_outlined),
          title: const Text('悬浮窗权限（可选）'),
          subtitle: const Text('部分国行 ROM 有悬浮窗时更不易冷冻进程'),
          onTap: () async {
            await keepalive.openOverlayPermissionSettings();
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('已打开悬浮窗权限设置')),
              );
            }
          },
        ),
        ListTile(
          leading: const Icon(Icons.receipt_long_outlined),
          title: const Text('会话日志'),
          subtitle: const Text('最近连接 / 主机密钥 / 文件操作'),
          onTap: () => showSessionLogSheet(context),
        ),
        SwitchListTile(
          secondary: const Icon(Icons.volume_mute_outlined),
          title: const Text('弱音 mediaPlayback'),
          subtitle: const Text(
            '国行 ROM 保活关键路径；默认开启。'
            '极弱 AudioTrack（无 MediaSession，听不见）。'
            '上架 Play 前请评估政策。关闭后仅靠 dataSync，多数国行会冻死会话。',
          ),
          value: keepalive.weakAudioEnabled,
          onChanged: (v) async {
            await keepalive.setWeakAudioEnabled(v);
            if (context.mounted) {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(content: Text(v ? '已开启弱音保活' : '已关闭弱音保活（不推荐）')),
              );
            }
          },
        ),
      ],
    );
    if (embedded) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: const SizedBox(
              height: 48,
              child: Padding(
                padding: EdgeInsets.symmetric(horizontal: 12),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '保活设置',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ),
          ),
          Expanded(child: body),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(title: const Text('保活设置')),
      body: body,
    );
  }
}
