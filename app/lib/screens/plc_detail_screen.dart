import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:google_fonts/google_fonts.dart';

import '../stores/dashboard_store.dart';
import '../theme/hmi_colors.dart';
import '../widgets/gauge_widget.dart';
import '../widgets/line_chart_widget.dart';

/// Detailed view for a PLC device — shows all registers with gauges & charts.
/// Includes a device switcher so the user can flip between PLCs.
class PlcDetailScreen extends StatelessWidget {
  final DashboardStore store;

  const PlcDetailScreen({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HmiColors.void_,
      body: Observer(
        builder: (_) {
          final devices = store.devices;
          final activeId = store.activeDeviceId;
          final activeDevice = store.activeDevice;

          return Column(
            children: [
              // ── Device Selector Header ──
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: HmiColors.surface,
                  border: Border(
                    bottom:
                        BorderSide(color: HmiColors.surfaceBorder, width: 1),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.precision_manufacturing_rounded,
                            size: 20, color: HmiColors.accent),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            activeDevice?.name ?? activeId,
                            style: GoogleFonts.outfit(
                              fontSize: 18,
                              fontWeight: FontWeight.w600,
                              color: HmiColors.textPrimary,
                            ),
                          ),
                        ),
                        if (activeDevice != null)
                          _connectionBadge(activeDevice.isConnected),
                      ],
                    ),
                    if (devices.length > 1) ...[
                      const SizedBox(height: 10),
                      SizedBox(
                        height: 34,
                        child: ListView.separated(
                          scrollDirection: Axis.horizontal,
                          itemCount: devices.length,
                          separatorBuilder: (_, __) =>
                              const SizedBox(width: 8),
                          itemBuilder: (ctx, i) {
                            final dev = devices[i];
                            final isActive = dev.id == activeId;
                            return _deviceTab(
                              dev.name,
                              dev.protocol.toUpperCase(),
                              isActive,
                              dev.isConnected,
                              () => store.switchDevice(dev.id),
                            );
                          },
                        ),
                      ),
                    ],
                  ],
                ),
              ),

              // ── Main Content ──
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(16),
                  children: [
                    _sectionHeader('Live Gauges'),
                    const SizedBox(height: 12),
                    _buildGauges(),
                    const SizedBox(height: 24),
                    _sectionHeader('Register Trends'),
                    const SizedBox(height: 8),
                    ..._buildCharts(),
                    const SizedBox(height: 32),
                  ],
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _connectionBadge(bool connected) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: (connected ? HmiColors.healthy : HmiColors.danger)
            .withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(
          color: (connected ? HmiColors.healthy : HmiColors.danger)
              .withValues(alpha: 0.4),
        ),
      ),
      child: Row(
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
          const SizedBox(width: 5),
          Text(
            connected ? 'ONLINE' : 'OFFLINE',
            style: GoogleFonts.dmMono(
              fontSize: 10,
              fontWeight: FontWeight.w700,
              color: connected ? HmiColors.healthy : HmiColors.danger,
            ),
          ),
        ],
      ),
    );
  }

  Widget _deviceTab(
    String name,
    String protocol,
    bool isActive,
    bool isConnected,
    VoidCallback onTap,
  ) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: isActive
              ? HmiColors.accent.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive
                ? HmiColors.accent.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isConnected ? HmiColors.healthy : HmiColors.danger,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              name,
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? HmiColors.accent : HmiColors.textSecondary,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              protocol,
              style: GoogleFonts.dmMono(
                fontSize: 9,
                fontWeight: FontWeight.w600,
                color: HmiColors.textMuted,
              ),
            ),
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

  Widget _buildGauges() {
    final gaugeConfigs = [
      ('temperature', () => store.temperature, 0.0, 120.0, 80.0, 100.0),
      ('pressure', () => store.pressure, 800.0, 1600.0, 1100.0, 1300.0),
      ('humidity', () => store.humidity, 0.0, 100.0, 70.0, 85.0),
      ('flowRate', () => store.flowRate, 0.0, 200.0, 150.0, 180.0),
      ('agitatorSpeed', () => store.agitatorSpeed, 0.0, 600.0, 400.0, 500.0),
      ('pH', () => store.pH, 0.0, 14.0, 9.0, 11.0),
    ];

    final rows = <Widget>[];
    for (var i = 0; i < gaugeConfigs.length; i += 3) {
      final rowItems = gaugeConfigs.skip(i).take(3).toList();
      rows.add(
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: rowItems.map((g) {
            final (key, getValue, min, max, warn, danger) = g;
            final reg = store.config.registerByKey(key);
            return GaugeWidget(
              label: reg?.label ?? key,
              value: getValue(),
              unit: reg?.unit ?? '',
              min: min,
              max: max,
              warningThreshold: warn,
              dangerThreshold: danger,
              size: 130,
            );
          }).toList(),
        ),
      );
      if (i + 3 < gaugeConfigs.length) {
        rows.add(const SizedBox(height: 16));
      }
    }
    return Column(children: rows);
  }

  List<Widget> _buildCharts() {
    final chartKeys = [
      'temperature',
      'pressure',
      'humidity',
      'flowRate',
      'agitatorSpeed',
    ];
    return chartKeys.map((key) {
      final reg = store.config.registerByKey(key);
      if (reg == null) return const SizedBox.shrink();
      final history = store.registerHistory[reg.address]?.toList() ?? [];
      return Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: LiveLineChart(
          title: '${reg.label} (${reg.unit})',
          values: history.map((d) {
            final v = d.value;
            return reg.divisor != 1 ? v / reg.divisor : v;
          }).toList(),
          unit: reg.unit,
          lineColor: reg.color,
          height: 160,
        ),
      );
    }).toList();
  }
}
