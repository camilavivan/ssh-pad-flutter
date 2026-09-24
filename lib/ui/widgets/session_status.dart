import 'package:flutter/material.dart';

import '../../core/session/session_backend.dart';

/// Status accents inspired by ServerBox compact server rows (original styling).
abstract final class SessionStatusStyle {
  static const connected = Color(0xFF3FB950);
  static const connecting = Color(0xFFD29922);
  static const error = Color(0xFFF85149);
  static const idle = Color(0xFF8B949E);

  static Color color(SessionPhase? phase) => switch (phase) {
        SessionPhase.connecting => connecting,
        SessionPhase.connected => connected,
        SessionPhase.error => error,
        SessionPhase.disconnected || null => idle,
      };

  static String label(SessionPhase? phase) => switch (phase) {
        SessionPhase.connecting => '连接中',
        SessionPhase.connected => '已连接',
        SessionPhase.disconnected => '已断开',
        SessionPhase.error => '错误',
        null => '未连接',
      };

  static bool isLive(SessionPhase? phase) =>
      phase == SessionPhase.connected || phase == SessionPhase.connecting;
}

/// Small filled status dot used on host/session cards and tabs.
class StatusDot extends StatelessWidget {
  const StatusDot({super.key, required this.phase, this.size = 8});

  final SessionPhase? phase;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: SessionStatusStyle.color(phase),
        shape: BoxShape.circle,
        boxShadow: SessionStatusStyle.isLive(phase)
            ? [
                BoxShadow(
                  color: SessionStatusStyle.color(phase).withValues(alpha: 0.45),
                  blurRadius: 4,
                ),
              ]
            : null,
      ),
    );
  }
}

/// Left accent bar on denser cards.
class StatusAccentBar extends StatelessWidget {
  const StatusAccentBar({super.key, required this.phase, this.width = 3});

  final SessionPhase? phase;
  final double width;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      decoration: BoxDecoration(
        color: SessionStatusStyle.color(phase),
        borderRadius: const BorderRadius.horizontal(left: Radius.circular(8)),
      ),
    );
  }
}

/// Compact protocol badge (SSH / SFTP / …).
class ProtocolBadge extends StatelessWidget {
  const ProtocolBadge({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: scheme.primary.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: scheme.primary.withValues(alpha: 0.35)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.3,
          color: scheme.primary,
          height: 1.1,
        ),
      ),
    );
  }
}

/// Section heading used in left pane / settings (ServerBox group style).
class SectionHeading extends StatelessWidget {
  const SectionHeading(this.title, {super.key, this.trailing});

  final String title;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.labelLarge?.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.4,
        );
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 4, 4, 6),
      child: Row(
        children: [
          Expanded(child: Text(title, style: style)),
          ?trailing,
        ],
      ),
    );
  }
}
