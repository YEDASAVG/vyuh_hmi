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
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: HmiColors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: HmiColors.surfaceBorder, width: 1.5),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: color,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label.toUpperCase(),
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: Colors.white70,
                      letterSpacing: 1.2,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                SparklineWidget(
                  values: sparklineData,
                  color: color,
                  width: 70,
                  height: 26,
                ),
              ],
            ),
            const SizedBox(height: 2),
            Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value.toStringAsFixed(value < 10 ? 1 : 0),
                  style: GoogleFonts.dmMono(
                    fontSize: 38,
                    fontWeight: FontWeight.w500,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(width: 6),
                Text(
                  unit,
                  style: GoogleFonts.outfit(
                    fontSize: 20,
                    color: Colors.white60,
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
