import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/plc_data.dart';
import '../theme/hmi_colors.dart';

/// Shows current batch state as a badge with a progress bar.
class BatchStateWidget extends StatelessWidget {
  final BatchState state;
  final double progress;

  const BatchStateWidget({
    super.key,
    required this.state,
    required this.progress,
  });

  Color _stateColor() {
    switch (state) {
      case BatchState.idle:
        return HmiColors.textMuted;
      case BatchState.heating:
        return HmiColors.danger;
      case BatchState.holding:
        return HmiColors.accent;
      case BatchState.cooling:
        return HmiColors.info;
      case BatchState.complete:
        return HmiColors.healthy;
    }
  }

  @override
  Widget build(BuildContext context) {
    final color = _stateColor();
    // progress comes as 0-100 from the server; normalise to 0.0-1.0.
    final p = (progress / 100).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: HmiColors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: HmiColors.surfaceBorder, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'BATCH REACTOR',
            style: GoogleFonts.outfit(
              fontSize: 26,
              fontWeight: FontWeight.w600,
              color: HmiColors.textSecondary,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  state.name.toUpperCase(),
                  style: GoogleFonts.dmMono(
                    fontSize: 30,
                    fontWeight: FontWeight.w600,
                    color: color,
                    letterSpacing: 2,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '${(p * 100).toStringAsFixed(0)}%',
                style: GoogleFonts.dmMono(
                  fontSize: 42,
                  fontWeight: FontWeight.w500,
                  color: color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          ClipRRect(
            borderRadius: BorderRadius.circular(5),
            child: LinearProgressIndicator(
              value: p,
              minHeight: 10,
              backgroundColor: HmiColors.surfaceBorder,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}
