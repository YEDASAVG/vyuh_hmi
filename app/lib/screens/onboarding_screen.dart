import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../theme/hmi_colors.dart';

/// Two-page onboarding flow shown on first launch.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;

  const OnboardingScreen({super.key, required this.onComplete});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = [
    _OnboardingData(
      icon: Icons.dashboard_customize_rounded,
      accentColor: HmiColors.accent,
      title: 'Real-Time Monitoring',
      description:
          'Live gauges, charts, and stat cards streaming directly from '
          'your PLC over Modbus TCP and OPC UA. '
          'Monitor temperature, pressure, flow, and batch state — all in one glance.',
      features: [
        _Feature(Icons.speed_rounded, 'Live gauge & sparklines'),
        _Feature(Icons.compare_arrows_rounded, 'Modbus TCP + OPC UA'),
        _Feature(Icons.notifications_active_rounded, 'ISA-18.2 alarms'),
      ],
    ),
    _OnboardingData(
      icon: Icons.verified_user_rounded,
      accentColor: HmiColors.healthy,
      title: 'Pharma-Grade Compliance',
      description:
          'Built for 21 CFR Part 11 with electronic signatures, '
          'full audit trails, and ISA-88 batch records. '
          'Every operator action is logged, timestamped, and traceable.',
      features: [
        _Feature(Icons.fingerprint_rounded, 'Electronic signatures'),
        _Feature(Icons.history_edu_rounded, 'Complete audit trail'),
        _Feature(Icons.assignment_turned_in_rounded, 'ISA-88 batch records'),
      ],
    ),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_page < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 400),
        curve: Curves.easeInOut,
      );
    } else {
      widget.onComplete();
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomPad = MediaQuery.of(context).padding.bottom;

    return Scaffold(
      backgroundColor: HmiColors.void_,
      body: Column(
        children: [
          // ── Pages ──
          Expanded(
            child: PageView.builder(
              controller: _controller,
              itemCount: _pages.length,
              onPageChanged: (i) => setState(() => _page = i),
              itemBuilder: (context, index) {
                return _OnboardingPage(data: _pages[index]);
              },
            ),
          ),

          // ── Bottom bar: dots + buttons ──
          Padding(
            padding: EdgeInsets.fromLTRB(24, 0, 24, 20 + bottomPad),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 600),
                child: Row(
              children: [
                // Skip button
                if (_page < _pages.length - 1)
                  TextButton(
                    onPressed: widget.onComplete,
                    child: Text(
                      'Skip',
                      style: GoogleFonts.outfit(
                        color: HmiColors.textMuted,
                        fontSize: 14,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  )
                else
                  const SizedBox(width: 60),

                const Spacer(),

                // Page dots
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: List.generate(_pages.length, (i) {
                    final isActive = i == _page;
                    return AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      margin: const EdgeInsets.symmetric(horizontal: 4),
                      width: isActive ? 24 : 8,
                      height: 8,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(4),
                        color: isActive
                            ? _pages[_page].accentColor
                            : HmiColors.surfaceBorder,
                      ),
                    );
                  }),
                ),

                const Spacer(),

                // Next / Get Started button
                Material(
                  color: Colors.transparent,
                  child: InkWell(
                    onTap: _next,
                    borderRadius: BorderRadius.circular(12),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 300),
                      padding: EdgeInsets.symmetric(
                        horizontal: _page == _pages.length - 1 ? 20 : 16,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: _pages[_page].accentColor,
                        borderRadius: BorderRadius.circular(12),
                        boxShadow: [
                          BoxShadow(
                            color: _pages[_page].accentColor.withValues(alpha: 0.3),
                            blurRadius: 12,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            _page == _pages.length - 1 ? 'Get Started' : 'Next',
                            style: GoogleFonts.outfit(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: Colors.white,
                            ),
                          ),
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.arrow_forward_rounded,
                            size: 18,
                            color: Colors.white,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
        ],
      ),
    );
  }
}

// ── Data models ───────────────────────────────────────────────────────────────

class _OnboardingData {
  final IconData icon;
  final Color accentColor;
  final String title;
  final String description;
  final List<_Feature> features;

  const _OnboardingData({
    required this.icon,
    required this.accentColor,
    required this.title,
    required this.description,
    required this.features,
  });
}

class _Feature {
  final IconData icon;
  final String label;
  const _Feature(this.icon, this.label);
}

// ── Single onboarding page ────────────────────────────────────────────────────

class _OnboardingPage extends StatefulWidget {
  final _OnboardingData data;
  const _OnboardingPage({required this.data});

  @override
  State<_OnboardingPage> createState() => _OnboardingPageState();
}

class _OnboardingPageState extends State<_OnboardingPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _anim;
  late final Animation<double> _iconScale;
  late final Animation<double> _contentSlide;
  late final Animation<double> _contentOpacity;

  @override
  void initState() {
    super.initState();
    _anim = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    );
    _iconScale = Tween<double>(begin: 0.5, end: 1.0).animate(
      CurvedAnimation(
        parent: _anim,
        curve: const Interval(0.0, 0.6, curve: Curves.elasticOut),
      ),
    );
    _contentSlide = Tween<double>(begin: 40.0, end: 0.0).animate(
      CurvedAnimation(
        parent: _anim,
        curve: const Interval(0.2, 0.8, curve: Curves.easeOut),
      ),
    );
    _contentOpacity = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _anim,
        curve: const Interval(0.2, 0.7, curve: Curves.easeOut),
      ),
    );
    _anim.forward();
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final data = widget.data;
    final topPad = MediaQuery.of(context).padding.top;
    final screenWidth = MediaQuery.of(context).size.width;
    final isWide = screenWidth >= 800;

    return AnimatedBuilder(
      animation: _anim,
      builder: (context, _) {
        if (isWide) {
          return _buildDesktopPage(data, topPad);
        }
        return _buildMobilePage(data, topPad);
      },
    );
  }

  Widget _buildMobilePage(_OnboardingData data, double topPad) {
    return Padding(
      padding: EdgeInsets.fromLTRB(28, topPad + 60, 28, 20),
      child: Column(
        children: [
          _buildAnimatedIcon(data),
          const SizedBox(height: 40),
          _buildTextContent(data),
          const SizedBox(height: 36),
          _buildFeaturePills(data),
        ],
      ),
    );
  }

  Widget _buildDesktopPage(_OnboardingData data, double topPad) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 900),
        child: Padding(
          padding: EdgeInsets.fromLTRB(40, topPad + 40, 40, 20),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Left — large icon with glow
              Expanded(
                flex: 2,
                child: _buildAnimatedIcon(data, size: 160, innerSize: 100, iconSize: 48),
              ),
              const SizedBox(width: 48),
              // Right — text + features
              Expanded(
                flex: 3,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildTextContent(data, align: TextAlign.start),
                    const SizedBox(height: 32),
                    _buildFeaturePills(data),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnimatedIcon(
    _OnboardingData data, {
    double size = 120,
    double innerSize = 80,
    double iconSize = 36,
  }) {
    return Transform.scale(
      scale: _iconScale.value,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: RadialGradient(
            colors: [
              data.accentColor.withValues(alpha: 0.15),
              Colors.transparent,
            ],
          ),
        ),
        child: Center(
          child: Container(
            width: innerSize,
            height: innerSize,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: HmiColors.surface,
              border: Border.all(
                color: data.accentColor.withValues(alpha: 0.4),
                width: 2,
              ),
              boxShadow: [
                BoxShadow(
                  color: data.accentColor.withValues(alpha: 0.15),
                  blurRadius: 20,
                  spreadRadius: 4,
                ),
              ],
            ),
            child: Icon(
              data.icon,
              size: iconSize,
              color: data.accentColor,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildTextContent(_OnboardingData data, {TextAlign align = TextAlign.center}) {
    return Transform.translate(
      offset: Offset(0, _contentSlide.value),
      child: Opacity(
        opacity: _contentOpacity.value,
        child: Column(
          crossAxisAlignment: align == TextAlign.start
              ? CrossAxisAlignment.start
              : CrossAxisAlignment.center,
          children: [
            Text(
              data.title,
              textAlign: align,
              style: GoogleFonts.outfit(
                fontSize: 26,
                fontWeight: FontWeight.w700,
                color: HmiColors.textPrimary,
                height: 1.2,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              data.description,
              textAlign: align,
              style: GoogleFonts.outfit(
                fontSize: 14,
                fontWeight: FontWeight.w400,
                color: HmiColors.textSecondary,
                height: 1.6,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFeaturePills(_OnboardingData data) {
    return Transform.translate(
      offset: Offset(0, _contentSlide.value * 1.2),
      child: Opacity(
        opacity: _contentOpacity.value,
        child: Column(
          children: data.features.map((f) {
            return Padding(
              padding: const EdgeInsets.only(bottom: 12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: HmiColors.surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: HmiColors.surfaceBorder),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(
                        color: data.accentColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        f.icon,
                        size: 18,
                        color: data.accentColor,
                      ),
                    ),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Text(
                        f.label,
                        style: GoogleFonts.outfit(
                          fontSize: 14,
                          fontWeight: FontWeight.w500,
                          color: HmiColors.textPrimary,
                        ),
                      ),
                    ),
                    Icon(
                      Icons.check_circle_rounded,
                      size: 18,
                      color: data.accentColor.withValues(alpha: 0.5),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}
