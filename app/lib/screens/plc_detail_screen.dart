import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:google_fonts/google_fonts.dart';

import '../stores/dashboard_store.dart';
import '../theme/hmi_colors.dart';
import '../widgets/gauge_widget.dart';
import '../widgets/line_chart_widget.dart';

/// Detailed view for a single PLC device.
/// Shows all 8 registers with individual gauges and charts.
class PlcDetailScreen extends StatelessWidget {
  final DashboardStore store;

  const PlcDetailScreen({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HmiColors.void_,
      appBar: AppBar(
        title: Text(
          'PLC-01  Reactor',
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: HmiColors.textPrimary,
          ),
        ),
        backgroundColor: HmiColors.void_,
      ),
      body: Observer(
        builder: (_) => ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // ── Gauge Row: Temp + Pressure ──────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                GaugeWidget(
                  label: 'Temperature',
                  value: store.temperature,
                  unit: '°C',
                  min: 0,
                  max: 120,
                  warningThreshold: 80,
                  dangerThreshold: 100,
                  size: 140,
                ),
                GaugeWidget(
                  label: 'Pressure',
                  value: store.pressure,
                  unit: 'mbar',
                  min: 800,
                  max: 1200,
                  warningThreshold: 1100,
                  dangerThreshold: 1150,
                  size: 140,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Gauge Row: Humidity + Flow ──────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                GaugeWidget(
                  label: 'Humidity',
                  value: store.humidity,
                  unit: '%',
                  min: 0,
                  max: 100,
                  warningThreshold: 70,
                  dangerThreshold: 85,
                  size: 140,
                ),
                GaugeWidget(
                  label: 'Flow Rate',
                  value: store.flowRate,
                  unit: 'L/min',
                  min: 0,
                  max: 200,
                  warningThreshold: 150,
                  dangerThreshold: 180,
                  size: 140,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // ── Gauge Row: Agitator + pH ────────────────────────────
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                GaugeWidget(
                  label: 'Agitator',
                  value: store.agitatorSpeed,
                  unit: 'RPM',
                  min: 0,
                  max: 500,
                  warningThreshold: 300,
                  dangerThreshold: 400,
                  size: 140,
                ),
                GaugeWidget(
                  label: 'pH',
                  value: store.pH,
                  unit: '',
                  min: 0,
                  max: 14,
                  warningThreshold: 9,
                  dangerThreshold: 11,
                  size: 140,
                ),
              ],
            ),
            const SizedBox(height: 24),

            // ── All Register Charts ─────────────────────────────────
            _sectionHeader('Register Trends'),
            const SizedBox(height: 8),
            ..._buildCharts(),
            const SizedBox(height: 32),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) {
    return Text(
      title,
      style: GoogleFonts.outfit(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: HmiColors.textSecondary,
      ),
    );
  }

  List<Widget> _buildCharts() {
    final registers = [
      (1028, 'Temperature (°C)', '°C', HmiColors.accent),
      (1029, 'Pressure (mbar)', 'mbar', HmiColors.info),
      (1030, 'Humidity (%)', '%', HmiColors.info),
      (1031, 'Flow Rate (L/min)', 'L/min', HmiColors.healthy),
      (1034, 'Agitator (RPM)', 'RPM', HmiColors.warning),
    ];

    return registers.map((r) {
      final (reg, label, unit, color) = r;
      final history = store.registerHistory[reg]?.toList() ?? [];
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: LiveLineChart(
          title: label,
          values: history.map((d) => d.value).toList(),
          unit: unit,
          lineColor: color,
          height: 160,
        ),
      );
    }).toList();
  }
}
