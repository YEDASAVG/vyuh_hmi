import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/hmi_colors.dart';
import 'alarm_banner_widget.dart';

/// Persistent alarm panel for HMI dashboard — always visible in the right column.
///
/// Follows ISA-101 High-Performance HMI guidelines:
/// - Always visible (never auto-dismissed)
/// - Color-coded by severity (red = critical, amber = warning)
/// - Shows timestamp, message, and severity
/// - Scrollable when many alarms present
/// - Shows "ALL CLEAR" when no active alarms
class PersistentAlarmPanel extends StatelessWidget {
  final List<Alarm> alarms;
  final ValueChanged<String>? onDismiss;

  const PersistentAlarmPanel({
    super.key,
    required this.alarms,
    this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    final criticals =
        alarms.where((a) => a.severity == AlarmSeverity.critical).toList();
    final warnings =
        alarms.where((a) => a.severity == AlarmSeverity.warning).toList();
    final infos =
        alarms.where((a) => a.severity == AlarmSeverity.info).toList();
    final sorted = [...criticals, ...warnings, ...infos];

    return Container(
      decoration: BoxDecoration(
        color: HmiColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: alarms.any((a) => a.severity == AlarmSeverity.critical)
              ? HmiColors.danger.withValues(alpha: 0.5)
              : HmiColors.surfaceBorder,
          width: alarms.any((a) => a.severity == AlarmSeverity.critical)
              ? 2
              : 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            decoration: BoxDecoration(
              color: alarms.any((a) => a.severity == AlarmSeverity.critical)
                  ? HmiColors.danger.withValues(alpha: 0.1)
                  : HmiColors.surfaceBorder.withValues(alpha: 0.3),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                Icon(
                  alarms.isEmpty
                      ? Icons.notifications_none_rounded
                      : Icons.notification_important_rounded,
                  color: alarms.isEmpty ? HmiColors.textMuted : HmiColors.danger,
                  size: 28,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'ACTIVE ALARMS',
                    style: GoogleFonts.dmMono(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: alarms.isEmpty
                          ? HmiColors.textMuted
                          : HmiColors.textPrimary,
                      letterSpacing: 2,
                    ),
                  ),
                ),
                if (alarms.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: HmiColors.danger.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: HmiColors.danger.withValues(alpha: 0.4),
                      ),
                    ),
                    child: Text(
                      '${alarms.length}',
                      style: GoogleFonts.dmMono(
                        fontSize: 24,
                        fontWeight: FontWeight.w700,
                        color: HmiColors.danger,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          // ── Alarm List ──
          Expanded(
            child: alarms.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.check_circle_outline_rounded,
                          size: 48,
                          color: HmiColors.healthy.withValues(alpha: 0.5),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'ALL CLEAR',
                          style: GoogleFonts.dmMono(
                            fontSize: 28,
                            fontWeight: FontWeight.w700,
                            color: HmiColors.healthy.withValues(alpha: 0.7),
                            letterSpacing: 3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'No active alarms',
                          style: GoogleFonts.outfit(
                            fontSize: 20,
                            color: HmiColors.textMuted,
                          ),
                        ),
                      ],
                    ),
                  )
                : ListView.separated(
                    padding: const EdgeInsets.all(12),
                    itemCount: sorted.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (context, index) {
                      final alarm = sorted[index];
                      return _PersistentAlarmTile(
                        alarm: alarm,
                        onDismiss: onDismiss,
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

class _PersistentAlarmTile extends StatefulWidget {
  final Alarm alarm;
  final ValueChanged<String>? onDismiss;

  const _PersistentAlarmTile({required this.alarm, this.onDismiss});

  @override
  State<_PersistentAlarmTile> createState() => _PersistentAlarmTileState();
}

class _PersistentAlarmTileState extends State<_PersistentAlarmTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _flashController;
  late final Animation<double> _flashOpacity;

  @override
  void initState() {
    super.initState();
    _flashController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _flashOpacity = Tween<double>(begin: 0.15, end: 0.45).animate(
      CurvedAnimation(parent: _flashController, curve: Curves.easeInOut),
    );
    if (widget.alarm.severity == AlarmSeverity.critical) {
      _flashController.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _flashController.dispose();
    super.dispose();
  }

  String _timeAgo(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    return '${diff.inHours}h ago';
  }

  @override
  Widget build(BuildContext context) {
    final alarm = widget.alarm;
    final severity = alarm.severity;
    final isCritical = severity == AlarmSeverity.critical;

    final tile = Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isCritical
            ? null
            : severity.bgColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: severity.color.withValues(alpha: isCritical ? 0.6 : 0.3),
          width: isCritical ? 2 : 1.5,
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(severity.icon, color: severity.color, size: isCritical ? 38 : 32),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        isCritical
                            ? 'CRITICAL'
                            : severity == AlarmSeverity.warning
                                ? 'WARNING'
                                : 'INFO',
                        style: GoogleFonts.dmMono(
                          fontSize: isCritical ? 20 : 18,
                          fontWeight: FontWeight.w700,
                          color: severity.color,
                          letterSpacing: 1.5,
                        ),
                      ),
                    ),
                    Text(
                      _timeAgo(alarm.timestamp),
                      style: GoogleFonts.dmMono(
                        fontSize: 17,
                        color: HmiColors.textMuted,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                Text(
                  alarm.message,
                  style: GoogleFonts.outfit(
                    fontSize: 19,
                    fontWeight: FontWeight.w500,
                    color: severity.color.withValues(alpha: 0.9),
                    height: 1.3,
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (widget.onDismiss != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => widget.onDismiss!(alarm.id),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: severity.color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.close, color: severity.color, size: 24),
              ),
            ),
          ],
        ],
      ),
    );

    if (isCritical) {
      return AnimatedBuilder(
        animation: _flashOpacity,
        builder: (context, child) {
          return Container(
            decoration: BoxDecoration(
              color: severity.color.withValues(alpha: _flashOpacity.value),
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(
                  color:
                      severity.color.withValues(alpha: _flashOpacity.value * 0.4),
                  blurRadius: 16,
                  spreadRadius: 2,
                ),
              ],
            ),
            child: child,
          );
        },
        child: tile,
      );
    }

    return tile;
  }
}