import 'package:flutter/material.dart';

import '../core/session/session_log.dart';

/// Simple scrollable session event log.
class SessionLogPanel extends StatelessWidget {
  const SessionLogPanel({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: sessionLog,
      builder: (context, _) {
        final entries = sessionLog.entries.reversed.toList();
        return Column(
          children: [
            ListTile(
              title: const Text('会话日志'),
              trailing: IconButton(
                tooltip: '清空',
                onPressed: sessionLog.clear,
                icon: const Icon(Icons.delete_outline),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: entries.isEmpty
                  ? const Center(child: Text('暂无日志'))
                  : ListView.builder(
                      itemCount: entries.length,
                      itemBuilder: (context, i) {
                        final e = entries[i];
                        final color = switch (e.level) {
                          SessionLogLevel.error =>
                            Theme.of(context).colorScheme.error,
                          SessionLogLevel.warn => Colors.orange.shade800,
                          SessionLogLevel.info => null,
                        };
                        final t =
                            '${e.at.hour.toString().padLeft(2, '0')}:'
                            '${e.at.minute.toString().padLeft(2, '0')}:'
                            '${e.at.second.toString().padLeft(2, '0')}';
                        return ListTile(
                          dense: true,
                          title: Text(
                            e.message,
                            style: TextStyle(fontSize: 13, color: color),
                          ),
                          subtitle: Text(t, style: const TextStyle(fontSize: 11)),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}

void showSessionLogSheet(BuildContext context) {
  showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SizedBox(
      height: MediaQuery.of(ctx).size.height * 0.5,
      child: const SessionLogPanel(),
    ),
  );
}
