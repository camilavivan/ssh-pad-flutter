import 'package:flutter/material.dart';

import '../../core/status/host_resource_stats.dart';
import 'session_status.dart';

/// Compact CPU / MEM bars + net / disk / load line for host cards.
class HostResourceStrip extends StatelessWidget {
  const HostResourceStrip({super.key, required this.stats});

  final HostResourceStats stats;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurfaceVariant;
    final accent = SessionStatusStyle.connected;

    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _StatBar(
            label: 'CPU',
            value: stats.cpuText(),
            progress: stats.cpuRatio,
            accent: accent,
            muted: muted,
          ),
          _StatBar(
            label: 'MEM',
            value: stats.memText(),
            progress: stats.memRatio,
            accent: accent,
            muted: muted,
          ),
          if (stats.diskTotalKb > 0)
            _StatBar(
              label: 'DISK',
              value: stats.diskText(),
              progress: stats.diskRatio,
              accent: accent,
              muted: muted,
            ),
          const SizedBox(height: 2),
          Text(
            'NET ${stats.netText()}'
            '${stats.load == '—' || stats.load.isEmpty ? '' : '  ·  load ${stats.load}'}',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 10,
              height: 1.15,
              color: muted,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

class _StatBar extends StatelessWidget {
  const _StatBar({
    required this.label,
    required this.value,
    required this.progress,
    required this.accent,
    required this.muted,
  });

  final String label;
  final String value;
  final double progress;
  final Color accent;
  final Color muted;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Row(
        children: [
          SizedBox(
            width: 34,
            child: Text(
              label,
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w600,
                color: muted,
                height: 1.1,
              ),
            ),
          ),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: SizedBox(
                height: 5,
                child: LinearProgressIndicator(
                  value: progress.clamp(0.0, 1.0),
                  backgroundColor: muted.withValues(alpha: 0.22),
                  color: accent,
                  minHeight: 5,
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 72,
            child: Text(
              value,
              textAlign: TextAlign.right,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 10,
                height: 1.1,
                color: muted,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
