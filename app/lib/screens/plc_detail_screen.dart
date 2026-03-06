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
                          separatorBuilder: (_, _) =>
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
                    _sectionHeader('Write Controls'),
                    const SizedBox(height: 8),
                    _buildWriteControls(),
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

  Widget _buildWriteControls() {
    final writable = store.config.registers
        .where((r) => r.writable)
        .toList();
    if (writable.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: HmiColors.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: HmiColors.surfaceBorder),
        ),
        child: Text(
          'No writable registers on this device',
          style: GoogleFonts.outfit(fontSize: 13, color: HmiColors.textMuted),
        ),
      );
    }
    return Column(
      children: writable.map((reg) {
        final current = store.liveValues[reg.address] ?? 0;
        final display = reg.divisor != 1
            ? (current / reg.divisor).toStringAsFixed(1)
            : current.toInt().toString();
        return _WriteRegisterTile(
          label: reg.label,
          unit: reg.unit,
          address: reg.address,
          currentDisplay: display,
          isWriting: store.isWriting,
          onWrite: (value) => store.writeRegister(register: reg.address, value: value),
        );
      }).toList(),
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

// ── Inline Write Control ─────────────────────────────────────────────

class _WriteRegisterTile extends StatefulWidget {
  final String label;
  final String unit;
  final int address;
  final String currentDisplay;
  final bool isWriting;
  final Future<void> Function(int value) onWrite;

  const _WriteRegisterTile({
    required this.label,
    required this.unit,
    required this.address,
    required this.currentDisplay,
    required this.isWriting,
    required this.onWrite,
  });

  @override
  State<_WriteRegisterTile> createState() => _WriteRegisterTileState();
}

class _WriteRegisterTileState extends State<_WriteRegisterTile> {
  final _ctrl = TextEditingController();
  bool _busy = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final val = int.tryParse(_ctrl.text.trim());
    if (val == null) return;
    setState(() => _busy = true);
    await widget.onWrite(val);
    if (mounted) {
      setState(() => _busy = false);
      _ctrl.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: HmiColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: HmiColors.surfaceBorder),
      ),
      child: Row(
        children: [
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  widget.label,
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: HmiColors.textPrimary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Reg ${widget.address}  ·  NOW: ${widget.currentDisplay} ${widget.unit}',
                  style: GoogleFonts.dmMono(
                    fontSize: 10,
                    color: HmiColors.textMuted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 80,
            height: 34,
            child: TextField(
              controller: _ctrl,
              keyboardType: TextInputType.number,
              style: GoogleFonts.dmMono(
                fontSize: 13,
                color: HmiColors.textPrimary,
              ),
              decoration: InputDecoration(
                isDense: true,
                contentPadding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                hintText: 'value',
                hintStyle: GoogleFonts.dmMono(
                  fontSize: 11,
                  color: HmiColors.textMuted,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: HmiColors.surfaceBorder),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide: BorderSide(color: HmiColors.surfaceBorder),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(6),
                  borderSide:
                      const BorderSide(color: HmiColors.accent, width: 1.5),
                ),
              ),
              onSubmitted: (_) => _submit(),
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            height: 34,
            child: FilledButton(
              onPressed: _busy || widget.isWriting ? null : _submit,
              style: FilledButton.styleFrom(
                backgroundColor: HmiColors.accent,
                padding: const EdgeInsets.symmetric(horizontal: 12),
              ),
              child: _busy
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : Text('WRITE',
                      style: GoogleFonts.dmMono(
                        fontSize: 10,
                        fontWeight: FontWeight.w700,
                      )),
            ),
          ),
        ],
      ),
    );
  }
}
