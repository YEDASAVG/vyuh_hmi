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
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HmiColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HmiColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Batch Reactor',
            style: GoogleFonts.outfit(
              fontSize: 13,
              fontWeight: FontWeight.w500,
              color: HmiColors.textSecondary,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  state.name.toUpperCase(),
                  style: GoogleFonts.dmMono(
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    color: color,
                  ),
                ),
              ),
              const Spacer(),
              Text(
                '${(p * 100).toStringAsFixed(0)}%',
                style: GoogleFonts.dmMono(
                  fontSize: 14,
                  color: HmiColors.textSecondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: p,
              minHeight: 6,
              backgroundColor: HmiColors.surfaceBorder,
              valueColor: AlwaysStoppedAnimation<Color>(color),
            ),
          ),
        ],
      ),
    );
  }
}
