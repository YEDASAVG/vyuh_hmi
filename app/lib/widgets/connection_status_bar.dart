import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/hmi_colors.dart';
import 'alarm_banner_widget.dart';

/// Top connection status bar showing server + WebSocket connection state
/// plus inline alarm count badges.
class ConnectionStatusBar extends StatelessWidget {
  final bool isServerConnected;
  final bool isWsConnected;
  final List<Alarm> alarms;

  const ConnectionStatusBar({
    super.key,
    required this.isServerConnected,
    required this.isWsConnected,
    this.alarms = const [],
  });

  @override
  Widget build(BuildContext context) {
    final allGood = isServerConnected && isWsConnected;
    final critCount =
        alarms.where((a) => a.severity == AlarmSeverity.critical).length;
    final warnCount =
        alarms.where((a) => a.severity == AlarmSeverity.warning).length;

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 500;
        return Container(
          width: double.infinity,
          padding: EdgeInsets.symmetric(horizontal: isNarrow ? 10 : 16, vertical: 6),
          color: allGood ? HmiColors.healthyDim : HmiColors.dangerDim,
          child: Row(
            children: [
              Icon(
                allGood ? Icons.check_circle_rounded : Icons.warning_rounded,
                size: 14,
                color: allGood ? HmiColors.healthy : HmiColors.danger,
              ),
              const SizedBox(width: 6),
              Text(
                allGood ? 'Connected' : 'Disconnected',
                style: GoogleFonts.outfit(
                  fontSize: isNarrow ? 11 : 12,
                  fontWeight: FontWeight.w500,
                  color: allGood ? HmiColors.healthy : HmiColors.danger,
                ),
              ),
              if (critCount > 0 || warnCount > 0) ...[
                const SizedBox(width: 8),
                Container(width: 1, height: 12, color: Colors.white12),
                const SizedBox(width: 8),
              ],
              if (critCount > 0)
                _alarmBadge(critCount, 'CRIT', HmiColors.danger),
              if (critCount > 0 && warnCount > 0)
                const SizedBox(width: 6),
              if (warnCount > 0)
                _alarmBadge(warnCount, 'WARN', HmiColors.warning),
              const Spacer(),
              // On narrow screens: just dots, no labels
              _dot(isNarrow ? '' : 'Server', isServerConnected),
              SizedBox(width: isNarrow ? 8 : 12),
              _dot(isNarrow ? '' : 'WebSocket', isWsConnected),
            ],
          ),
        );
      },
    );
  }

  Widget _alarmBadge(int count, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(3),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: GoogleFonts.jetBrainsMono(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: 3),
          Text(
            label,
            style: GoogleFonts.jetBrainsMono(
              fontSize: 9,
              fontWeight: FontWeight.w600,
              color: color.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dot(String label, bool connected) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: connected ? HmiColors.healthy : HmiColors.danger,
          ),
        ),
        if (label.isNotEmpty) ...[
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 11,
              color: HmiColors.textMuted,
            ),
          ),
        ],
      ],
    );
  }
}
