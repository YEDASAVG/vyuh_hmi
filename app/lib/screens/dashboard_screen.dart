import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';

import '../config/dashboard_config.dart';
import '../config/hmi_theme_engine.dart';
import '../config/widget_registry.dart';
import '../models/plc_data.dart';
import '../stores/dashboard_store.dart';
import '../widgets/alarm_banner_widget.dart';
import '../widgets/batch_state_widget.dart';
import '../widgets/connection_status_bar.dart';
import '../widgets/control_toggle_widget.dart';

class DashboardScreen extends StatelessWidget {
  final DashboardStore store;
  final DashboardConfig config;

  const DashboardScreen({
    super.key,
    required this.store,
    required this.config,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ActiveTheme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        return Observer(
          builder: (_) {
            final isWide = constraints.maxWidth > 700;
            return Column(
              children: [
                ConnectionStatusBar(
                  isServerConnected: store.isServerConnected,
                  isWsConnected: store.isWsConnected,
                ),
                AlarmBanner(
                  alarms: store.activeAlarms.toList(),
                  onDismiss: store.dismissAlarm,
                ),
                Expanded(
                  child: isWide
                      ? _wideLayout(constraints, colors)
                      : _narrowLayout(colors),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Widget _wideLayout(BoxConstraints constraints, ThemeConfig colors) {
    final registry = WidgetRegistry(config: config, store: store);
    const designWidth = 900.0;
    const maxScale = 1.3;
    final availableWidth = constraints.maxWidth - 40;
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
                            registry.buildGauge(size: 200) ??
                                const SizedBox.shrink(),
                            const SizedBox(height: 16),
                            if (config.dashboard.batchState != null)
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
                          children: registry.buildStatCards(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 20),
                  // ── Control Panel ──
                  if (config.dashboard.controls != null)
                    _buildControlPanel(colors),
                  if (config.dashboard.controls != null)
                    const SizedBox(height: 20),
                  // ── Charts row ──
                  SizedBox(
                    height: 220,
                    child: Row(
                      children: _interleave(
                        registry.buildCharts(),
                        const SizedBox(width: 12),
                      ),
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

  Widget _narrowLayout(ThemeConfig colors) {
    final registry = WidgetRegistry(config: config, store: store);

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Center(
          child: registry.buildGauge(size: 180) ?? const SizedBox.shrink(),
        ),
        const SizedBox(height: 16),
        if (config.dashboard.batchState != null)
          BatchStateWidget(
            state: store.batchState,
            progress: store.batchProgress,
          ),
        const SizedBox(height: 16),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: registry.buildStatCards(),
        ),
        const SizedBox(height: 16),
        if (config.dashboard.controls != null) _buildControlPanel(colors),
        const SizedBox(height: 16),
        ...registry
            .buildChartsNarrow()
            .expand((w) => [w, const SizedBox(height: 12)]),
      ],
    );
  }

  // ── Control Panel (config-driven) ────────────────────────────────

  Widget _buildControlPanel(ThemeConfig colors) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(Icons.tune_rounded, color: colors.accent, size: 18),
              const SizedBox(width: 8),
              Text(
                'OPERATOR CONTROLS',
                style: TextStyle(
                  color: colors.textSecondary,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'DM Mono',
                  letterSpacing: 1.5,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Wrap(
            spacing: 12,
            runSpacing: 12,
            children: [
              if (config.dashboard.controls?.agitator != null)
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
              if (config.dashboard.controls?.emergencyStop != null)
                SizedBox(
                  width: 220,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      EmergencyStopButton(
                        isLoading: store.isWriting,
                        onPressed: () => store.emergencyStop(),
                      ),
                      const SizedBox(height: 8),
                      _RestartBatchButton(
                        isLoading: store.isWriting,
                        isIdle: store.batchState == BatchState.idle,
                        onPressed: () => store.restartBatch(),
                      ),
                      if (store.lastWriteError != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          store.lastWriteError!,
                          style: TextStyle(
                            color: colors.danger,
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

  /// Insert separator widgets between items.
  List<Widget> _interleave(List<Widget> items, Widget separator) {
    if (items.isEmpty) return items;
    final result = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      if (i > 0) result.add(separator);
      result.add(items[i]);
    }
    return result;
  }
}

/// Restart Batch button — appears when batch is IDLE (after emergency stop).
class _RestartBatchButton extends StatelessWidget {
  final bool isLoading;
  final bool isIdle;
  final VoidCallback onPressed;

  const _RestartBatchButton({
    required this.isLoading,
    required this.isIdle,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final colors = ActiveTheme.of(context);

    return AnimatedOpacity(
      opacity: isIdle ? 1.0 : 0.4,
      duration: const Duration(milliseconds: 200),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: (isLoading || !isIdle) ? null : () => _confirmRestart(context),
          borderRadius: BorderRadius.circular(12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: colors.healthy.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: colors.healthy.withValues(alpha: 0.5), width: 1.5),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (isLoading)
                  SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: colors.healthy,
                    ),
                  )
                else
                  Icon(Icons.play_arrow_rounded,
                      color: colors.healthy, size: 20),
                const SizedBox(width: 8),
                Text(
                  'RESTART BATCH',
                  style: TextStyle(
                    color: colors.healthy,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'DM Mono',
                    letterSpacing: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _confirmRestart(BuildContext context) async {
    final colors = ActiveTheme.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(Icons.play_arrow_rounded, color: colors.healthy, size: 28),
            const SizedBox(width: 8),
            Text(
              'RESTART BATCH',
              style: TextStyle(
                color: colors.healthy,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: Text(
          'This will clear the emergency stop and allow the batch process to resume from IDLE.\n\n'
          'The reactor will begin a new heating cycle.',
          style: TextStyle(color: colors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('CANCEL',
                style: TextStyle(color: colors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: colors.healthy,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('CONFIRM RESTART'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      onPressed();
    }
  }
}
