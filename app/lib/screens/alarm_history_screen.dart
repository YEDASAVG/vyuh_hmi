import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../config/dashboard_config.dart';
import '../config/hmi_theme_engine.dart';
import '../services/api_service.dart';

/// ISA-18.2 Alarm History screen — scaled for 2K factory displays.
class AlarmHistoryScreen extends StatefulWidget {
  final ApiService api;
  final bool canManage;

  const AlarmHistoryScreen({
    super.key,
    required this.api,
    required this.canManage,
  });

  @override
  State<AlarmHistoryScreen> createState() => _AlarmHistoryScreenState();
}

class _AlarmHistoryScreenState extends State<AlarmHistoryScreen> {
  List<Map<String, dynamic>> _alarms = [];
  bool _isLoading = true;
  String? _stateFilter;
  int? _priorityFilter;

  static const _stateFilters = <String?>[
    null, 'active', 'acknowledged', 'shelved', 'cleared'
  ];
  static const _priorityLabels = {
    1: 'Critical', 2: 'High', 3: 'Medium', 4: 'Low', 5: 'Info'
  };

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final alarms = await widget.api.getAlarms(
      state: _stateFilter,
      priority: _priorityFilter,
    );
    if (mounted) {
      setState(() {
        _alarms = alarms;
        _isLoading = false;
      });
    }
  }

  Future<void> _ackAlarm(int id) async {
    final ok = await widget.api.ackAlarm(id);
    if (ok) _load();
  }

  Future<void> _shelveAlarm(int id) async {
    final colors = ActiveTheme.of(context);
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          backgroundColor: colors.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Text('Shelve Alarm #$id',
              style: GoogleFonts.outfit(
                  fontSize: 24, fontWeight: FontWeight.w700,
                  color: Colors.white)),
          content: TextField(
            controller: controller,
            style: GoogleFonts.outfit(fontSize: 20, color: Colors.white),
            decoration: InputDecoration(
              hintText: 'Reason for shelving...',
              hintStyle: GoogleFonts.outfit(
                  fontSize: 20, color: colors.textMuted),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text('Cancel',
                  style: GoogleFonts.outfit(
                      fontSize: 18, color: colors.textMuted)),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              style: FilledButton.styleFrom(backgroundColor: colors.accent),
              child: Text('Shelve 30 min',
                  style: GoogleFonts.outfit(
                      fontSize: 18, fontWeight: FontWeight.w600)),
            ),
          ],
        );
      },
    );
    if (reason != null && reason.isNotEmpty) {
      final ok = await widget.api.shelveAlarm(
          id, durationMinutes: 30, reason: reason);
      if (ok) _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ActiveTheme.of(context);

    return Column(
      children: [
        // Header bar
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 18),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(
              bottom: BorderSide(color: colors.surfaceBorder, width: 1),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded,
                  color: colors.accent, size: 34),
              const SizedBox(width: 14),
              Text(
                'ALARMS',
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(width: 24),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${_alarms.length} entries',
                  style: GoogleFonts.dmMono(
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                      color: colors.accent),
                ),
              ),
              const Spacer(),
              IconButton(
                icon: Icon(Icons.refresh_rounded,
                    color: Colors.white70, size: 28),
                onPressed: _load,
              ),
            ],
          ),
        ),

        // Filters row
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colors.surfaceBorder),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<String?>(
                      value: _stateFilter,
                      isExpanded: true,
                      dropdownColor: colors.surface,
                      icon: Icon(Icons.keyboard_arrow_down_rounded,
                          color: Colors.white70, size: 28),
                      style: GoogleFonts.outfit(
                          fontSize: 20, color: Colors.white),
                      items: _stateFilters.map((f) {
                        final label = f == null
                            ? 'All States'
                            : f[0].toUpperCase() + f.substring(1);
                        return DropdownMenuItem(
                          value: f,
                          child: Text(label,
                              style: GoogleFonts.outfit(
                                  fontSize: 20,
                                  color: Colors.white)),
                        );
                      }).toList(),
                      onChanged: (v) {
                        setState(() => _stateFilter = v);
                        _load();
                      },
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Container(
                  height: 56,
                  padding: const EdgeInsets.symmetric(horizontal: 18),
                  decoration: BoxDecoration(
                    color: colors.surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: colors.surfaceBorder),
                  ),
                  child: DropdownButtonHideUnderline(
                    child: DropdownButton<int?>(
                      value: _priorityFilter,
                      isExpanded: true,
                      dropdownColor: colors.surface,
                      icon: Icon(Icons.keyboard_arrow_down_rounded,
                          color: Colors.white70, size: 28),
                      style: GoogleFonts.outfit(
                          fontSize: 20, color: Colors.white),
                      items: [
                        DropdownMenuItem<int?>(
                          value: null,
                          child: Text('All Priorities',
                              style: GoogleFonts.outfit(
                                  fontSize: 20,
                                  color: Colors.white)),
                        ),
                        ..._priorityLabels.entries
                            .map((e) => DropdownMenuItem<int?>(
                                  value: e.key,
                                  child: Row(
                                    children: [
                                      Container(
                                        width: 14,
                                        height: 14,
                                        decoration: BoxDecoration(
                                          shape: BoxShape.circle,
                                          color: _priorityColor(e.key),
                                        ),
                                      ),
                                      const SizedBox(width: 12),
                                      Text(e.value,
                                          style: GoogleFonts.outfit(
                                              fontSize: 20,
                                              color: Colors.white)),
                                    ],
                                  ),
                                )),
                      ],
                      onChanged: (v) {
                        setState(() => _priorityFilter = v);
                        _load();
                      },
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),

        // Alarm list
        Expanded(
          child: _isLoading
              ? Center(
                  child: CircularProgressIndicator(color: colors.accent))
              : _alarms.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.check_circle_outline_rounded,
                              size: 80, color: colors.textMuted),
                          const SizedBox(height: 20),
                          Text('No alarms',
                              style: GoogleFonts.outfit(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white70)),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 28),
                      itemCount: _alarms.length,
                      itemBuilder: (c, i) =>
                          _buildAlarmTile(_alarms[i], colors),
                    ),
        ),
      ],
    );
  }

  static int _priorityFromString(String s) {
    switch (s.toLowerCase()) {
      case 'critical': return 1;
      case 'high': return 2;
      case 'medium': return 3;
      case 'low': return 4;
      case 'info': return 5;
      default: return int.tryParse(s) ?? 5;
    }
  }

  Widget _buildAlarmTile(Map<String, dynamic> alarm, ThemeConfig colors) {
    final id = (alarm['id'] is int)
        ? alarm['id'] as int
        : int.tryParse(alarm['id'].toString()) ?? 0;
    final rawPriority = alarm['priority'];
    final priority = rawPriority is int
        ? rawPriority
        : _priorityFromString(rawPriority?.toString() ?? '');
    final state = alarm['state'] as String? ?? 'active';
    final label = alarm['label'] as String? ?? '';
    final message = alarm['message'] as String? ?? '';
    final device = alarm['device_id'] as String? ?? '';
    final timestamp = alarm['timestamp'] as String? ?? '';
    final ackedBy = alarm['acked_by'] as String?;
    final ackedAt = alarm['acked_at'] as String?;
    final shelvedBy = alarm['shelved_by'] as String?;
    final shelvedUntil = alarm['shelved_until'] as String?;
    final value = alarm['value'];
    final threshold = alarm['threshold'];

    String formattedTime = '';
    try {
      final dt = DateTime.parse(timestamp);
      formattedTime = DateFormat('MMM d, HH:mm:ss').format(dt.toLocal());
    } catch (_) {
      formattedTime = timestamp;
    }

    final prioColor = _priorityColor(priority);

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: state == 'active'
              ? prioColor.withValues(alpha: 0.5)
              : colors.surfaceBorder,
          width: state == 'active' ? 2 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: priority badge + label + state badge
            Row(
              children: [
                _priorityBadge(priority),
                const SizedBox(width: 16),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.outfit(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      color: Colors.white,
                    ),
                  ),
                ),
                _stateBadge(state, colors),
              ],
            ),
            const SizedBox(height: 14),

            // Message
            Text(
              message,
              style: GoogleFonts.outfit(
                  fontSize: 20, color: Colors.white70),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 14),

            // Device + value + threshold + time row
            Wrap(
              spacing: 24,
              runSpacing: 10,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.memory_rounded,
                        size: 22, color: Colors.white60),
                    const SizedBox(width: 8),
                    Text(device,
                        style: GoogleFonts.dmMono(
                            fontSize: 18,
                            fontWeight: FontWeight.w600,
                            color: colors.accent)),
                  ],
                ),
                if (value != null && threshold != null)
                  Text(
                    'Value: ${_fmt(value)} / Threshold: ${_fmt(threshold)}',
                    style: GoogleFonts.dmMono(
                        fontSize: 18,
                        fontWeight: FontWeight.w500,
                        color: prioColor),
                  ),
                Text(formattedTime,
                    style: GoogleFonts.dmMono(
                        fontSize: 18, color: Colors.white54)),
              ],
            ),

            // Ack info
            if (ackedBy != null) ...[
              const SizedBox(height: 12),
              Text(
                'Acknowledged by $ackedBy at ${_fmtTime(ackedAt)}',
                style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: Colors.green.shade300),
              ),
            ],

            // Shelve info
            if (shelvedBy != null) ...[
              const SizedBox(height: 12),
              Text(
                'Shelved by $shelvedBy until ${_fmtTime(shelvedUntil)}',
                style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w500,
                    color: Colors.orange.shade300),
              ),
            ],

            // Actions
            if (widget.canManage && state == 'active') ...[
              const SizedBox(height: 18),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _ackAlarm(id),
                    icon: const Icon(Icons.check_circle_outline, size: 28),
                    label: Text('Acknowledge',
                        style: GoogleFonts.outfit(
                            fontSize: 20, fontWeight: FontWeight.w600)),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.green.shade300,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                    ),
                  ),
                  const SizedBox(width: 16),
                  TextButton.icon(
                    onPressed: () => _shelveAlarm(id),
                    icon: const Icon(Icons.snooze_rounded, size: 28),
                    label: Text('Shelve',
                        style: GoogleFonts.outfit(
                            fontSize: 20, fontWeight: FontWeight.w600)),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.orange.shade300,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 14),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _priorityBadge(int priority) {
    final color = _priorityColor(priority);
    final label = _priorityLabels[priority] ?? 'Info';
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.dmMono(
          fontSize: 17,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }

  Widget _stateBadge(String state, ThemeConfig colors) {
    final stateColor = switch (state) {
      'active' => Colors.red.shade300,
      'acknowledged' => Colors.green.shade300,
      'shelved' => Colors.orange.shade300,
      'cleared' => colors.textSecondary,
      _ => colors.textSecondary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: stateColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        state.toUpperCase(),
        style: GoogleFonts.dmMono(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: stateColor,
            letterSpacing: 0.5),
      ),
    );
  }

  Color _priorityColor(int priority) {
    return switch (priority) {
      1 => Colors.red.shade400,
      2 => Colors.orange.shade400,
      3 => Colors.amber.shade400,
      4 => Colors.blue.shade300,
      _ => Colors.grey.shade400,
    };
  }

  String _fmt(dynamic v) {
    if (v is double) return v.toStringAsFixed(1);
    return v.toString();
  }

  String _fmtTime(String? ts) {
    if (ts == null) return '';
    try {
      return DateFormat('MMM d, HH:mm').format(DateTime.parse(ts).toLocal());
    } catch (_) {
      return ts;
    }
  }
}
