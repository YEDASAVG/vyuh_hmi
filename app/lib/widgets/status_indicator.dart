import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/hmi_colors.dart';

/// Green/yellow/red dot indicator based on value thresholds.
class StatusIndicator extends StatelessWidget {
  final double value;
  final double warningThreshold;
  final double dangerThreshold;
  final double size;
  final String? label;

  const StatusIndicator({
    super.key,
    required this.value,
    this.warningThreshold = 70,
    this.dangerThreshold = 90,
    this.size = 10,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final color = _color;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: color,
            boxShadow: [
              BoxShadow(
                color: color.withValues(alpha: 0.5),
                blurRadius: 6,
                spreadRadius: 1,
              ),
            ],
          ),
        ),
        if (label != null) ...[
          const SizedBox(width: 6),
          Text(
            label!,
            style: GoogleFonts.outfit(
              fontSize: 12,
              color: HmiColors.textSecondary,
            ),
          ),
        ],
      ],
    );
  }

  Color get _color {
    if (value >= dangerThreshold) return HmiColors.danger;
    if (value >= warningThreshold) return HmiColors.warning;
    return HmiColors.healthy;
  }
}
