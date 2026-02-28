import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/hmi_colors.dart';

/// Industrial circular gauge widget with color-zone arc.
/// Designed for HMI dashboards — large center value, sweep arc, min/max labels.
class GaugeWidget extends StatelessWidget {
  final String label;
  final double value;
  final String unit;
  final double min;
  final double max;
  final double? warningThreshold;
  final double? dangerThreshold;
  final double size;

  const GaugeWidget({
    super.key,
    required this.label,
    required this.value,
    required this.unit,
    this.min = 0,
    this.max = 100,
    this.warningThreshold,
    this.dangerThreshold,
    this.size = 160,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size + 28, // Extra space for label below.
      child: Column(
        children: [
          SizedBox(
            width: size,
            height: size,
            child: CustomPaint(
              painter: _GaugePainter(
                value: value,
                min: min,
                max: max,
                warningThreshold: warningThreshold,
                dangerThreshold: dangerThreshold,
              ),
              child: Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      value.toStringAsFixed(value < 10 ? 1 : 0),
                      style: GoogleFonts.dmMono(
                        fontSize: size * 0.22,
                        fontWeight: FontWeight.w500,
                        color: _valueColor,
                      ),
                    ),
                    Text(
                      unit,
                      style: GoogleFonts.outfit(
                        fontSize: size * 0.09,
                        fontWeight: FontWeight.w400,
                        color: HmiColors.textSecondary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: GoogleFonts.outfit(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: HmiColors.textSecondary,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Color get _valueColor {
    if (dangerThreshold != null && value >= dangerThreshold!) {
      return HmiColors.danger;
    }
    if (warningThreshold != null && value >= warningThreshold!) {
      return HmiColors.warning;
    }
    return HmiColors.accent;
  }
}

class _GaugePainter extends CustomPainter {
  final double value;
  final double min;
  final double max;
  final double? warningThreshold;
  final double? dangerThreshold;

  _GaugePainter({
    required this.value,
    required this.min,
    required this.max,
    this.warningThreshold,
    this.dangerThreshold,
  });

  static const double _startAngle = 135 * (math.pi / 180); // 7:30 position
  static const double _sweepTotal = 270 * (math.pi / 180); // 270° arc

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 12;
    final strokeWidth = size.width * 0.06;

    // ── Background track ──────────────────────────────────────────
    final trackPaint = Paint()
      ..color = HmiColors.surfaceBorder
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      _startAngle,
      _sweepTotal,
      false,
      trackPaint,
    );

    // ── Value arc ─────────────────────────────────────────────────
    final fraction = ((value - min) / (max - min)).clamp(0.0, 1.0);
    final valueSweep = _sweepTotal * fraction;

    final valuePaint = Paint()
      ..color = _arcColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      _startAngle,
      valueSweep,
      false,
      valuePaint,
    );

    // ── Glow effect on the value arc ──────────────────────────────
    final glowPaint = Paint()
      ..color = _arcColor.withValues(alpha: 0.25)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth * 2.5
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 8);

    canvas.drawArc(
      Rect.fromCircle(center: center, radius: radius),
      _startAngle,
      valueSweep,
      false,
      glowPaint,
    );

    // ── Tick marks at min & max ───────────────────────────────────
    _drawTick(canvas, center, radius + 6, _startAngle, size);
    _drawTick(canvas, center, radius + 6, _startAngle + _sweepTotal, size);

    // ── Min/Max labels ────────────────────────────────────────────
    _drawLabel(canvas, center, radius + 16, _startAngle, min.toInt().toString(),
        size);
    _drawLabel(canvas, center, radius + 16, _startAngle + _sweepTotal,
        max.toInt().toString(), size);
  }

  Color get _arcColor {
    if (dangerThreshold != null && value >= dangerThreshold!) {
      return HmiColors.danger;
    }
    if (warningThreshold != null && value >= warningThreshold!) {
      return HmiColors.warning;
    }
    return HmiColors.accent;
  }

  void _drawTick(
      Canvas canvas, Offset center, double radius, double angle, Size size) {
    final tickLength = size.width * 0.03;
    final p1 = Offset(
      center.dx + (radius - tickLength) * math.cos(angle),
      center.dy + (radius - tickLength) * math.sin(angle),
    );
    final p2 = Offset(
      center.dx + radius * math.cos(angle),
      center.dy + radius * math.sin(angle),
    );
    canvas.drawLine(
      p1,
      p2,
      Paint()
        ..color = HmiColors.textMuted
        ..strokeWidth = 1.5,
    );
  }

  void _drawLabel(Canvas canvas, Offset center, double radius, double angle,
      String text, Size size) {
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          fontSize: size.width * 0.07,
          color: HmiColors.textMuted,
          fontFamily: 'DM Mono',
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();

    final pos = Offset(
      center.dx + radius * math.cos(angle) - tp.width / 2,
      center.dy + radius * math.sin(angle) - tp.height / 2,
    );
    tp.paint(canvas, pos);
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.value != value || old.max != max || old.min != min;
}
