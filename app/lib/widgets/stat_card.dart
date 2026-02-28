import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/hmi_colors.dart';
import 'line_chart_widget.dart';

/// Compact stat card for dashboard grid — shows label, value, unit, and sparkline.
class StatCard extends StatelessWidget {
  final String label;
  final double value;
  final String unit;
  final List<double> sparklineData;
  final Color? accentColor;
  final VoidCallback? onTap;

  const StatCard({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    required this.sparklineData,
    this.accentColor,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final color = accentColor ?? HmiColors.accent;

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        decoration: BoxDecoration(
          color: HmiColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: HmiColors.surfaceBorder),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: HmiColors.textSecondary,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SparklineWidget(
                  values: sparklineData,
                  color: color,
                  width: 48,
                  height: 18,
                ),
              ],
            ),
            const SizedBox(height: 4),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value.toStringAsFixed(value < 10 ? 1 : 0),
                  style: GoogleFonts.dmMono(
                    fontSize: 20,
                    fontWeight: FontWeight.w500,
                    color: HmiColors.textPrimary,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  unit,
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: HmiColors.textMuted,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
