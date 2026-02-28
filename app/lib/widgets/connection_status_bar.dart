import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/hmi_colors.dart';

/// Top connection status bar showing server + WebSocket connection state.
class ConnectionStatusBar extends StatelessWidget {
  final bool isServerConnected;
  final bool isWsConnected;

  const ConnectionStatusBar({
    super.key,
    required this.isServerConnected,
    required this.isWsConnected,
  });

  @override
  Widget build(BuildContext context) {
    final allGood = isServerConnected && isWsConnected;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      color: allGood ? HmiColors.healthyDim : HmiColors.dangerDim,
      child: Row(
        children: [
          Icon(
            allGood ? Icons.check_circle_rounded : Icons.warning_rounded,
            size: 14,
            color: allGood ? HmiColors.healthy : HmiColors.danger,
          ),
          const SizedBox(width: 8),
          Text(
            allGood ? 'Connected' : 'Disconnected',
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: allGood ? HmiColors.healthy : HmiColors.danger,
            ),
          ),
          const Spacer(),
          _dot('Server', isServerConnected),
          const SizedBox(width: 12),
          _dot('WebSocket', isWsConnected),
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
        const SizedBox(width: 4),
        Text(
          label,
          style: GoogleFonts.outfit(
            fontSize: 11,
            color: HmiColors.textMuted,
          ),
        ),
      ],
    );
  }
}
