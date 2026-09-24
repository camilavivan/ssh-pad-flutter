import 'package:flutter/material.dart';

import '../../core/security/host_key_verifier.dart';

/// Shows TOFU / mismatch dialog; returns user decision.
Future<HostKeyDecision> showHostKeyDialog(
  BuildContext context,
  HostKeyPromptRequest request,
) async {
  final result = await showDialog<HostKeyDecision>(
    context: context,
    barrierDismissible: false,
    builder: (ctx) {
      final isMismatch = request.kind == HostKeyPromptKind.mismatch;
      return AlertDialog(
        title: Text(isMismatch ? '主机密钥已更改' : '信任此主机？'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isMismatch)
                Text(
                  '警告：${request.host}:${request.port} 的主机密钥与本地信任的不一致。'
                  '可能是管理员换过密钥，也可能是中间人攻击。',
                  style: TextStyle(color: Theme.of(ctx).colorScheme.error),
                )
              else
                Text(
                  '首次连接 ${request.host}:${request.port}。'
                  '请核对指纹后决定是否信任（TOFU）。',
                ),
              const SizedBox(height: 12),
              Text('密钥类型: ${request.keyType}'),
              const SizedBox(height: 8),
              const Text('指纹:'),
              SelectableText(
                request.fingerprint,
                style: const TextStyle(fontFamily: 'monospace', fontSize: 13),
              ),
              if (isMismatch && request.previous != null) ...[
                const SizedBox(height: 12),
                const Text('先前信任的指纹:'),
                SelectableText(
                  request.previous!.fingerprint,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, HostKeyDecision.reject),
            child: const Text('拒绝'),
          ),
          if (isMismatch)
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: Theme.of(ctx).colorScheme.error,
              ),
              onPressed: () => Navigator.pop(ctx, HostKeyDecision.replace),
              child: const Text('替换并信任'),
            )
          else
            FilledButton(
              onPressed: () => Navigator.pop(ctx, HostKeyDecision.accept),
              child: const Text('信任并继续'),
            ),
        ],
      );
    },
  );
  return result ?? HostKeyDecision.reject;
}
