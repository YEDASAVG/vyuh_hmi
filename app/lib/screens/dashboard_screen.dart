import 'package:flutter/material.dart';
import 'package:flutter_mobx/flutter_mobx.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/dashboard_config.dart';
import '../config/hmi_theme_engine.dart';
import '../config/widget_registry.dart';
import '../models/plc_data.dart';
import '../services/auth_service.dart';
import '../stores/dashboard_store.dart';
import '../widgets/batch_state_widget.dart';
import '../widgets/alarm_banner_widget.dart';
import '../widgets/control_toggle_widget.dart';
import '../widgets/esig_dialog.dart';
import '../widgets/persistent_alarm_panel.dart';

class DashboardScreen extends StatelessWidget {
  final DashboardStore store;
  final DashboardConfig config;
  /// User role — controls are hidden for 'viewer'.
  final String userRole;
  /// Auth service for e-signature verification on critical writes.
  final AuthService? authService;
  /// Navigate to the Devices tab to add/discover PLCs.
  final VoidCallback? onNavigateToDevices;

  const DashboardScreen({
    super.key,
    required this.store,
    required this.config,
    this.userRole = 'viewer',
    this.authService,
    this.onNavigateToDevices,
  });

  bool get _canControl => userRole == 'admin' || userRole == 'operator';

  @override
  Widget build(BuildContext context) {
    final colors = ActiveTheme.of(context);

    return LayoutBuilder(
      builder: (context, constraints) {
        return Observer(
          builder: (_) {
            return Column(
              children: [
                // ── Vyuh Branding Bar ──
                _BrandingBar(
                  store: store,
                  colors: colors,
                  isServerConnected: store.isServerConnected,
                  isWsConnected: store.isWsConnected,
                  alarms: store.activeAlarms.toList(),
                  onAddDevice: onNavigateToDevices,
                ),
                Expanded(
                  child: Stack(
                    children: [
                      _hmiLayout(context, constraints, colors),
                      // OFFLINE overlay
                      if (store.activeDevice?.isConnected == false)
                        _OfflineBanner(
                          deviceName: store.activeDevice!.name,
                          onReconnect: onNavigateToDevices,
                          colors: colors,
                        ),
                    ],
                  ),
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// HMI 2-column layout designed for 2K factory displays.
  ///
  /// Follows ISA-101 High-Performance HMI guidelines:
  /// - Left column: Gauges + Stat Cards + Charts (monitoring)
  /// - Right column: Controls + Persistent Alarm Panel (action)
  Widget _hmiLayout(BuildContext context, BoxConstraints constraints, ThemeConfig colors) {
    final registry = WidgetRegistry(config: config, store: store);
    final w = constraints.maxWidth;
    final gaugeSize = w >= 1600 ? 380.0 : w >= 1200 ? 340.0 : 300.0;

    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ════════════════════════════════════════════
          // LEFT COLUMN — Monitoring (Gauges, Cards, Charts)
          // ════════════════════════════════════════════
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.only(right: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Top Row: Gauge + Stat Cards grid ──
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Gauge column
                      SizedBox(
                        width: gaugeSize + 40,
                        child: registry.buildGauge(size: gaugeSize) ??
                            const SizedBox.shrink(),
                      ),
                      const SizedBox(width: 12),
                      // Stat Cards — 2-column grid + Batch Reactor below
                      Expanded(
                        child: Column(
                          children: [
                            _StatCardGrid(cards: registry.buildStatCards()),
                            if (config.dashboard.batchState != null) ...[
                              const SizedBox(height: 12),
                              BatchStateWidget(
                                state: store.batchState,
                                progress: store.batchProgress,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  // ── Charts Row — fills remaining vertical space ──
                  Expanded(
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
          // ════════════════════════════════════════════
          // RIGHT COLUMN — Controls + Persistent Alarms (2-col grid)
          // ════════════════════════════════════════════
          Expanded(
            flex: 1,
            child: Padding(
              padding: const EdgeInsets.only(left: 12),
              child: _buildControlGrid(context, colors),
            ),
          ),
        ],
      ),
    );
  }

  // ── Control Grid (2-column layout matching wireframe) ─────────────

  Widget _buildControlGrid(BuildContext ctx, ThemeConfig colors) {
    final controlWidgets = <Widget>[];

    if (_canControl && config.dashboard.controls != null) {
      // Agitator speed
      if (config.dashboard.controls?.agitator != null) {
        controlWidgets.add(AgitatorSliderWidget(
          currentRpm: store.agitatorSpeed,
          isOverridden: store.agitatorOverrideActive,
          isLoading: store.isWriting,
          onSetRpm: (rpm) => store.setAgitatorRpm(rpm),
          onClearOverride: () => store.clearAgitatorOverride(),
        ));
      }

      // Setpoint sliders — each as its own card
      for (final sp in config.dashboard.controls?.setpoints ?? []) {
        controlWidgets.add(_SetpointSlider(
          config: sp,
          currentValue: store.liveValues[sp.register] ?? 0,
          isLoading: store.isWriting,
          colors: colors,
          onSet: (value) =>
              store.writeRegister(register: sp.register, value: value),
          onClear: () =>
              store.writeRegister(register: sp.register, value: 0),
        ));
      }

      // Emergency stop + restart — side by side, same size
      if (config.dashboard.controls?.emergencyStop != null) {
        controlWidgets.add(IntrinsicHeight(
          child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: EmergencyStopButton(
                isLoading: store.isWriting,
                onPressed: () => _withEsig(
                  ctx,
                  'Emergency Stop — Force Batch to IDLE',
                  () => store.emergencyStop(),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _RestartBatchButton(
                isLoading: store.isWriting,
                isIdle: store.batchState == BatchState.idle,
                onPressed: () => store.restartBatch(),
              ),
            ),
          ],
        )));
        if (store.lastWriteError != null) {
          controlWidgets.add(Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              store.lastWriteError!,
              style: TextStyle(
                color: colors.danger,
                fontSize: 16,
                fontFamily: 'DM Mono',
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ));
        }
      }
    }

    // Persistent alarm panel is first item in right column of row 1
    final alarmPanel = PersistentAlarmPanel(
      alarms: store.activeAlarms.toList(),
      onDismiss: store.dismissAlarm,
    );

    // Build 2-column grid: top-right = alarms, rest = controls
    final rows = <Widget>[];
    // Row 1: first control | alarms
    rows.add(Expanded(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: controlWidgets.isNotEmpty
                ? controlWidgets[0]
                : const SizedBox.shrink(),
          ),
          const SizedBox(width: 12),
          Expanded(child: alarmPanel),
        ],
      ),
    ));

    // Remaining controls in pairs
    for (var i = 1; i < controlWidgets.length; i += 2) {
      final hasSecond = i + 1 < controlWidgets.length;
      rows.add(const SizedBox(height: 12));
      rows.add(Expanded(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: controlWidgets[i]),
            const SizedBox(width: 12),
            if (hasSecond)
              Expanded(child: controlWidgets[i + 1])
            else
              const Expanded(child: SizedBox()),
          ],
        ),
      ));
    }

    return Column(children: rows);
  }

  /// Gate a critical action behind electronic signature verification.
  /// If no [authService] is provided, falls through directly (dev mode).
  Future<void> _withEsig(
    BuildContext context,
    String action,
    Future<bool> Function() execute,
  ) async {
    if (authService != null) {
      final verified = await ESignatureDialog.show(
        context,
        authService: authService!,
        action: action,
      );
      if (!verified) return; // user cancelled or failed
    }
    await execute();
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
  final Future<void> Function() onPressed;

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
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 24),
            decoration: BoxDecoration(
              color: colors.healthy.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: colors.healthy.withValues(alpha: 0.5), width: 2),
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (isLoading)
                  SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: colors.healthy,
                    ),
                  )
                else
                  Icon(Icons.play_arrow_rounded,
                      color: colors.healthy, size: 56),
                const SizedBox(height: 12),
                Text(
                  'RESTART\nBATCH',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: colors.healthy,
                    fontSize: 28,
                    fontWeight: FontWeight.w700,
                    fontFamily: 'DM Mono',
                    letterSpacing: 2,
                    height: 1.3,
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
                fontSize: 24,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: Text(
          'This will clear the emergency stop and allow the batch process to resume from IDLE.\n\n'
          'The reactor will begin a new heating cycle.',
          style: TextStyle(color: colors.textSecondary, fontSize: 18),
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
      await onPressed();
    }
  }
}

// ── Setpoint Slider Widget ──────────────────────────────────────────

class _SetpointSlider extends StatefulWidget {
  final SetpointConfig config;
  final double currentValue;
  final bool isLoading;
  final ThemeConfig colors;
  final Future<void> Function(int value) onSet;
  final Future<void> Function() onClear;

  const _SetpointSlider({
    required this.config,
    required this.currentValue,
    required this.isLoading,
    required this.colors,
    required this.onSet,
    required this.onClear,
  });

  @override
  State<_SetpointSlider> createState() => _SetpointSliderState();
}

class _SetpointSliderState extends State<_SetpointSlider> {
  double _pending = 0;
  bool _isDragging = false;

  @override
  void initState() {
    super.initState();
    _pending = widget.currentValue.clamp(
      widget.config.min.toDouble(),
      widget.config.max.toDouble(),
    );
  }

  @override
  void didUpdateWidget(covariant _SetpointSlider oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isDragging && oldWidget.currentValue != widget.currentValue) {
      _pending = widget.currentValue.clamp(
        widget.config.min.toDouble(),
        widget.config.max.toDouble(),
      );
    }
  }

  String _displayValue(double raw) {
    if (widget.config.divisor > 1) {
      return (raw / widget.config.divisor).toStringAsFixed(1);
    }
    return raw.toInt().toString();
  }

  @override
  Widget build(BuildContext context) {
    final sp = widget.config;
    final colors = widget.colors;
    final current = _displayValue(widget.currentValue);
    final pending = _displayValue(_pending);

    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.surfaceBorder, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.tune_rounded, size: 26, color: colors.accent),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  sp.label,
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 26,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              Text(
                'NOW: $current ${sp.unit}',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 22,
                  fontFamily: 'DM Mono',
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              Text(
                _displayValue(sp.min.toDouble()),
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 18,
                  fontFamily: 'DM Mono',
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: colors.accent,
                    inactiveTrackColor: colors.surfaceBorder,
                    thumbColor: colors.accent,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 16),
                    trackHeight: 10,
                  ),
                  child: Slider(
                    value: _pending,
                    min: sp.min.toDouble(),
                    max: sp.max.toDouble(),
                    divisions: ((sp.max - sp.min) / sp.step).round(),
                    onChangeStart: (_) => setState(() => _isDragging = true),
                    onChanged: (v) => setState(() => _pending = v),
                    onChangeEnd: (_) => setState(() => _isDragging = false),
                  ),
                ),
              ),
              Text(
                _displayValue(sp.max.toDouble()),
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 18,
                  fontFamily: 'DM Mono',
                ),
              ),
            ],
          ),
          const Spacer(),
          Row(
            children: [
              Text(
                'SET: $pending ${sp.unit}',
                style: TextStyle(
                  color: colors.accent,
                  fontSize: 32,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'DM Mono',
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 46,
                child: TextButton(
                  onPressed: widget.isLoading ? null : () => widget.onClear(),
                  style: TextButton.styleFrom(
                    foregroundColor: Colors.white54,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                  ),
                  child: const Text('AUTO', style: TextStyle(fontSize: 22, fontFamily: 'DM Mono', fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(width: 6),
              SizedBox(
                height: 46,
                child: FilledButton(
                  onPressed: widget.isLoading ? null : () => widget.onSet(_pending.round()),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 20),
                  ),
                  child: widget.isLoading
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.textPrimary,
                          ),
                        )
                      : const Text('APPLY', style: TextStyle(fontSize: 22, fontFamily: 'DM Mono', fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _DeviceChip extends StatelessWidget {
  final String label;
  final String sublabel;
  final bool isActive;
  final bool isConnected;
  final Color accentColor;
  final VoidCallback onTap;

  const _DeviceChip({
    required this.label,
    required this.sublabel,
    required this.isActive,
    required this.isConnected,
    required this.accentColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: isActive
                ? accentColor.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isActive
                  ? accentColor.withValues(alpha: 0.5)
                  : Colors.white10,
              width: isActive ? 2 : 1,
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
                  color: isConnected ? const Color(0xFF66BB6A) : Colors.red,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 15,
                  fontWeight: isActive ? FontWeight.w600 : FontWeight.w400,
                  color: isActive ? accentColor : Colors.white70,
                ),
              ),
              if (!isConnected) ...[
                const SizedBox(width: 5),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(3),
                    border: Border.all(color: Colors.red.withValues(alpha: 0.5), width: 1),
                  ),
                  child: const Text(
                    'OFFLINE',
                    style: TextStyle(
                      color: Colors.red,
                      fontSize: 9,
                      fontFamily: 'DM Mono',
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1,
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

// ── 2-Column Stat Card Grid (HMI layout) ────────────────────────────────────

class _StatCardGrid extends StatelessWidget {
  final List<Widget> cards;
  const _StatCardGrid({required this.cards});

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < cards.length; i += 2) {
      final hasSecond = i + 1 < cards.length;
      rows.add(Row(
        children: [
          Expanded(child: cards[i]),
          const SizedBox(width: 12),
          if (hasSecond) Expanded(child: cards[i + 1])
          else const Expanded(child: SizedBox()),
        ],
      ));
      if (i + 2 < cards.length) rows.add(const SizedBox(height: 12));
    }
    return Column(children: rows);
  }
}

// ── Vyuh HMI Branding Bar ─────────────────────────────────────────────────────

class _BrandingBar extends StatelessWidget {
  final DashboardStore store;
  final ThemeConfig colors;
  final bool isServerConnected;
  final bool isWsConnected;
  final List<Alarm> alarms;
  final VoidCallback? onAddDevice;

  const _BrandingBar({
    required this.store,
    required this.colors,
    required this.isServerConnected,
    required this.isWsConnected,
    required this.alarms,
    this.onAddDevice,
  });

  @override
  Widget build(BuildContext context) {
    final allGood = isServerConnected && isWsConnected;
    final devices = store.devices;
    final activeId = store.activeDeviceId;
    final active = store.activeDevice;
    final critCount =
        alarms.where((a) => a.severity == AlarmSeverity.critical).length;
    final warnCount =
        alarms.where((a) => a.severity == AlarmSeverity.warning).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          bottom: BorderSide(color: colors.surfaceBorder, width: 1.5),
        ),
      ),
      child: Row(
        children: [
          // ── Vyuh Logo / Branding ──
          Icon(Icons.precision_manufacturing_rounded,
              color: colors.accent, size: 28),
          const SizedBox(width: 12),
          Text(
            'VYUH',
            style: GoogleFonts.dmMono(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: colors.accent,
              letterSpacing: 4,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'HMI',
            style: GoogleFonts.outfit(
              fontSize: 24,
              fontWeight: FontWeight.w400,
              color: colors.textMuted,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(width: 32),
          // ── Device Switcher (inline) ──
          if (devices.isNotEmpty) ...[
            Container(width: 1, height: 24, color: colors.surfaceBorder),
            const SizedBox(width: 16),
            Icon(Icons.memory_rounded, size: 20, color: colors.textMuted),
            const SizedBox(width: 8),
            ...devices.map((dev) {
              final isActive = dev.id == activeId;
              final protocolColor = dev.protocol == 'opcua'
                  ? const Color(0xFF26A69A)
                  : const Color(0xFF42A5F5);
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: _DeviceChip(
                  label: dev.name,
                  sublabel: dev.protocol.toUpperCase(),
                  isActive: isActive,
                  isConnected: dev.isConnected,
                  accentColor: isActive ? colors.accent : protocolColor,
                  onTap: () => store.switchDevice(dev.id),
                ),
              );
            }),
            if (onAddDevice != null)
              IconButton(
                icon: Icon(Icons.add_circle_outline_rounded,
                    size: 22, color: colors.accent),
                tooltip: 'Add / Discover PLCs',
                onPressed: onAddDevice,
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
              ),
          ] else ...[
            Container(width: 1, height: 24, color: colors.surfaceBorder),
            const SizedBox(width: 16),
            Icon(Icons.memory_rounded, size: 20, color: colors.accent),
            const SizedBox(width: 8),
            Text(
              'Device: $activeId',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: colors.accent,
              ),
            ),
          ],
          const Spacer(),
          // ── Alarm Counts ──
          if (critCount > 0)
            _statusBadge(critCount, 'CRIT', colors.danger),
          if (critCount > 0 && warnCount > 0)
            const SizedBox(width: 8),
          if (warnCount > 0)
            _statusBadge(warnCount, 'WARN', colors.warning),
          if (critCount > 0 || warnCount > 0)
            const SizedBox(width: 16),
          // ── Connection Status ──
          Container(width: 1, height: 24, color: colors.surfaceBorder),
          const SizedBox(width: 16),
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: allGood ? colors.healthy : colors.danger,
              boxShadow: [
                BoxShadow(
                  color: (allGood ? colors.healthy : colors.danger)
                      .withValues(alpha: 0.5),
                  blurRadius: 6,
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          Text(
            allGood ? 'ONLINE' : 'OFFLINE',
            style: GoogleFonts.dmMono(
              fontSize: 17,
              fontWeight: FontWeight.w600,
              color: allGood ? colors.healthy : colors.danger,
              letterSpacing: 1.5,
            ),
          ),
          // ── Protocol badge ──
          if (active != null) ...[
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: (active.protocol == 'opcua'
                        ? const Color(0xFF26A69A)
                        : const Color(0xFF42A5F5))
                    .withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                active.protocol.toUpperCase(),
                style: GoogleFonts.jetBrainsMono(
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                  color: active.protocol == 'opcua'
                      ? const Color(0xFF26A69A)
                      : const Color(0xFF42A5F5),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _statusBadge(int count, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$count',
            style: GoogleFonts.dmMono(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: color,
            ),
          ),
          const SizedBox(width: 4),
          Text(
            label,
            style: GoogleFonts.dmMono(
              fontSize: 15,
              fontWeight: FontWeight.w600,
              color: color.withValues(alpha: 0.7),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Offline Overlay ───────────────────────────────────────────────────────────

class _OfflineBanner extends StatelessWidget {
  final String deviceName;
  final VoidCallback? onReconnect;
  final ThemeConfig colors;

  const _OfflineBanner({
    required this.deviceName,
    required this.colors,
    this.onReconnect,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black.withValues(alpha: 0.72),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Colors.red.withValues(alpha: 0.15),
                border: Border.all(color: Colors.red.withValues(alpha: 0.5), width: 2),
              ),
              child: const Icon(Icons.link_off_rounded, color: Colors.red, size: 34),
            ),
            const SizedBox(height: 20),
            Text(
              deviceName.toUpperCase(),
              style: GoogleFonts.jetBrainsMono(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                color: Colors.red.withValues(alpha: 0.8),
                letterSpacing: 2,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'DEVICE OFFLINE',
              style: GoogleFonts.outfit(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 1,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Live data is paused. Last known values are shown.',
              style: GoogleFonts.outfit(
                fontSize: 17,
                color: Colors.white54,
              ),
            ),
            const SizedBox(height: 28),
            if (onReconnect != null)
              FilledButton.icon(
                onPressed: onReconnect,
                style: FilledButton.styleFrom(
                  backgroundColor: colors.accent,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
                icon: const Icon(Icons.link_rounded, size: 18),
                label: Text(
                  'GO TO DEVICES',
                  style: GoogleFonts.outfit(
                    fontSize: 17,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
