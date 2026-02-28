import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/plc_data.dart';
import '../stores/dashboard_store.dart';
import '../theme/hmi_colors.dart';

/// A single point-in-time snapshot with all register values grouped.
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

/// Historical data screen — fetches past readings, groups by timestamp.
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
  int _limit = 200; // fetch more raw rows to get decent grouped snapshots

  @override
  void initState() {
    super.initState();
    _fetchHistory();
  }

  Future<void> _fetchHistory() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final data = await widget.store.fetchHistory(
        deviceId: 'plc-01',
        limit: _limit,
      );
      setState(() {
        _snapshots = _groupByTimestamp(data);
        _loading = false;
      });
    } catch (e) {
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  /// Group raw per-register rows into snapshots by second.
  List<_Snapshot> _groupByTimestamp(List<PlcData> raw) {
    final Map<String, _Snapshot> map = {};

    for (final d in raw) {
      // Group by second (strip milliseconds).
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
    list.sort((a, b) => b.time.compareTo(a.time)); // newest first
    return list;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: HmiColors.void_,
      appBar: AppBar(
        title: Text(
          'History',
          style: GoogleFonts.outfit(
            fontSize: 18,
            fontWeight: FontWeight.w600,
            color: HmiColors.textPrimary,
          ),
        ),
        backgroundColor: HmiColors.void_,
        actions: [
          PopupMenuButton<int>(
            icon: const Icon(Icons.filter_list, color: HmiColors.textSecondary),
            color: HmiColors.surface,
            onSelected: (val) {
              _limit = val;
              _fetchHistory();
            },
            itemBuilder: (_) => [200, 400, 800, 1600]
                .map((n) => PopupMenuItem(
                      value: n,
                      child: Text(
                        '~${n ~/ 8} snapshots',
                        style: GoogleFonts.outfit(color: HmiColors.textPrimary),
                      ),
                    ))
                .toList(),
          ),
          IconButton(
            icon: const Icon(Icons.refresh, color: HmiColors.textSecondary),
            onPressed: _fetchHistory,
          ),
        ],
      ),
      body: _buildBody(),
    );
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
              child:
                  Text('Retry', style: GoogleFonts.outfit(color: HmiColors.accent)),
            ),
          ],
        ),
      );
    }

    if (_snapshots.isEmpty) {
      return Center(
        child: Text('No history data',
            style: GoogleFonts.outfit(fontSize: 14, color: HmiColors.textMuted)),
      );
    }

    return Column(
      children: [
        // Summary bar.
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          color: HmiColors.surface,
          child: Text(
            '${_snapshots.length} snapshots  •  1 per second  •  newest first',
            style: GoogleFonts.outfit(fontSize: 12, color: HmiColors.textMuted),
          ),
        ),
        const Divider(height: 1, color: HmiColors.surfaceBorder),
        // Snapshot list.
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: _snapshots.length,
            itemBuilder: (ctx, i) => _buildSnapshotCard(_snapshots[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildSnapshotCard(_Snapshot snap) {
    final timeStr = DateFormat('HH:mm:ss').format(snap.time.toLocal());

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: HmiColors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: HmiColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header row: timestamp + batch state badge.
          Row(
            children: [
              Icon(Icons.access_time, size: 14, color: HmiColors.textMuted),
              const SizedBox(width: 6),
              Text(
                timeStr,
                style: GoogleFonts.dmMono(
                    fontSize: 13, color: HmiColors.textSecondary),
              ),
              const Spacer(),
              // Batch state badge.
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: snap.batchColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(4),
                  border:
                      Border.all(color: snap.batchColor.withValues(alpha: 0.3)),
                ),
                child: Text(
                  snap.batchLabel,
                  style: GoogleFonts.dmMono(
                      fontSize: 11,
                      fontWeight: FontWeight.w500,
                      color: snap.batchColor),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '${snap.progress.toInt()}%',
                style: GoogleFonts.dmMono(
                    fontSize: 12, color: HmiColors.textSecondary),
              ),
            ],
          ),
          const SizedBox(height: 10),
          // Values grid — 2 rows of 3.
          Row(
            children: [
              _val('Temp', '${snap.temp.toInt()}', '°C', HmiColors.accent),
              _val('Press', snap.pressure.toInt().toString(), 'mbar',
                  HmiColors.info),
              _val('Humid', '${snap.humidity.toInt()}', '%', HmiColors.info),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            children: [
              _val('Flow', '${snap.flow.toInt()}', 'L/m', HmiColors.healthy),
              _val('Agit', '${snap.agitator.toInt()}', 'RPM',
                  HmiColors.warning),
              _val('pH', snap.pH.toStringAsFixed(1), '', HmiColors.accent),
            ],
          ),
        ],
      ),
    );
  }

  /// Single value cell inside the snapshot card.
  Widget _val(String label, String value, String unit, Color color) {
    return Expanded(
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: GoogleFonts.outfit(
                      fontSize: 10, color: HmiColors.textMuted)),
              const SizedBox(height: 2),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(value,
                      style: GoogleFonts.dmMono(
                          fontSize: 16,
                          fontWeight: FontWeight.w500,
                          color: color)),
                  const SizedBox(width: 2),
                  Text(unit,
                      style: GoogleFonts.outfit(
                          fontSize: 10, color: HmiColors.textMuted)),
                ],
              ),
            ],
          ),
        ],
      ),
    );
  }
}
