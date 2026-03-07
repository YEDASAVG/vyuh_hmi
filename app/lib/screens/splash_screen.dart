import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/hmi_colors.dart';

/// Animated industrial splash screen with logo animation.
class SplashScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const SplashScreen({super.key, required this.onComplete});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with TickerProviderStateMixin {
  late final AnimationController _logoController;
  late final AnimationController _contentController;
  late final AnimationController _pulseController;
  late final Animation<double> _logoScale;
  late final Animation<double> _logoOpacity;
  late final Animation<double> _titleSlide;
  late final Animation<double> _titleOpacity;
  late final Animation<double> _subtitleOpacity;
  late final Animation<double> _shimmer;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();

    // Logo: scale up + fade in
    _logoController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _logoScale = Tween<double>(begin: 0.3, end: 1.0).animate(
      CurvedAnimation(parent: _logoController, curve: Curves.elasticOut),
    );
    _logoOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _logoController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );

    // Content: title + subtitle staggered
    _contentController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );
    _titleSlide = Tween<double>(begin: 30.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _contentController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );
    _titleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _contentController,
        curve: const Interval(0.0, 0.5, curve: Curves.easeOut),
      ),
    );
    _subtitleOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _contentController,
        curve: const Interval(0.4, 1.0, curve: Curves.easeOut),
      ),
    );
    _shimmer = Tween<double>(begin: -1.0, end: 2.0).animate(
      CurvedAnimation(
        parent: _contentController,
        curve: const Interval(0.5, 1.0, curve: Curves.easeInOut),
      ),
    );

    // Pulsing ring around logo
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1500),
    );
    _pulse = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeOut),
    );

    _startSequence();
  }

  Future<void> _startSequence() async {
    await Future.delayed(const Duration(milliseconds: 200));
    _logoController.forward();
    await Future.delayed(const Duration(milliseconds: 400));
    _contentController.forward();
    _pulseController.repeat();
    await Future.delayed(const Duration(milliseconds: 2200));
    widget.onComplete();
  }

  @override
  void dispose() {
    _logoController.dispose();
    _contentController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HmiColors.void_,
      body: Stack(
        children: [
          // Subtle grid pattern background
          const _GridBackground(),

          // Main content
          Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // ── Animated logo ──
                AnimatedBuilder(
                  animation: Listenable.merge([_logoController, _pulseController]),
                  builder: (context, child) {
                    return Stack(
                      alignment: Alignment.center,
                      children: [
                        // Expanding pulse ring
                        if (_pulseController.isAnimating)
                          Opacity(
                            opacity: (1.0 - _pulse.value) * 0.3,
                            child: Container(
                              width: 120 + (_pulse.value * 60),
                              height: 120 + (_pulse.value * 60),
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border: Border.all(
                                  color: HmiColors.accent,
                                  width: 2 * (1.0 - _pulse.value),
                                ),
                              ),
                            ),
                          ),
                        // Logo container
                        Opacity(
                          opacity: _logoOpacity.value,
                          child: Transform.scale(
                            scale: _logoScale.value,
                            child: Container(
                              width: 100,
                              height: 100,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const RadialGradient(
                                  colors: [
                                    Color(0xFF2A2A32),
                                    Color(0xFF18181C),
                                  ],
                                ),
                                border: Border.all(
                                  color: HmiColors.accent.withValues(alpha: 0.5),
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: HmiColors.accent.withValues(alpha: 0.2),
                                    blurRadius: 30,
                                    spreadRadius: 5,
                                  ),
                                ],
                              ),
                              child: const Icon(
                                Icons.precision_manufacturing_rounded,
                                size: 44,
                                color: HmiColors.accent,
                              ),
                            ),
                          ),
                        ),
                      ],
                    );
                  },
                ),
                const SizedBox(height: 32),

                // ── Title ──
                AnimatedBuilder(
                  animation: _contentController,
                  builder: (context, _) {
                    return Transform.translate(
                      offset: Offset(0, _titleSlide.value),
                      child: Opacity(
                        opacity: _titleOpacity.value,
                        child: ShaderMask(
                          shaderCallback: (bounds) {
                            return LinearGradient(
                              begin: Alignment(_shimmer.value - 1, 0),
                              end: Alignment(_shimmer.value, 0),
                              colors: const [
                                HmiColors.textPrimary,
                                HmiColors.accent,
                                HmiColors.textPrimary,
                              ],
                              stops: const [0.0, 0.5, 1.0],
                            ).createShader(bounds);
                          },
                          child: Text(
                            'VYUH HMI',
                            style: GoogleFonts.dmMono(
                              fontSize: 32,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 6,
                              color: Colors.white,
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 8),

                // ── Subtitle ──
                AnimatedBuilder(
                  animation: _contentController,
                  builder: (context, _) {
                    return Opacity(
                      opacity: _subtitleOpacity.value,
                      child: Text(
                        'Industrial Process Control',
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w400,
                          color: HmiColors.textSecondary,
                          letterSpacing: 2,
                        ),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 48),

                // ── Loading indicator ──
                AnimatedBuilder(
                  animation: _contentController,
                  builder: (context, _) {
                    return Opacity(
                      opacity: _subtitleOpacity.value,
                      child: SizedBox(
                        width: 160,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(2),
                          child: const LinearProgressIndicator(
                            minHeight: 2,
                            backgroundColor: HmiColors.surfaceBorder,
                            valueColor: AlwaysStoppedAnimation(HmiColors.accent),
                          ),
                        ),
                      ),
                    );
                  },
                ),
              ],
            ),
          ),

          // Version tag
          Positioned(
            bottom: 40,
            left: 0,
            right: 0,
            child: AnimatedBuilder(
              animation: _contentController,
              builder: (context, _) {
                return Opacity(
                  opacity: _subtitleOpacity.value,
                  child: Text(
                    'v1.0.0  •  ISA-88 / ISA-18.2 / 21 CFR 11',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.dmMono(
                      fontSize: 10,
                      color: HmiColors.textMuted,
                      letterSpacing: 1,
                    ),
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

/// Subtle animated grid lines background.
class _GridBackground extends StatefulWidget {
  const _GridBackground();

  @override
  State<_GridBackground> createState() => _GridBackgroundState();
}

class _GridBackgroundState extends State<_GridBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 8),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return CustomPaint(
          painter: _GridPainter(phase: _ctrl.value),
          size: Size.infinite,
        );
      },
    );
  }
}

class _GridPainter extends CustomPainter {
  final double phase;
  _GridPainter({required this.phase});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = HmiColors.surfaceBorder.withValues(alpha: 0.3)
      ..strokeWidth = 0.5;

    const spacing = 40.0;

    // Vertical lines
    for (double x = 0; x < size.width; x += spacing) {
      final shimmer = (math.sin((x / size.width + phase) * math.pi * 2) + 1) / 2;
      paint.color = HmiColors.surfaceBorder.withValues(alpha: 0.1 + shimmer * 0.15);
      canvas.drawLine(Offset(x, 0), Offset(x, size.height), paint);
    }

    // Horizontal lines
    for (double y = 0; y < size.height; y += spacing) {
      final shimmer = (math.sin((y / size.height + phase) * math.pi * 2) + 1) / 2;
      paint.color = HmiColors.surfaceBorder.withValues(alpha: 0.1 + shimmer * 0.15);
      canvas.drawLine(Offset(0, y), Offset(size.width, y), paint);
    }

    // Accent glow dot at center
    final center = Offset(size.width / 2, size.height / 2);
    final glowPaint = Paint()
      ..shader = RadialGradient(
        colors: [
          HmiColors.accent.withValues(alpha: 0.08),
          Colors.transparent,
        ],
      ).createShader(Rect.fromCircle(center: center, radius: 200));
    canvas.drawCircle(center, 200, glowPaint);
  }

  @override
  bool shouldRepaint(_GridPainter old) => old.phase != phase;
}
