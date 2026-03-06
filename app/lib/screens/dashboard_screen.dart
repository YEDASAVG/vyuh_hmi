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
import '../widgets/connection_status_bar.dart';
import '../widgets/control_toggle_widget.dart';
import '../widgets/esig_dialog.dart';

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
            final isWide = constraints.maxWidth > 700;
            return Column(
              children: [
                ConnectionStatusBar(
                  isServerConnected: store.isServerConnected,
                  isWsConnected: store.isWsConnected,
                  alarms: store.activeAlarms.toList(),
                ),
                _DeviceSwitcherBar(
                  store: store,
                  colors: colors,
                  onAddDevice: onNavigateToDevices,
                ),
                Expanded(
                  child: Stack(
                    children: [
                      isWide
                          ? _wideLayout(constraints, colors)
                          : _narrowLayout(colors),
                      // OFFLINE overlay — shown when the active device is disconnected.
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
                  // ── Control Panel (operator / admin only) ──
                  if (_canControl && config.dashboard.controls != null)
                    _buildControlPanel(colors),
                  if (_canControl && config.dashboard.controls != null)
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
        if (_canControl && config.dashboard.controls != null) _buildControlPanel(colors),
        const SizedBox(height: 16),
        ...registry
            .buildChartsNarrow()
            .expand((w) => [w, const SizedBox(height: 12)]),
      ],
    );
  }

  // ── Control Panel (config-driven) ────────────────────────────────

  Widget _buildControlPanel(ThemeConfig colors) {
    return Builder(
      builder: (context) => Container(
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
                    onSetRpm: (rpm) => _withEsig(
                      context,
                      'Set Agitator RPM to $rpm',
                      () => store.setAgitatorRpm(rpm),
                    ),
                    onClearOverride: () => _withEsig(
                      context,
                      'Clear Agitator Override',
                      () => store.clearAgitatorOverride(),
                    ),
                  ),
                ),
              // ── Setpoint Controls (config-driven) ──
              for (final sp in config.dashboard.controls?.setpoints ?? [])
                SizedBox(
                  width: 300,
                  child: _SetpointSlider(
                    config: sp,
                    currentValue: store.liveValues[sp.register] ?? 0,
                    isLoading: store.isWriting,
                    colors: colors,
                    onSet: (value) => _withEsig(
                      context,
                      'Set ${sp.label} to ${sp.divisor > 1 ? (value / sp.divisor).toStringAsFixed(1) : value.toString()} ${sp.unit}',
                      () => store.writeRegister(register: sp.register, value: value),
                    ),
                    onClear: () => _withEsig(
                      context,
                      'Clear ${sp.label} override',
                      () => store.writeRegister(register: sp.register, value: 0),
                    ),
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
                        onPressed: () => _withEsig(
                          context,
                          'Emergency Stop — Force Batch to IDLE',
                          () => store.emergencyStop(),
                        ),
                      ),
                      const SizedBox(height: 8),
                      _RestartBatchButton(
                        isLoading: store.isWriting,
                        isIdle: store.batchState == BatchState.idle,
                        onPressed: () => _withEsig(
                          context,
                          'Restart Batch',
                          () => store.restartBatch(),
                        ),
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
    ),
    );
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
      padding: const EdgeInsets.all(14),
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
              Icon(Icons.tune_rounded, size: 16, color: colors.accent),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  sp.label,
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              Text(
                'NOW: $current ${sp.unit}',
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 10,
                  fontFamily: 'DM Mono',
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Text(
                _displayValue(sp.min.toDouble()),
                style: TextStyle(
                  color: colors.textMuted,
                  fontSize: 10,
                  fontFamily: 'DM Mono',
                ),
              ),
              Expanded(
                child: SliderTheme(
                  data: SliderThemeData(
                    activeTrackColor: colors.accent,
                    inactiveTrackColor: colors.surfaceBorder,
                    thumbColor: colors.accent,
                    thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
                    trackHeight: 4,
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
                  color: colors.textMuted,
                  fontSize: 10,
                  fontFamily: 'DM Mono',
                ),
              ),
            ],
          ),
          Row(
            children: [
              Text(
                'SET: $pending ${sp.unit}',
                style: TextStyle(
                  color: colors.accent,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  fontFamily: 'DM Mono',
                ),
              ),
              const Spacer(),
              SizedBox(
                height: 30,
                child: TextButton(
                  onPressed: widget.isLoading ? null : () => widget.onClear(),
                  style: TextButton.styleFrom(
                    foregroundColor: colors.textMuted,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                  child: const Text('AUTO', style: TextStyle(fontSize: 10, fontFamily: 'DM Mono')),
                ),
              ),
              const SizedBox(width: 4),
              SizedBox(
                height: 30,
                child: FilledButton(
                  onPressed: widget.isLoading ? null : () => widget.onSet(_pending.round()),
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                  ),
                  child: widget.isLoading
                      ? SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: colors.textPrimary,
                          ),
                        )
                      : const Text('APPLY', style: TextStyle(fontSize: 10, fontFamily: 'DM Mono', fontWeight: FontWeight.w700)),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

// ── Device Switcher Bar ──────────────────────────────────────────────

class _DeviceSwitcherBar extends StatelessWidget {
  final DashboardStore store;
  final ThemeConfig colors;
  final VoidCallback? onAddDevice;

  const _DeviceSwitcherBar({required this.store, required this.colors, this.onAddDevice});

  @override
  Widget build(BuildContext context) {
    return Observer(
      builder: (_) {
        final devices = store.devices;
        final active = store.activeDevice;
        final activeId = store.activeDeviceId;

        if (devices.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: colors.surface,
            child: Row(
              children: [
                Icon(Icons.memory_rounded, size: 16, color: colors.accent),
                const SizedBox(width: 8),
                Text(
                  'Device: $activeId',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: colors.accent,
                  ),
                ),
              ],
            ),
          );
        }

        return Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(
              bottom: BorderSide(color: colors.surfaceBorder, width: 1),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.memory_rounded, size: 16, color: colors.accent),
              const SizedBox(width: 8),
              Text(
                'DEVICE',
                style: GoogleFonts.outfit(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.2,
                  color: colors.textMuted,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: devices.map((dev) {
                      final isActive = dev.id == activeId;
                      final protocolColor = dev.protocol == 'opcua'
                          ? const Color(0xFF26A69A)
                          : const Color(0xFF42A5F5);
                      return Padding(
                        padding: const EdgeInsets.only(right: 6),
                        child: _DeviceChip(
                          label: dev.name,
                          sublabel: dev.protocol.toUpperCase(),
                          isActive: isActive,
                          isConnected: dev.isConnected,
                          accentColor: isActive ? colors.accent : protocolColor,
                          onTap: () => store.switchDevice(dev.id),
                        ),
                      );
                    }).toList(),
                  ),
                ),
              ),
              if (onAddDevice != null)
                IconButton(
                  icon: Icon(Icons.add_circle_outline_rounded,
                      size: 20, color: colors.accent),
                  tooltip: 'Add / Discover PLCs',
                  onPressed: onAddDevice,
                  constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                  padding: EdgeInsets.zero,
                ),
              if (active != null) ...[
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: (active.protocol == 'opcua'
                            ? const Color(0xFF26A69A)
                            : const Color(0xFF42A5F5))
                        .withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    active.protocol.toUpperCase(),
                    style: GoogleFonts.jetBrainsMono(
                      fontSize: 10,
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
      },
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: isActive
                ? accentColor.withValues(alpha: 0.15)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            border: Border.all(
              color: isActive
                  ? accentColor.withValues(alpha: 0.5)
                  : Colors.white10,
              width: isActive ? 1.5 : 1,
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
                  color: isConnected ? const Color(0xFF66BB6A) : Colors.red,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                label,
                style: GoogleFonts.outfit(
                  fontSize: 12,
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
                fontSize: 12,
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
                fontSize: 13,
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
                    fontSize: 13,
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
