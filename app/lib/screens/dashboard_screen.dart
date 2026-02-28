import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import '../stores/dashboard_store.dart';
import '../theme/hmi_colors.dart';
import '../widgets/batch_state_widget.dart';
import '../widgets/connection_status_bar.dart';
import '../widgets/gauge_widget.dart';
import '../widgets/line_chart_widget.dart';
import '../widgets/stat_card.dart';

class DashboardScreen extends StatelessWidget {
  final DashboardStore store;
  const DashboardScreen({super.key, required this.store});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Observer INSIDE LayoutBuilder so MobX tracks all reads.
        return Observer(
          builder: (_) {
            final isWide = constraints.maxWidth > 700;
            return Column(
              children: [
                ConnectionStatusBar(
                  isServerConnected: store.isServerConnected,
                  isWsConnected: store.isWsConnected,
                ),
                Expanded(
                  child: isWide
                      ? _wideLayout(constraints)
                      : _narrowLayout(),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _wideLayout(BoxConstraints constraints) {
    final scale = constraints.maxWidth / 900;
    final clampedScale = scale.clamp(1.0, 1.5);

    return Transform.scale(
      scale: clampedScale,
      alignment: Alignment.topCenter,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 900),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Top row: Gauge + Batch | Stat Cards ──
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(
                    width: 240,
                    child: Column(
                      children: [
                        GaugeWidget(
                          label: 'Temperature',
                          value: store.temperature,
                          unit: '°C',
                          max: 120,
                          warningThreshold: 80,
                          dangerThreshold: 100,
                          size: 200,
                        ),
                        const SizedBox(height: 16),
                        BatchStateWidget(
                          state: store.batchState,
                          progress: store.batchProgress,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: _buildStatCards(),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              // ── Charts row ──
              SizedBox(
                height: 220,
                child: Row(
                  children: [
                    Expanded(
                      child: LiveLineChart(
                        title: 'Temperature',
                        values: _historyValues(1028),
                        lineColor: HmiColors.accent,
                        unit: '°C',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: LiveLineChart(
                        title: 'Pressure',
                        values: _historyValues(1029),
                        lineColor: HmiColors.info,
                        unit: 'mbar',
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: LiveLineChart(
                        title: 'Flow Rate',
                        values: _historyValues(1031),
                        lineColor: HmiColors.healthy,
                        unit: 'L/min',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
    );
  }

  Widget _narrowLayout() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: GaugeWidget(
            label: 'Temperature',
            value: store.temperature,
            unit: '°C',
            max: 120,
            warningThreshold: 80,
            dangerThreshold: 100,
            size: 180,
          ),
        ),
        const SizedBox(height: 16),
        BatchStateWidget(
          state: store.batchState,
          progress: store.batchProgress,
        ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: _buildStatCards(),
        ),
        const SizedBox(height: 16),
        LiveLineChart(
          title: 'Temperature',
          values: _historyValues(1028),
          lineColor: HmiColors.accent,
          unit: '°C',
          height: 200,
        ),
        const SizedBox(height: 12),
        LiveLineChart(
          title: 'Pressure',
          values: _historyValues(1029),
          lineColor: HmiColors.info,
          unit: 'mbar',
          height: 200,
        ),
        const SizedBox(height: 12),
        LiveLineChart(
          title: 'Flow Rate',
          values: _historyValues(1031),
          lineColor: HmiColors.healthy,
          unit: 'L/min',
          height: 200,
        ),
      ],
    );
  }

  List<Widget> _buildStatCards() {
    return [
      SizedBox(
        width: 190,
        height: 80,
        child: StatCard(
          label: 'Temperature',
          value: store.temperature,
          unit: '°C',
          sparklineData: _historyValues(1028),
          accentColor: HmiColors.accent,
        ),
      ),
      SizedBox(
        width: 190,
        height: 80,
        child: StatCard(
          label: 'Pressure',
          value: store.pressure,
          unit: 'mbar',
          sparklineData: _historyValues(1029),
          accentColor: HmiColors.info,
        ),
      ),
      SizedBox(
        width: 190,
        height: 80,
        child: StatCard(
          label: 'Humidity',
          value: store.humidity,
          unit: '%',
          sparklineData: _historyValues(1030),
          accentColor: Colors.cyan,
        ),
      ),
      SizedBox(
        width: 190,
        height: 80,
        child: StatCard(
          label: 'Flow Rate',
          value: store.flowRate,
          unit: 'L/min',
          sparklineData: _historyValues(1031),
          accentColor: HmiColors.healthy,
        ),
      ),
      SizedBox(
        width: 190,
        height: 80,
        child: StatCard(
          label: 'Agitator',
          value: store.agitatorSpeed,
          unit: 'RPM',
          sparklineData: _historyValues(1034),
          accentColor: HmiColors.warning,
        ),
      ),
      SizedBox(
        width: 190,
        height: 80,
        child: StatCard(
          label: 'pH Level',
          value: store.pH,
          unit: '',
          sparklineData: _historyValues(1035),
          accentColor: Colors.purple,
        ),
      ),
    ];
  }

  List<double> _historyValues(int register) {
    final list = store.registerHistory[register];
    if (list == null || list.isEmpty) return [];
    return list.map((d) => d.value).toList();
  }
}
