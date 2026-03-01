import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import '../stores/dashboard_store.dart';
import '../theme/hmi_colors.dart';
import '../widgets/alarm_banner_widget.dart';
import '../widgets/batch_state_widget.dart';
import '../widgets/connection_status_bar.dart';
import '../widgets/control_toggle_widget.dart';
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
                // Phase 4: Alarm banner
                AlarmBanner(
                  alarms: store.activeAlarms.toList(),
                  onDismiss: store.dismissAlarm,
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
    const designWidth = 900.0;
    const maxScale = 1.3;
    final availableWidth = constraints.maxWidth - 40; // account for padding
    final scale = (availableWidth / designWidth).clamp(0.8, maxScale);
    final containerWidth = designWidth * scale;

    return SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: SizedBox(
            width: containerWidth,
            child: FittedBox(
              fit: BoxFit.fitWidth,
              alignment: Alignment.topCenter,
              child: SizedBox(
                width: designWidth,
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
              // ── Phase 4: Control Panel ──
              _buildControlPanel(),
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
        // Phase 4: Controls
        _buildControlPanel(),
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

  // ── Phase 4: Control Panel ─────────────────────────────────────

  Widget _buildControlPanel() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HmiColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: HmiColors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          const Row(
            children: [
              Icon(Icons.tune_rounded, color: HmiColors.accent, size: 18),
              SizedBox(width: 8),
              Text(
                'OPERATOR CONTROLS',
                style: TextStyle(
                  color: HmiColors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'DM Mono',
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Emergency stop + Agitator slider side by side on wide, stacked on narrow
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              SizedBox(
                width: 300,
                child: AgitatorSliderWidget(
                  currentRpm: store.agitatorSpeed,
                  isOverridden: store.agitatorOverrideActive,
                  isLoading: store.isWriting,
                  onSetRpm: (rpm) => store.setAgitatorRpm(rpm),
                  onClearOverride: () => store.clearAgitatorOverride(),
                ),
              ),
              SizedBox(
                width: 220,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    EmergencyStopButton(
                      isLoading: store.isWriting,
                      onPressed: () => store.emergencyStop(),
                    ),
                    if (store.lastWriteError != null) ...[
                      const SizedBox(height: 8),
                      Text(
                        store.lastWriteError!,
                        style: const TextStyle(
                          color: HmiColors.danger,
                          fontSize: 10,
                          fontFamily: 'DM Mono',
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ),
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
