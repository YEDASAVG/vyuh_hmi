import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/plc_data.dart';
import '../stores/dashboard_store.dart';
import '../theme/hmi_colors.dart';

/// A grouped snapshot — one per second with all register values.
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

/// History screen — shows past readings per device, auto-refreshes.
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
  int _limit = 200;
  Timer? _refreshTimer;
  late String _selectedDeviceId;

  @override
  void initState() {
    super.initState();
    _selectedDeviceId = widget.store.activeDeviceId;
    _fetchHistory();
    // Auto-refresh every 5 seconds
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
    final Map<String, _Snapshot> map = {};
    for (final d in raw) {
      final dt = DateTime.tryParse(d.timestamp);
      if (dt == null) continue;
      final key = DateFormat('yyyy-MM-dd HH:mm:ss').format(dt.toLocal());
      final snap = map.putIfAbsent(key, () => _Snapshot(dt));
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
    final list = map.values.toList();
    list.sort((a, b) => b.time.compareTo(a.time));
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HmiColors.void_,
      body: Column(
        children: [
          // ── Header with device picker ──
          _buildHeader(),
          // ── Body ──
          Expanded(child: _buildBody()),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Observer(builder: (_) {
      final devices = widget.store.devices;
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: HmiColors.surface,
          border: Border(
            bottom: BorderSide(color: HmiColors.surfaceBorder, width: 1),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.history_rounded, size: 20, color: HmiColors.accent),
                const SizedBox(width: 8),
                Text(
                  'History',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: HmiColors.textPrimary,
                  ),
                ),
                const Spacer(),
                // Limit picker
                PopupMenuButton<int>(
                  icon: Icon(Icons.filter_list_rounded,
                      size: 20, color: HmiColors.textSecondary),
                  color: HmiColors.surface,
                  onSelected: (val) {
                    _limit = val;
                    _fetchHistory();
                  },
                  itemBuilder: (_) => [
                    for (final n in [100, 200, 400, 800])
                      PopupMenuItem(
                        value: n,
                        child: Text(
                          '~${n ~/ 8} snapshots',
                          style: GoogleFonts.outfit(
                              fontSize: 13, color: HmiColors.textPrimary),
                        ),
                      ),
                  ],
                ),
                IconButton(
                  icon: Icon(Icons.refresh_rounded,
                      size: 20, color: HmiColors.textSecondary),
                  onPressed: _fetchHistory,
                  tooltip: 'Refresh',
                ),
              ],
            ),
            if (devices.length > 1) ...[
              const SizedBox(height: 10),
              SizedBox(
                height: 34,
                child: ListView.separated(
                  scrollDirection: Axis.horizontal,
                  itemCount: devices.length,
                  separatorBuilder: (_, _) => const SizedBox(width: 8),
                  itemBuilder: (ctx, i) {
                    final dev = devices[i];
                    final isActive = dev.id == _selectedDeviceId;
                    return GestureDetector(
                      onTap: () {
                        setState(() => _selectedDeviceId = dev.id);
                        _fetchHistory();
                      },
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
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
                                color: dev.isConnected
                                    ? HmiColors.healthy
                                    : HmiColors.danger,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(
                              dev.name,
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                fontWeight: isActive
                                    ? FontWeight.w600
                                    : FontWeight.w400,
                                color: isActive
                                    ? HmiColors.accent
                                    : HmiColors.textSecondary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ],
          ],
        ),
      );
    });
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: HmiColors.accent),
      );
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: HmiColors.danger, size: 48),
            const SizedBox(height: 12),
            Text('Failed to load history',
                style: GoogleFonts.outfit(
                    fontSize: 16, color: HmiColors.textPrimary)),
            const SizedBox(height: 4),
            Text(_error!,
                style: GoogleFonts.outfit(
                    fontSize: 12, color: HmiColors.textMuted),
                textAlign: TextAlign.center),
            const SizedBox(height: 16),
            TextButton(
              onPressed: _fetchHistory,
              child: Text('Retry',
                  style: GoogleFonts.outfit(color: HmiColors.accent)),
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
            Icon(Icons.hourglass_empty_rounded,
                size: 48, color: HmiColors.textMuted),
            const SizedBox(height: 12),
            Text('No history yet',
                style: GoogleFonts.outfit(
                    fontSize: 16, color: HmiColors.textSecondary)),
            const SizedBox(height: 4),
            Text('Data will appear once the PLC starts collecting.',
                style: GoogleFonts.outfit(
                    fontSize: 12, color: HmiColors.textMuted)),
          ],
        ),
      );
    }

    return Column(
      children: [
        // Summary bar
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: HmiColors.surface.withValues(alpha: 0.5),
          child: Row(
            children: [
              _summaryChip(
                  Icons.data_array_rounded,
                  '${_snapshots.length} snapshots',
                  HmiColors.accent),
              const SizedBox(width: 12),
              _summaryChip(
                  Icons.timer_outlined,
                  '1/sec',
                  HmiColors.info),
              const Spacer(),
              Text(
                'Auto-refresh 5s',
                style: GoogleFonts.outfit(
                    fontSize: 10, color: HmiColors.textMuted),
              ),
            ],
          ),
        ),
        const Divider(height: 1, color: HmiColors.surfaceBorder),
        // Table header
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          color: HmiColors.surface,
          child: Row(
            children: [
              _headerCell('TIME', flex: 2),
              _headerCell('TEMP'),
              _headerCell('PSI'),
              _headerCell('RH%'),
              _headerCell('FLOW'),
              _headerCell('RPM'),
              _headerCell('pH'),
              _headerCell('STATE', flex: 2),
            ],
          ),
        ),
        const Divider(height: 1, color: HmiColors.surfaceBorder),
        // Data rows
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: _snapshots.length,
            itemBuilder: (ctx, i) => _buildRow(_snapshots[i], i),
          ),
        ),
      ],
    );
  }

  Widget _summaryChip(IconData icon, String text, Color color) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 4),
        Text(text,
            style: GoogleFonts.outfit(fontSize: 11, color: color)),
      ],
    );
  }

  Widget _headerCell(String text, {int flex = 1}) {
    return Expanded(
      flex: flex,
      child: Text(
        text,
        style: GoogleFonts.dmMono(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          letterSpacing: 0.5,
          color: HmiColors.textMuted,
        ),
      ),
    );
  }

  Widget _buildRow(_Snapshot snap, int index) {
    final timeStr = DateFormat('HH:mm:ss').format(snap.time.toLocal());
    final isEven = index % 2 == 0;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: isEven ? Colors.transparent : HmiColors.surface.withValues(alpha: 0.3),
      child: Row(
        children: [
          // Time
          Expanded(
            flex: 2,
            child: Text(
              timeStr,
              style: GoogleFonts.dmMono(
                  fontSize: 12, color: HmiColors.textSecondary),
            ),
          ),
          // Temp
          _dataCell('${snap.temp.toInt()}', HmiColors.accent),
          // Pressure
          _dataCell('${snap.pressure.toInt()}', HmiColors.info),
          // Humidity
          _dataCell('${snap.humidity.toInt()}', HmiColors.info),
          // Flow
          _dataCell('${snap.flow.toInt()}', HmiColors.healthy),
          // Agitator
          _dataCell('${snap.agitator.toInt()}', HmiColors.warning),
          // pH
          _dataCell(snap.pH.toStringAsFixed(1), const Color(0xFFAB47BC)),
          // Batch state
          Expanded(
            flex: 2,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              decoration: BoxDecoration(
                color: snap.batchColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(3),
              ),
              child: Text(
                '${snap.batchLabel} ${snap.progress.toInt()}%',
                style: GoogleFonts.dmMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: snap.batchColor,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _dataCell(String value, Color color) {
    return Expanded(
      child: Text(
        value,
        style: GoogleFonts.dmMono(
          fontSize: 12,
          fontWeight: FontWeight.w500,
          color: color,
        ),
      ),
    );
  }
}
