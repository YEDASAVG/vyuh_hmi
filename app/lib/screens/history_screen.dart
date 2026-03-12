import 'dart:async';
import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../config/dashboard_config.dart';
import '../config/hmi_theme_engine.dart';
import '../models/plc_data.dart';
import '../stores/dashboard_store.dart';
import '../theme/hmi_colors.dart';

// ── Snapshot model ─────────────────────────────────────────────────────────

class _Snapshot {
  final DateTime time;
  double temp;
  double pressure;
  double humidity;
  double flow;
  int batchState;
  double progress;
  double agitator;
  double pH;

  _Snapshot(this.time)
      : temp = 0,
        pressure = 0,
        humidity = 0,
        flow = 0,
        batchState = 0,
        progress = 0,
        agitator = 0,
        pH = 0;

  String get batchLabel => switch (batchState) {
        0 => 'IDLE',
        1 => 'HEATING',
        2 => 'HOLDING',
        3 => 'COOLING',
        4 => 'COMPLETE',
        _ => 'UNKNOWN',
      };

  Color get batchColor => HmiColors.batchStateColor(batchLabel);
}

// ── Chart channel descriptor ───────────────────────────────────────────────

class _Channel {
  final String label;
  final String unit;
  final Color color;
  final double Function(_Snapshot s) getValue;

  const _Channel({
    required this.label,
    required this.unit,
    required this.color,
    required this.getValue,
  });
}

// ── Time‐range presets ─────────────────────────────────────────────────────

class _TimeRange {
  final String label;
  final int limit;       // raw rows to fetch
  final int intervalSec; // averaging bucket size

  const _TimeRange(this.label, this.limit, this.intervalSec);
}

const _timeRanges = <_TimeRange>[
  _TimeRange('5 min  (30 s avg)', 2400, 30),
  _TimeRange('10 min (1 min avg)', 4800, 60),
  _TimeRange('30 min (2 min avg)', 14400, 120),
  _TimeRange('1 hour (5 min avg)', 28800, 300),
];

// ── Screen ─────────────────────────────────────────────────────────────────

class HistoryScreen extends StatefulWidget {
  final DashboardStore store;

  const HistoryScreen({super.key, required this.store});

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  List<_Snapshot> _snapshots = [];
  bool _loading = true;
  String? _error;
  int _limit = 4800; // ~10 min of data (8 registers × 60s × 10min)
  int _intervalSec = 60; // averaging bucket size in seconds
  Timer? _refreshTimer;
  late String _selectedDeviceId;

  @override
  void initState() {
    super.initState();
    _selectedDeviceId = widget.store.activeDeviceId;
    _fetchHistory();
    _refreshTimer = Timer.periodic(
        const Duration(seconds: 5), (_) => _fetchHistory(silent: true));
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _fetchHistory({bool silent = false}) async {
    if (!silent) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final data = await widget.store.fetchHistory(
        deviceId: _selectedDeviceId,
        limit: _limit,
      );
      if (mounted) {
        setState(() {
          _snapshots = _groupByTimestamp(data);
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = e.toString();
          _loading = false;
        });
      }
    }
  }

  List<_Snapshot> _groupByTimestamp(List<PlcData> raw) {
    // Step 1: Group raw rows into per-second snapshots
    final Map<String, _Snapshot> secMap = {};
    for (final d in raw) {
      final dt = DateTime.tryParse(d.timestamp);
      if (dt == null) continue;
      final key = DateFormat('yyyy-MM-dd HH:mm:ss').format(dt.toLocal());
      final snap = secMap.putIfAbsent(key, () => _Snapshot(dt));
      switch (d.register) {
        case 1028:
          snap.temp = d.value;
        case 1029:
          snap.pressure = d.value;
        case 1030:
          snap.humidity = d.value;
        case 1031:
          snap.flow = d.value;
        case 1032:
          snap.batchState = d.value.toInt();
        case 1033:
          snap.progress = d.value;
        case 1034:
          snap.agitator = d.value;
        case 1035:
          snap.pH = d.value / 10.0;
      }
    }

    // Step 2: Downsample into N-second buckets by averaging
    final secList = secMap.values.toList()
      ..sort((a, b) => a.time.compareTo(b.time));

    if (secList.isEmpty || _intervalSec <= 1) return secList;

    final Map<int, List<_Snapshot>> buckets = {};
    final epoch0 = secList.first.time.millisecondsSinceEpoch;
    for (final s in secList) {
      final offset = s.time.millisecondsSinceEpoch - epoch0;
      final bucket = offset ~/ (_intervalSec * 1000);
      buckets.putIfAbsent(bucket, () => []).add(s);
    }

    final averaged = <_Snapshot>[];
    for (final entry in buckets.entries) {
      final group = entry.value;
      final n = group.length;
      // Use the midpoint time of the bucket
      final midTime = group[n ~/ 2].time;
      final avg = _Snapshot(midTime);
      avg.temp = group.fold(0.0, (s, e) => s + e.temp) / n;
      avg.pressure = group.fold(0.0, (s, e) => s + e.pressure) / n;
      avg.humidity = group.fold(0.0, (s, e) => s + e.humidity) / n;
      avg.flow = group.fold(0.0, (s, e) => s + e.flow) / n;
      avg.agitator = group.fold(0.0, (s, e) => s + e.agitator) / n;
      avg.pH = group.fold(0.0, (s, e) => s + e.pH) / n;
      avg.progress = group.last.progress;
      // batch state = most frequent in the bucket
      final stateFreq = <int, int>{};
      for (final g in group) {
        stateFreq[g.batchState] = (stateFreq[g.batchState] ?? 0) + 1;
      }
      avg.batchState = stateFreq.entries
          .reduce((a, b) => a.value >= b.value ? a : b)
          .key;
      averaged.add(avg);
    }
    averaged.sort((a, b) => a.time.compareTo(b.time));
    return averaged;
  }

  // ── Channel definitions ────────────────────────────────────────

  static final _channels = <_Channel>[
    _Channel(
        label: 'Temperature',
        unit: '°C',
        color: const Color(0xFFE8763A),
        getValue: (s) => s.temp),
    _Channel(
        label: 'Pressure',
        unit: 'PSI',
        color: const Color(0xFF3B82F6),
        getValue: (s) => s.pressure),
    _Channel(
        label: 'Flow Rate',
        unit: 'L/min',
        color: const Color(0xFF22C55E),
        getValue: (s) => s.flow),
    _Channel(
        label: 'pH Level',
        unit: 'pH',
        color: const Color(0xFFAB47BC),
        getValue: (s) => s.pH),
    _Channel(
        label: 'Humidity',
        unit: '%RH',
        color: const Color(0xFF06B6D4),
        getValue: (s) => s.humidity),
    _Channel(
        label: 'Agitator',
        unit: 'RPM',
        color: const Color(0xFFF59E0B),
        getValue: (s) => s.agitator),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = ActiveTheme.of(context);

    return Scaffold(
      backgroundColor: colors.background,
      body: Column(
        children: [
          _buildHeader(colors),
          Expanded(child: _buildBody(colors)),
        ],
      ),
    );
  }

  // ── Header ─────────────────────────────────────────────────────

  Widget _buildHeader(ThemeConfig colors) {
    return Observer(builder: (_) {
      final devices = widget.store.devices;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
        decoration: BoxDecoration(
          color: colors.surface,
          border: Border(
            bottom: BorderSide(color: colors.surfaceBorder, width: 1),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.show_chart_rounded,
                size: 28, color: colors.accent),
            const SizedBox(width: 12),
            Text(
              'HISTORIAN',
              style: GoogleFonts.outfit(
                fontSize: 24,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
                letterSpacing: 2,
              ),
            ),
            const SizedBox(width: 24),
            if (devices.length > 1)
              ...devices.map((dev) {
                final isActive = dev.id == _selectedDeviceId;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: GestureDetector(
                    onTap: () {
                      setState(() => _selectedDeviceId = dev.id);
                      _fetchHistory();
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
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
                              color: dev.isConnected
                                  ? colors.healthy
                                  : colors.danger,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            dev.name,
                            style: GoogleFonts.outfit(
                              fontSize: 15,
                              fontWeight: isActive
                                  ? FontWeight.w600
                                  : FontWeight.w400,
                              color: isActive
                                  ? colors.accent
                                  : colors.textSecondary,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            const Spacer(),
            // Snapshots count badge
            if (_snapshots.isNotEmpty)
              Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.data_array_rounded,
                        size: 18, color: colors.accent),
                    const SizedBox(width: 6),
                    Text(
                      '${_snapshots.length} pts · ${_intervalSec}s avg',
                      style: GoogleFonts.dmMono(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: colors.accent),
                    ),
                  ],
                ),
              ),
            const SizedBox(width: 12),
            PopupMenuButton<_TimeRange>(
              icon: Icon(Icons.filter_list_rounded,
                  size: 24, color: colors.textSecondary),
              color: colors.surface,
              onSelected: (val) {
                _limit = val.limit;
                _intervalSec = val.intervalSec;
                _fetchHistory();
              },
              itemBuilder: (_) => [
                for (final r in _timeRanges)
                  PopupMenuItem(
                    value: r,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _limit == r.limit
                              ? Icons.radio_button_checked
                              : Icons.radio_button_unchecked,
                          size: 18,
                          color: _limit == r.limit
                              ? colors.accent
                              : colors.textMuted,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          r.label,
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            color: _limit == r.limit
                                ? colors.accent
                                : colors.textPrimary,
                            fontWeight: _limit == r.limit
                                ? FontWeight.w600
                                : FontWeight.w400,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 4),
            IconButton(
              icon: Icon(Icons.refresh_rounded,
                  size: 24, color: colors.textSecondary),
              onPressed: _fetchHistory,
              tooltip: 'Refresh',
            ),
          ],
        ),
      );
    });
  }

  // ── Body ───────────────────────────────────────────────────────

  Widget _buildBody(ThemeConfig colors) {
    if (_loading) {
      return Center(
          child: CircularProgressIndicator(color: colors.accent));
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline, color: colors.danger, size: 64),
            const SizedBox(height: 16),
            Text('Failed to load history',
                style: GoogleFonts.outfit(
                    fontSize: 22, color: colors.textPrimary)),
            const SizedBox(height: 8),
            Text(_error!,
                style: GoogleFonts.outfit(
                    fontSize: 14, color: colors.textMuted),
                textAlign: TextAlign.center),
            const SizedBox(height: 20),
            TextButton(
              onPressed: _fetchHistory,
              child: Text('Retry',
                  style: GoogleFonts.outfit(
                      fontSize: 18, color: colors.accent)),
            ),
          ],
        ),
      );
    }

    if (_snapshots.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.show_chart_rounded,
                size: 80, color: colors.textMuted),
            const SizedBox(height: 16),
            Text('No history yet',
                style: GoogleFonts.outfit(
                    fontSize: 22, color: colors.textSecondary)),
            const SizedBox(height: 8),
            Text('Charts will appear once the PLC starts collecting.',
                style: GoogleFonts.outfit(
                    fontSize: 16, color: colors.textMuted)),
          ],
        ),
      );
    }

    // Fill all vertical space with a 3×2 grid of chart panels
    const rows = 3; // 6 channels → 3 rows of 2
    const gap = 14.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final totalH = constraints.maxHeight;
        final panelH = (totalH - gap * (rows - 1) - 24) / rows; // 24 = top+bottom pad
        return Padding(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 12),
          child: Column(
            children: [
              for (var r = 0; r < rows; r++) ...[
                if (r > 0) const SizedBox(height: gap),
                Expanded(
                  child: Row(
                    children: [
                      Expanded(
                          child: _buildChartPanel(
                              _channels[r * 2], colors, panelH)),
                      const SizedBox(width: 14),
                      Expanded(
                          child: (r * 2 + 1 < _channels.length)
                              ? _buildChartPanel(
                                  _channels[r * 2 + 1], colors, panelH)
                              : const SizedBox()),
                    ],
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  // ── Individual chart panel ─────────────────────────────────────

  Widget _buildChartPanel(_Channel channel, ThemeConfig colors, double panelH) {
    final values = _snapshots.map(channel.getValue).toList();

    // Compute Y bounds
    double minY = values.isEmpty ? 0 : values.reduce(math.min);
    double maxY = values.isEmpty ? 100 : values.reduce(math.max);
    final pad = (maxY - minY) * 0.15;
    minY = minY - pad;
    maxY = maxY + pad;
    if ((maxY - minY).abs() < 1) {
      minY -= 1;
      maxY += 1;
    }

    final latest = values.isNotEmpty ? values.last : 0.0;
    final minVal = values.isEmpty ? 0.0 : values.reduce(math.min);
    final maxVal = values.isEmpty ? 0.0 : values.reduce(math.max);

    final spots = <FlSpot>[];
    for (var i = 0; i < values.length; i++) {
      spots.add(FlSpot(i.toDouble(), values[i]));
    }

    final xCount = spots.length;
    final labelInterval =
        xCount > 6 ? (xCount / 5).ceil().toDouble() : 1.0;

    return Container(
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colors.surfaceBorder),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Title row — big readable fonts
          Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: channel.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 10),
              Text(
                channel.label.toUpperCase(),
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 1.2,
                ),
              ),
              const SizedBox(width: 20),
              Text(
                'MIN ${minVal.toStringAsFixed(1)}',
                style: GoogleFonts.dmMono(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.white70),
              ),
              const SizedBox(width: 16),
              Text(
                'MAX ${maxVal.toStringAsFixed(1)}',
                style: GoogleFonts.dmMono(
                    fontSize: 15,
                    fontWeight: FontWeight.w500,
                    color: Colors.white70),
              ),
              const Spacer(),
              // Current value — large and bright
              Text(
                '${latest.toStringAsFixed(1)} ${channel.unit}',
                style: GoogleFonts.dmMono(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: channel.color,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Chart — fills remaining space
          Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: false,
                  horizontalInterval: (maxY - minY) / 4,
                  getDrawingHorizontalLine: (_) => FlLine(
                    color: colors.surfaceBorder,
                    strokeWidth: 0.6,
                  ),
                ),
                titlesData: FlTitlesData(
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 56,
                      interval: (maxY - minY) / 4,
                      getTitlesWidget: (value, meta) => Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: Text(
                          value.toStringAsFixed(0),
                          style: GoogleFonts.dmMono(
                              fontSize: 14,
                              color: Colors.white60),
                          textAlign: TextAlign.right,
                        ),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 28,
                      interval: labelInterval,
                      getTitlesWidget: (value, meta) {
                        final idx = value.toInt();
                        if (idx < 0 || idx >= _snapshots.length) {
                          return const SizedBox.shrink();
                        }
                        return Text(
                          DateFormat('HH:mm').format(
                              _snapshots[idx].time.toLocal()),
                          style: GoogleFonts.dmMono(
                              fontSize: 14,
                              color: Colors.white60),
                        );
                      },
                    ),
                  ),
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                ),
                borderData: FlBorderData(show: false),
                minX: 0,
                maxX: spots.isEmpty ? 1 : (spots.length - 1).toDouble(),
                minY: minY,
                maxY: maxY,
                lineTouchData: LineTouchData(
                  handleBuiltInTouches: true,
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipColor: (_) => colors.surface,
                    getTooltipItems: (touchedSpots) =>
                        touchedSpots.map((s) {
                      final idx = s.x.toInt();
                      final time = idx >= 0 && idx < _snapshots.length
                          ? DateFormat('HH:mm:ss').format(
                              _snapshots[idx].time.toLocal())
                          : '';
                      return LineTooltipItem(
                        '${s.y.toStringAsFixed(1)} ${channel.unit}\n$time',
                        GoogleFonts.dmMono(
                          fontSize: 16,
                          color: channel.color,
                          fontWeight: FontWeight.w600,
                        ),
                      );
                    }).toList(),
                  ),
                ),
                lineBarsData: [
                  LineChartBarData(
                    spots: spots,
                    isCurved: true,
                    curveSmoothness: 0.2,
                    color: channel.color,
                    barWidth: 3,
                    isStrokeCapRound: true,
                    dotData: const FlDotData(show: false),
                    belowBarData: BarAreaData(
                      show: true,
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          channel.color.withValues(alpha: 0.25),
                          channel.color.withValues(alpha: 0.0),
                        ],
                      ),
                    ),
                    shadow: Shadow(
                      color: channel.color.withValues(alpha: 0.3),
                      blurRadius: 8,
                    ),
                  ),
                ],
              ),
              duration: const Duration(milliseconds: 200),
            ),
          ),
        ],
      ),
    );
  }
}
