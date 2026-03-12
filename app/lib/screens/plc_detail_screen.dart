import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/dashboard_config.dart';
import '../config/hmi_theme_engine.dart';
import '../stores/dashboard_store.dart';
import '../widgets/gauge_widget.dart';
import '../widgets/line_chart_widget.dart';

/// Redesigned PLC Detail — big gauges (3×2 grid), 2-col write controls,
/// horizontal charts strip. Everything scaled for 2K factory displays.
class PlcDetailScreen extends StatelessWidget {
  final DashboardStore store;

  const PlcDetailScreen({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    final colors = ActiveTheme.of(context);

    return Scaffold(
      backgroundColor: colors.background,
      body: Observer(
        builder: (_) {
          final devices = store.devices;
          final activeId = store.activeDeviceId;
          final activeDevice = store.activeDevice;

          return Column(
            children: [
              // ── Compact Device Header ──
              _buildDeviceHeader(colors, devices, activeId, activeDevice),

              // ── Main Content ──
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    return _hmiLayout(context, constraints, colors);
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // ── Device Header ──────────────────────────────────────────────────

  Widget _buildDeviceHeader(
    ThemeConfig colors,
    List<dynamic> devices,
    String activeId,
    dynamic activeDevice,
  ) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          bottom: BorderSide(color: colors.surfaceBorder, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.precision_manufacturing_rounded,
              size: 28, color: colors.accent),
          const SizedBox(width: 12),
          Text(
            activeDevice?.name ?? activeId,
            style: GoogleFonts.outfit(
              fontSize: 28,
              fontWeight: FontWeight.w600,
              color: Colors.white,
            ),
          ),
          const SizedBox(width: 16),
          if (activeDevice != null)
            _connectionBadge(colors, activeDevice.isConnected),
          const Spacer(),
          if (devices.length > 1)
            ...devices.map((dev) {
              final isActive = dev.id == activeId;
              return Padding(
                padding: const EdgeInsets.only(left: 8),
                child: _deviceChip(
                    colors, dev.name, dev.protocol.toUpperCase(), isActive,
                    dev.isConnected, () => store.switchDevice(dev.id)),
              );
            }),
        ],
      ),
    );
  }

  Widget _connectionBadge(ThemeConfig colors, bool connected) {
    final c = connected ? colors.healthy : colors.danger;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: c.withValues(alpha: 0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: c),
          ),
          const SizedBox(width: 6),
          Text(
            connected ? 'ONLINE' : 'OFFLINE',
            style: GoogleFonts.dmMono(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: c,
            ),
          ),
        ],
      ),
    );
  }

  Widget _deviceChip(ThemeConfig colors, String name, String protocol,
      bool isActive, bool isConnected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(
          color: isActive
              ? colors.accent.withValues(alpha: 0.15)
              : Colors.white.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(
            color: isActive
                ? colors.accent.withValues(alpha: 0.5)
                : Colors.white.withValues(alpha: 0.1),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isConnected ? colors.healthy : colors.danger,
              ),
            ),
            const SizedBox(width: 8),
            Text(
              name,
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                color: isActive ? colors.accent : Colors.white70,
              ),
            ),
            const SizedBox(width: 6),
            Text(
              protocol,
              style: GoogleFonts.dmMono(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: Colors.white54,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Main Layout (2-column) ─────────────────────────────────────────

  Widget _hmiLayout(
      BuildContext context, BoxConstraints constraints, ThemeConfig colors) {
    final w = constraints.maxWidth;

    // On small screens, fall back to scrollable single column
    if (w < 900) {
      return ListView(
        padding: const EdgeInsets.all(20),
        children: [
          _sectionLabel(colors, 'LIVE REGISTERS'),
          const SizedBox(height: 16),
          _buildGaugeGrid(colors, constraints),
          const SizedBox(height: 28),
          _sectionLabel(colors, 'WRITE CONTROLS'),
          const SizedBox(height: 12),
          _buildWriteGrid(colors),
          const SizedBox(height: 28),
          _sectionLabel(colors, 'REGISTER TRENDS'),
          const SizedBox(height: 12),
          ..._buildChartList(colors),
        ],
      );
    }

    // Desktop: left (gauges + controls) | right (charts)
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Left: Gauges + Write Controls ──
        Expanded(
          flex: 6,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Gauge grid
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 20, 16, 0),
                child: _sectionLabel(colors, 'LIVE REGISTERS'),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 16, 0),
                  child: _buildGaugeGrid(colors, constraints),
                ),
              ),
              // Write controls
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 8, 16, 0),
                child: _sectionLabel(colors, 'WRITE CONTROLS'),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 12, 16, 16),
                child: _buildWriteGrid(colors),
              ),
            ],
          ),
        ),
        VerticalDivider(width: 1, color: colors.surfaceBorder),
        // ── Right: Charts ──
        Expanded(
          flex: 4,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
                child: _sectionLabel(colors, 'REGISTER TRENDS'),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                  children: _buildChartList(colors),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Section Label ──────────────────────────────────────────────────

  Widget _sectionLabel(ThemeConfig colors, String title) {
    return Text(
      title,
      style: GoogleFonts.outfit(
        fontSize: 24,
        fontWeight: FontWeight.w700,
        color: Colors.white70,
        letterSpacing: 2,
      ),
    );
  }

  // ── Gauge Grid (3×2 on desktop, fills available space) ─────────────

  Widget _buildGaugeGrid(ThemeConfig colors, BoxConstraints constraints) {
    final gaugeConfigs = [
      ('temperature', () => store.temperature, 0.0, 120.0, 80.0, 100.0),
      ('pressure', () => store.pressure, 800.0, 1600.0, 1100.0, 1300.0),
      ('humidity', () => store.humidity, 0.0, 100.0, 70.0, 85.0),
      ('flowRate', () => store.flowRate, 0.0, 200.0, 150.0, 180.0),
      ('agitatorSpeed', () => store.agitatorSpeed, 0.0, 600.0, 400.0, 500.0),
      ('pH', () => store.pH, 0.0, 14.0, 9.0, 11.0),
    ];

    return LayoutBuilder(
      builder: (context, gaugeConstraints) {
        final w = gaugeConstraints.maxWidth;
        final h = gaugeConstraints.maxHeight;

        // On desktop: 3 per row, 2 rows
        // On smaller screens: 2 per row, 3 rows
        final perRow = w >= 600 ? 3 : 2;
        final rows = (gaugeConfigs.length / perRow).ceil();

        // Calculate max gauge size to fill available space
        final hGap = 16.0;
        final vGap = 12.0;
        final maxGaugeW =
            (w - (perRow - 1) * hGap) / perRow;
        final maxGaugeH = h > 0
            ? (h - (rows - 1) * vGap - rows * 44) / rows // 44 for label below gauge
            : 240.0;
        final gaugeSize = (maxGaugeW < maxGaugeH ? maxGaugeW : maxGaugeH)
            .clamp(100.0, 280.0);

        final rowWidgets = <Widget>[];
        for (var i = 0; i < gaugeConfigs.length; i += perRow) {
          final rowItems = gaugeConfigs.skip(i).take(perRow).toList();
          rowWidgets.add(
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
                  size: gaugeSize,
                );
              }).toList(),
            ),
          );
          if (i + perRow < gaugeConfigs.length) {
            rowWidgets.add(SizedBox(height: vGap));
          }
        }

        return Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: rowWidgets,
        );
      },
    );
  }

  // ── Write Controls (2-column grid) ─────────────────────────────────

  Widget _buildWriteGrid(ThemeConfig colors) {
    final writable =
        store.config.registers.where((r) => r.writable).toList();
    if (writable.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colors.surfaceBorder),
        ),
        child: Text(
          'No writable registers on this device',
          style: GoogleFonts.outfit(fontSize: 20, color: Colors.white54),
        ),
      );
    }

    // 2-column grid of write tiles
    final rows = <Widget>[];
    for (var i = 0; i < writable.length; i += 2) {
      final left = writable[i];
      final right = i + 1 < writable.length ? writable[i + 1] : null;
      rows.add(
        Row(
          children: [
            Expanded(child: _buildWriteTile(colors, left)),
            const SizedBox(width: 12),
            Expanded(
              child: right != null
                  ? _buildWriteTile(colors, right)
                  : const SizedBox.shrink(),
            ),
          ],
        ),
      );
      if (i + 2 < writable.length) {
        rows.add(const SizedBox(height: 12));
      }
    }
    return Column(children: rows);
  }

  Widget _buildWriteTile(ThemeConfig colors, dynamic reg) {
    final current = store.liveValues[reg.address] ?? 0;
    final display = reg.divisor != 1
        ? (current / reg.divisor).toStringAsFixed(1)
        : current.toInt().toString();

    return _WriteRegisterTile(
      label: reg.label,
      unit: reg.unit,
      address: reg.address,
      currentDisplay: display,
      color: reg.color,
      isWriting: store.isWriting,
      onWrite: (value) =>
          store.writeRegister(register: reg.address, value: value),
    );
  }

  // ── Charts (stacked list, filling right column) ────────────────────

  List<Widget> _buildChartList(ThemeConfig colors) {
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
        padding: const EdgeInsets.only(bottom: 16),
        child: LiveLineChart(
          title: '${reg.label} (${reg.unit})',
          values: history.map((d) {
            final v = d.value;
            return reg.divisor != 1 ? v / reg.divisor : v;
          }).toList(),
          unit: reg.unit,
          lineColor: reg.color,
          height: 200,
        ),
      );
    }).toList();
  }
}

// ── Write Register Tile (big, card-style) ────────────────────────────

class _WriteRegisterTile extends StatefulWidget {
  final String label;
  final String unit;
  final int address;
  final String currentDisplay;
  final Color color;
  final bool isWriting;
  final Future<void> Function(int value) onWrite;

  const _WriteRegisterTile({
    required this.label,
    required this.unit,
    required this.address,
    required this.currentDisplay,
    required this.color,
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
    final colors = ActiveTheme.of(context);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Label + register address (single row)
          Row(
            children: [
              Expanded(
                child: Text(
                  widget.label.toUpperCase(),
                  style: GoogleFonts.outfit(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                    letterSpacing: 1,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              Text(
                'REG ${widget.address}',
                style: GoogleFonts.dmMono(
                  fontSize: 13,
                  color: Colors.white54,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          // Value + Input + Write in one row
          Row(
            children: [
              Text(
                widget.currentDisplay,
                style: GoogleFonts.dmMono(
                  fontSize: 28,
                  fontWeight: FontWeight.w600,
                  color: widget.color,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                widget.unit,
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  color: Colors.white70,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SizedBox(
                  height: 40,
                  child: TextField(
                    controller: _ctrl,
                    keyboardType: TextInputType.number,
                    style: GoogleFonts.dmMono(
                      fontSize: 18,
                      color: Colors.white,
                    ),
                    decoration: InputDecoration(
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      hintText: 'Value',
                      hintStyle: GoogleFonts.dmMono(
                        fontSize: 14,
                        color: Colors.white38,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: colors.surfaceBorder),
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide: BorderSide(color: colors.surfaceBorder),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(8),
                        borderSide:
                            BorderSide(color: colors.accent, width: 1.5),
                      ),
                    ),
                    onSubmitted: (_) => _submit(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 40,
                child: FilledButton(
                  onPressed: _busy || widget.isWriting ? null : _submit,
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                  child: _busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white),
                        )
                      : Text(
                          'WRITE',
                          style: GoogleFonts.dmMono(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
