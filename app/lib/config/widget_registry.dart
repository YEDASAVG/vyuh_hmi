import 'package:flutter/material.dart';

import '../stores/dashboard_store.dart';
import '../widgets/gauge_widget.dart';
import '../widgets/line_chart_widget.dart';
import '../widgets/stat_card.dart';
import 'dashboard_config.dart';

/// Maps config data to Flutter widgets.
///
/// The registry takes a [DashboardConfig] and [DashboardStore] and produces
/// the appropriate widgets driven entirely by config.
class WidgetRegistry {
  final DashboardConfig config;
  final DashboardStore store;

  const WidgetRegistry({required this.config, required this.store});

  // ── Gauge ───────────────────────────────────────────────────────

  /// Build the primary gauge from config.
  Widget? buildGauge({double size = 200}) {
    final gc = config.dashboard.gauge;
    if (gc == null) return null;

    final reg = config.registerByKey(gc.registerKey);
    if (reg == null) return null;

    return GaugeWidget(
      label: reg.label,
      value: _liveValue(reg),
      unit: reg.unit,
      max: gc.max,
      warningThreshold: gc.warningThreshold,
      dangerThreshold: gc.dangerThreshold,
      size: size,
    );
  }

  // ── Stat Cards ────────────────────────────────────────────────────

  /// Build all stat cards defined in the config.
  List<Widget> buildStatCards() {
    return config.dashboard.statCards.map((key) {
      final reg = config.registerByKey(key);
      if (reg == null) return const SizedBox.shrink();

      return SizedBox(
        width: 190,
        height: 80,
        child: StatCard(
          label: reg.label,
          value: _liveValue(reg),
          unit: reg.unit,
          sparklineData: _historyValues(reg.address),
          accentColor: reg.color,
        ),
      );
    }).toList();
  }

  // ── Charts ────────────────────────────────────────────────────────

  /// Build all chart widgets defined in config.
  List<Widget> buildCharts() {
    return config.dashboard.charts.map((key) {
      final reg = config.registerByKey(key);
      if (reg == null) return const SizedBox.shrink();

      return Expanded(
        child: LiveLineChart(
          title: reg.label,
          values: _historyValues(reg.address),
          lineColor: reg.color,
          unit: reg.unit,
        ),
      );
    }).toList();
  }

  /// Build charts for narrow (stacked) layout.
  List<Widget> buildChartsNarrow({double height = 200}) {
    return config.dashboard.charts.map((key) {
      final reg = config.registerByKey(key);
      if (reg == null) return const SizedBox.shrink();

      return LiveLineChart(
        title: reg.label,
        values: _historyValues(reg.address),
        lineColor: reg.color,
        unit: reg.unit,
        height: height,
      );
    }).toList();
  }

  // ── Helpers ───────────────────────────────────────────────────────

  double _liveValue(RegisterConfig reg) {
    final raw = store.liveValues[reg.address] ?? 0;
    return reg.applyDivisor(raw);
  }

  List<double> _historyValues(int register) {
    final list = store.registerHistory[register];
    if (list == null || list.isEmpty) return [];
    return list.map((d) => d.value).toList();
  }
}
