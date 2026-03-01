import 'package:flutter/material.dart';

import '../theme/hmi_colors.dart';

/// Industrial toggle/valve control widget with confirmation dialog.
///
/// Used for bidirectional PLC control (Phase 4):
///   - Agitator ON/OFF toggle with RPM slider
///   - Emergency stop button (force batch to IDLE)
///
/// Displays current state, animates transitions, and requires
/// operator confirmation before sending write commands to the server.
class ControlToggleWidget extends StatelessWidget {
  final String label;
  final String description;
  final bool isActive;
  final bool isLoading;
  final IconData activeIcon;
  final IconData inactiveIcon;
  final Future<void> Function(bool newState) onToggle;

  const ControlToggleWidget({
    super.key,
    required this.label,
    required this.description,
    required this.isActive,
    required this.onToggle,
    this.isLoading = false,
    this.activeIcon = Icons.power_settings_new_rounded,
    this.inactiveIcon = Icons.power_off_rounded,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HmiColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isActive ? HmiColors.healthy.withValues(alpha: 0.4) : HmiColors.surfaceBorder,
          width: 1.5,
        ),
      ),
      child: Row(
        children: [
          // Status indicator dot
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: isActive ? HmiColors.healthy : HmiColors.textMuted,
              boxShadow: isActive
                  ? [
                      BoxShadow(
                        color: HmiColors.healthy.withValues(alpha: 0.5),
                        blurRadius: 8,
                        spreadRadius: 1,
                      )
                    ]
                  : null,
            ),
          ),
          const SizedBox(width: 12),
          // Label + description
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: HmiColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  isActive ? 'ACTIVE' : 'OFF',
                  style: TextStyle(
                    color: isActive ? HmiColors.healthy : HmiColors.textMuted,
                    fontSize: 11,
                    fontWeight: FontWeight.w500,
                    fontFamily: 'DM Mono',
                    letterSpacing: 1.2,
                  ),
                ),
              ],
            ),
          ),
          // Toggle switch
          if (isLoading)
            const SizedBox(
              width: 24,
              height: 24,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: HmiColors.accent,
              ),
            )
          else
            _IndustrialSwitch(
              value: isActive,
              onChanged: (newValue) => _confirmAndToggle(context, newValue),
            ),
        ],
      ),
    );
  }

  Future<void> _confirmAndToggle(BuildContext context, bool newValue) async {
    final action = newValue ? 'ACTIVATE' : 'DEACTIVATE';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HmiColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: Row(
          children: [
            Icon(
              Icons.warning_amber_rounded,
              color: HmiColors.warning,
              size: 24,
            ),
            const SizedBox(width: 8),
            Text(
              'Confirm $action',
              style: const TextStyle(
                color: HmiColors.textPrimary,
                fontSize: 16,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        content: Text(
          '$action "$label"?\n\n$description',
          style: const TextStyle(
            color: HmiColors.textSecondary,
            fontSize: 13,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text(
              'CANCEL',
              style: TextStyle(color: HmiColors.textMuted),
            ),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: newValue ? HmiColors.healthy : HmiColors.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(action),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await onToggle(newValue);
    }
  }
}

/// Custom industrial-style toggle switch.
class _IndustrialSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool> onChanged;

  const _IndustrialSwitch({required this.value, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeInOut,
        width: 48,
        height: 26,
        padding: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(13),
          color: value ? HmiColors.healthy.withValues(alpha: 0.3) : HmiColors.surfaceBorder,
          border: Border.all(
            color: value ? HmiColors.healthy : HmiColors.textMuted,
            width: 1.5,
          ),
        ),
        child: AnimatedAlign(
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeInOut,
          alignment: value ? Alignment.centerRight : Alignment.centerLeft,
          child: Container(
            width: 18,
            height: 18,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: value ? HmiColors.healthy : HmiColors.textMuted,
              boxShadow: value
                  ? [
                      BoxShadow(
                        color: HmiColors.healthy.withValues(alpha: 0.5),
                        blurRadius: 6,
                      ),
                    ]
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}

/// Emergency stop button — big red button to force batch to IDLE.
class EmergencyStopButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback onPressed;

  const EmergencyStopButton({
    super.key,
    this.isLoading = false,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading ? null : () => _confirmStop(context),
        borderRadius: BorderRadius.circular(12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
          decoration: BoxDecoration(
            color: HmiColors.danger.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: HmiColors.danger.withValues(alpha: 0.5), width: 1.5),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (isLoading)
                const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: HmiColors.danger,
                  ),
                )
              else
                const Icon(Icons.dangerous_rounded, color: HmiColors.danger, size: 20),
              const SizedBox(width: 8),
              const Text(
                'EMERGENCY STOP',
                style: TextStyle(
                  color: HmiColors.danger,
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
    );
  }

  Future<void> _confirmStop(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HmiColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.dangerous_rounded, color: HmiColors.danger, size: 28),
            SizedBox(width: 8),
            Text(
              'EMERGENCY STOP',
              style: TextStyle(
                color: HmiColors.danger,
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
          ],
        ),
        content: const Text(
          'This will immediately stop the batch process and force the reactor to IDLE state.\n\n'
          'All active operations will be halted.',
          style: TextStyle(color: HmiColors.textSecondary, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('CANCEL', style: TextStyle(color: HmiColors.textMuted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: HmiColors.danger,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
            ),
            child: const Text('CONFIRM STOP'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      onPressed();
    }
  }
}

/// Agitator RPM slider control — allows operator to set RPM override.
class AgitatorSliderWidget extends StatefulWidget {
  final double currentRpm;
  final bool isOverridden;
  final bool isLoading;
  final Future<void> Function(int rpm) onSetRpm;
  final Future<void> Function() onClearOverride;

  const AgitatorSliderWidget({
    super.key,
    required this.currentRpm,
    required this.isOverridden,
    required this.onSetRpm,
    required this.onClearOverride,
    this.isLoading = false,
  });

  @override
  State<AgitatorSliderWidget> createState() => _AgitatorSliderWidgetState();
}

class _AgitatorSliderWidgetState extends State<AgitatorSliderWidget> {
  double _sliderValue = 200;
  bool _isDragging = false;

  @override
  void didUpdateWidget(AgitatorSliderWidget oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_isDragging) {
      _sliderValue = widget.currentRpm.clamp(0, 500);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: HmiColors.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: widget.isOverridden
              ? HmiColors.warning.withValues(alpha: 0.4)
              : HmiColors.surfaceBorder,
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Row(
            children: [
              const Icon(Icons.speed_rounded, color: HmiColors.warning, size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text(
                  'Agitator Speed',
                  style: TextStyle(
                    color: HmiColors.textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
              if (widget.isOverridden)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: HmiColors.warningDim,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: const Text(
                    'OVERRIDE',
                    style: TextStyle(
                      color: HmiColors.warning,
                      fontSize: 9,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'DM Mono',
                      letterSpacing: 1,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          // Current value
          Text(
            '${widget.currentRpm.toInt()} RPM',
            style: const TextStyle(
              color: HmiColors.textPrimary,
              fontSize: 24,
              fontWeight: FontWeight.w700,
              fontFamily: 'DM Mono',
            ),
          ),
          const SizedBox(height: 12),
          // Slider
          SliderTheme(
            data: SliderThemeData(
              activeTrackColor: HmiColors.warning,
              inactiveTrackColor: HmiColors.surfaceBorder,
              thumbColor: HmiColors.warning,
              overlayColor: HmiColors.warning.withValues(alpha: 0.2),
              trackHeight: 4,
              thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 8),
            ),
            child: Slider(
              value: _sliderValue,
              min: 0,
              max: 500,
              divisions: 50,
              label: '${_sliderValue.toInt()} RPM',
              onChangeStart: (_) => _isDragging = true,
              onChanged: (v) => setState(() => _sliderValue = v),
              onChangeEnd: (_) => _isDragging = false,
            ),
          ),
          const SizedBox(height: 8),
          // Action buttons
          Row(
            children: [
              Expanded(
                child: _ActionButton(
                  label: 'SET ${_sliderValue.toInt()} RPM',
                  color: HmiColors.warning,
                  isLoading: widget.isLoading,
                  onPressed: () => widget.onSetRpm(_sliderValue.toInt()),
                ),
              ),
              if (widget.isOverridden) ...[
                const SizedBox(width: 8),
                _ActionButton(
                  label: 'AUTO',
                  color: HmiColors.textMuted,
                  isLoading: widget.isLoading,
                  onPressed: widget.onClearOverride,
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final String label;
  final Color color;
  final bool isLoading;
  final VoidCallback onPressed;

  const _ActionButton({
    required this.label,
    required this.color,
    required this.onPressed,
    this.isLoading = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: isLoading ? null : onPressed,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: color.withValues(alpha: 0.4)),
          ),
          child: Center(
            child: isLoading
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: color),
                  )
                : Text(
                    label,
                    style: TextStyle(
                      color: color,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      fontFamily: 'DM Mono',
                      letterSpacing: 1,
                    ),
                  ),
          ),
        ),
      ),
    );
  }
}
