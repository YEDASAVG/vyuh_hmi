import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../config/dashboard_config.dart';
import '../config/hmi_theme_engine.dart';
import '../services/api_service.dart';

/// ISA-18.2 Alarm History screen.
///
/// Features:
/// - Filterable by state (Active, Acknowledged, Shelved, Cleared) and priority
/// - Acknowledge / shelve actions for operators
/// - Color-coded priority badges
/// - Auto-refresh every 10 seconds
class AlarmHistoryScreen extends StatefulWidget {
  final ApiService api;
  final bool canManage; // operator+ can ack/shelve

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

  static const _stateFilters = <String?>[null, 'active', 'acknowledged', 'shelved', 'cleared'];
  static const _priorityLabels = {1: 'Critical', 2: 'High', 3: 'Medium', 4: 'Low', 5: 'Info'};

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
    final reason = await showDialog<String>(
      context: context,
      builder: (ctx) {
        final controller = TextEditingController();
        return AlertDialog(
          backgroundColor: const Color(0xFF1A1A2E),
          title: Text('Shelve Alarm #$id',
              style: GoogleFonts.outfit(color: Colors.white)),
          content: TextField(
            controller: controller,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              hintText: 'Reason for shelving...',
              hintStyle: TextStyle(color: Colors.white38),
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, controller.text),
              child: const Text('Shelve 30 min'),
            ),
          ],
        );
      },
    );
    if (reason != null && reason.isNotEmpty) {
      final ok = await widget.api.shelveAlarm(id, durationMinutes: 30, reason: reason);
      if (ok) _load();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ActiveTheme.of(context);

    return Column(
      children: [
        // ── Header + filters ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: colors.accent, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Alarm History',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              // Refresh
              IconButton(
                icon: Icon(Icons.refresh_rounded, color: colors.textSecondary, size: 20),
                onPressed: _load,
              ),
            ],
          ),
        ),

        // ── State filter chips ──
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: _stateFilters.map((f) {
              final selected = _stateFilter == f;
              final label = f == null ? 'All' : f[0].toUpperCase() + f.substring(1);
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(label),
                  selected: selected,
                  onSelected: (_) {
                    setState(() => _stateFilter = f);
                    _load();
                  },
                  selectedColor: colors.accent.withValues(alpha: 0.25),
                  labelStyle: GoogleFonts.outfit(
                    fontSize: 12,
                    color: selected ? colors.accent : colors.textSecondary,
                  ),
                  backgroundColor: colors.surface,
                  side: BorderSide(
                    color: selected ? colors.accent : colors.surfaceBorder,
                  ),
                ),
              );
            }).toList(),
          ),
        ),

        // ── Priority filter ──
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            children: [
              _priorityChip(null, 'All Priorities', colors),
              ..._priorityLabels.entries.map(
                (e) => _priorityChip(e.key, e.value, colors),
              ),
            ],
          ),
        ),

        const SizedBox(height: 8),

        // ── Alarm list ──
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _alarms.isEmpty
                  ? Center(
                      child: Text('No alarms',
                          style: GoogleFonts.outfit(
                              color: colors.textSecondary, fontSize: 14)),
                    )
                  : RefreshIndicator(
                      onRefresh: _load,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 12),
                        itemCount: _alarms.length,
                        itemBuilder: (ctx, i) => _buildAlarmTile(_alarms[i], colors),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _priorityChip(int? value, String label, ThemeConfig colors) {
    final selected = _priorityFilter == value;
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: FilterChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) {
          setState(() => _priorityFilter = value);
          _load();
        },
        selectedColor: _priorityColor(value ?? 5).withValues(alpha: 0.25),
        labelStyle: GoogleFonts.outfit(
          fontSize: 12,
          color: selected ? _priorityColor(value ?? 5) : colors.textSecondary,
        ),
        backgroundColor: colors.surface,
        side: BorderSide(
          color: selected ? _priorityColor(value ?? 5) : colors.surfaceBorder,
        ),
      ),
    );
  }

  Widget _buildAlarmTile(Map<String, dynamic> alarm, ThemeConfig colors) {
    final id = alarm['id'] as int;
    final priority = alarm['priority'] as int? ?? 5;
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

    return Card(
      color: colors.surface,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: state == 'active' ? prioColor.withValues(alpha: 0.5) : colors.surfaceBorder,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Row 1: priority badge + label + state badge + time
            Row(
              children: [
                _priorityBadge(priority),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    label,
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary,
                    ),
                  ),
                ),
                _stateBadge(state, colors),
              ],
            ),
            const SizedBox(height: 6),

            // Row 2: message + value info
            Text(
              message,
              style: GoogleFonts.outfit(fontSize: 12, color: colors.textSecondary),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),

            // Row 3: device, value, threshold, time
            Row(
              children: [
                Icon(Icons.memory_rounded, size: 12, color: colors.textSecondary),
                const SizedBox(width: 4),
                Text(device, style: GoogleFonts.dmMono(fontSize: 11, color: colors.textSecondary)),
                const Spacer(),
                if (value != null && threshold != null) ...[
                  Text(
                    'Value: ${_fmt(value)} / Threshold: ${_fmt(threshold)}',
                    style: GoogleFonts.dmMono(fontSize: 10, color: prioColor),
                  ),
                  const SizedBox(width: 8),
                ],
                Text(formattedTime,
                    style: GoogleFonts.dmMono(fontSize: 10, color: colors.textSecondary)),
              ],
            ),

            // Ack info
            if (ackedBy != null) ...[
              const SizedBox(height: 4),
              Text(
                'Acknowledged by $ackedBy at ${_fmtTime(ackedAt)}',
                style: GoogleFonts.outfit(fontSize: 11, color: Colors.green.shade300),
              ),
            ],

            // Shelve info
            if (shelvedBy != null) ...[
              const SizedBox(height: 4),
              Text(
                'Shelved by $shelvedBy until ${_fmtTime(shelvedUntil)}',
                style: GoogleFonts.outfit(fontSize: 11, color: Colors.orange.shade300),
              ),
            ],

            // Actions
            if (widget.canManage && state == 'active') ...[
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  TextButton.icon(
                    onPressed: () => _ackAlarm(id),
                    icon: const Icon(Icons.check_circle_outline, size: 16),
                    label: const Text('Acknowledge'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.green.shade300,
                      textStyle: GoogleFonts.outfit(fontSize: 12),
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: () => _shelveAlarm(id),
                    icon: const Icon(Icons.snooze_rounded, size: 16),
                    label: const Text('Shelve'),
                    style: TextButton.styleFrom(
                      foregroundColor: Colors.orange.shade300,
                      textStyle: GoogleFonts.outfit(fontSize: 12),
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        label.toUpperCase(),
        style: GoogleFonts.dmMono(
          fontSize: 9,
          fontWeight: FontWeight.w700,
          color: color,
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
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: stateColor.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        state.toUpperCase(),
        style: GoogleFonts.dmMono(fontSize: 9, fontWeight: FontWeight.w600, color: stateColor),
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
