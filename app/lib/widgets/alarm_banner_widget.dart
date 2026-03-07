import 'package:flutter/material.dart';

import '../theme/hmi_colors.dart';

/// Severity levels for HMI alarms.
enum AlarmSeverity {
  warning(HmiColors.warning, HmiColors.warningDim, Icons.warning_amber_rounded),
  critical(HmiColors.danger, HmiColors.dangerDim, Icons.error_rounded),
  info(HmiColors.info, Color(0x335B9CF5), Icons.info_rounded);

  const AlarmSeverity(this.color, this.bgColor, this.icon);
  final Color color;
  final Color bgColor;
  final IconData icon;
}

/// A single alarm event.
class Alarm {
  final String id;
  final String message;
  final AlarmSeverity severity;
  final DateTime timestamp;
  final int? register;

  Alarm({
    required this.id,
    required this.message,
    required this.severity,
    DateTime? timestamp,
    this.register,
  }) : timestamp = timestamp ?? DateTime.now();
}

/// Animated alarm banner that flashes for critical alarms.
///
/// Shows at the top of the screen when values exceed safety thresholds.
/// Supports multiple alarms stacked, with dismiss action.
class AlarmBanner extends StatelessWidget {
  final List<Alarm> alarms;
  final ValueChanged<String>? onDismiss;

  const AlarmBanner({
    super.key,
    required this.alarms,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    if (alarms.isEmpty) return const SizedBox.shrink();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: alarms.map((alarm) => _AlarmTile(alarm: alarm, onDismiss: onDismiss)).toList(),
    );
  }
}

class _AlarmTile extends StatefulWidget {
  final Alarm alarm;
  final ValueChanged<String>? onDismiss;

  const _AlarmTile({required this.alarm, this.onDismiss});

  @override
  State<_AlarmTile> createState() => _AlarmTileState();
}

class _AlarmTileState extends State<_AlarmTile> with SingleTickerProviderStateMixin {
  late final AnimationController _flashController;
  late final Animation<double> _flashOpacity;

  @override
  void initState() {
    super.initState();
    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _flashOpacity = Tween<double>(begin: 0.15, end: 0.55).animate(
      CurvedAnimation(parent: _flashController, curve: Curves.easeInOut),
    );

    // Only flash for critical alarms.
    if (widget.alarm.severity == AlarmSeverity.critical) {
      _flashController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _flashController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final alarm = widget.alarm;
    final severity = alarm.severity;

    final isCritical = severity == AlarmSeverity.critical;

    final content = Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: isCritical ? 14 : 10),
      child: Row(
        children: [
          Icon(severity.icon, color: severity.color, size: isCritical ? 28 : 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  isCritical ? '⚠ CRITICAL ALARM' : severity == AlarmSeverity.warning ? '⚠ WARNING' : 'INFO',
                  style: TextStyle(
                    color: severity.color,
                    fontSize: isCritical ? 14 : 11,
                    fontWeight: FontWeight.w900,
                    letterSpacing: 1.2,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  alarm.message,
                  style: TextStyle(
                    color: severity.color.withValues(alpha: 0.9),
                    fontSize: isCritical ? 13 : 12,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (widget.onDismiss != null)
            GestureDetector(
              onTap: () => widget.onDismiss!(alarm.id),
              child: Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: severity.color.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Icon(Icons.close, color: severity.color, size: 16),
              ),
            ),
        ],
      ),
    );

    // Critical alarms flash with hard pulse; others have a static background.
    if (isCritical) {
      return AnimatedBuilder(
        animation: _flashOpacity,
        builder: (context, child) {
          return Container(
            margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: severity.color.withValues(alpha: _flashOpacity.value),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: severity.color.withValues(alpha: 0.6), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: severity.color.withValues(alpha: _flashOpacity.value * 0.5),
                  blurRadius: 12,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: child,
          );
        },
        child: content,
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: severity.bgColor,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: severity.color.withValues(alpha: 0.3)),
      ),
      child: content,
    );
  }
}
