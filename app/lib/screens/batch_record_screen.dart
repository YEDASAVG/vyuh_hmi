import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../config/dashboard_config.dart';
import '../config/hmi_theme_engine.dart';
import '../services/api_service.dart';

/// ISA-88 Batch Record screen — 3-column Kanban board for 2K factory displays.
/// Shows Running / Held / Completed batches side-by-side so parallel operations
/// are visible at a glance.
class BatchRecordScreen extends StatefulWidget {
  final ApiService api;

  const BatchRecordScreen({super.key, required this.api});

  @override
  State<BatchRecordScreen> createState() => _BatchRecordScreenState();
}

class _BatchRecordScreenState extends State<BatchRecordScreen> {
  List<Map<String, dynamic>> _allBatches = [];
  bool _isLoading = true;
  Timer? _autoRefresh;

  // Expanded card state — track per batch
  String? _expandedBatchId;
  Map<String, dynamic>? _expandedDetail;

  @override
  void initState() {
    super.initState();
    _load();
    _autoRefresh = Timer.periodic(
        const Duration(seconds: 10), (_) => _load(silent: true));
  }

  @override
  void dispose() {
    _autoRefresh?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _isLoading = true);
    final batches = await widget.api.getBatches(limit: 200);
    if (mounted) {
      setState(() {
        _allBatches = batches;
        _isLoading = false;
      });
    }
  }

  Future<void> _loadDetail(String batchId) async {
    if (_expandedBatchId == batchId) {
      setState(() {
        _expandedBatchId = null;
        _expandedDetail = null;
      });
      return;
    }
    final detail = await widget.api.getBatch(batchId);
    if (mounted) {
      setState(() {
        _expandedBatchId = batchId;
        _expandedDetail = detail;
      });
    }
  }

  // ---- Column definitions ----
  static const _columns = <_BoardColumn>[
    _BoardColumn(
      title: 'RUNNING',
      icon: Icons.play_circle_rounded,
      statuses: ['running'],
      color: Colors.blue,
    ),
    _BoardColumn(
      title: 'HELD',
      icon: Icons.pause_circle_rounded,
      statuses: ['held'],
      color: Colors.orange,
    ),
    _BoardColumn(
      title: 'COMPLETED',
      icon: Icons.check_circle_rounded,
      statuses: ['completed', 'aborted'],
      color: Colors.green,
    ),
  ];

  List<Map<String, dynamic>> _batchesForColumn(_BoardColumn col) {
    return _allBatches.where((b) {
      final s = (b['status'] as String? ?? '').toLowerCase();
      return col.statuses.contains(s);
    }).toList();
  }

  // ---- Build ----

  @override
  Widget build(BuildContext context) {
    final colors = ActiveTheme.of(context);

    return Column(
      children: [
        _buildHeader(colors),
        Expanded(
          child: _isLoading
              ? Center(
                  child: CircularProgressIndicator(color: colors.accent))
              : _allBatches.isEmpty
                  ? _buildEmpty(colors)
                  : _buildBoard(colors),
        ),
      ],
    );
  }

  // ---- Header ----

  Widget _buildHeader(ThemeConfig colors) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 16),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          bottom: BorderSide(color: colors.surfaceBorder, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.assignment_rounded, color: colors.accent, size: 32),
          const SizedBox(width: 14),
          Text(
            'BATCH RECORDS',
            style: GoogleFonts.outfit(
              fontSize: 28,
              fontWeight: FontWeight.w700,
              color: Colors.white,
              letterSpacing: 2,
            ),
          ),
          const SizedBox(width: 20),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: colors.accent.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text(
              '${_allBatches.length}',
              style: GoogleFonts.dmMono(
                  fontSize: 20,
                  fontWeight: FontWeight.w700,
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
    );
  }

  // ---- Empty state ----

  Widget _buildEmpty(ThemeConfig colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.science_outlined, size: 80, color: colors.textMuted),
          const SizedBox(height: 16),
          Text('No batch records',
              style: GoogleFonts.outfit(
                  fontSize: 26, color: Colors.white70)),
        ],
      ),
    );
  }

  // ---- 3-column Kanban board ----

  Widget _buildBoard(ThemeConfig colors) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (int i = 0; i < _columns.length; i++) ...[
            if (i > 0) const SizedBox(width: 14),
            Expanded(
              child: _buildColumn(_columns[i], colors),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildColumn(_BoardColumn col, ThemeConfig colors) {
    final batches = _batchesForColumn(col);
    final colColor = col.color.shade300;

    return Container(
      decoration: BoxDecoration(
        color: col.color.withValues(alpha: 0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colColor.withValues(alpha: 0.2),
          width: 1.5,
        ),
      ),
      child: Column(
        children: [
          // Column header
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            decoration: BoxDecoration(
              color: colColor.withValues(alpha: 0.1),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(14)),
            ),
            child: Row(
              children: [
                Icon(col.icon, color: colColor, size: 26),
                const SizedBox(width: 10),
                Text(
                  col.title,
                  style: GoogleFonts.outfit(
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                    color: colColor,
                    letterSpacing: 1.5,
                  ),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 12, vertical: 4),
                  decoration: BoxDecoration(
                    color: colColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${batches.length}',
                    style: GoogleFonts.dmMono(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: colColor,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Scrollable batch cards
          Expanded(
            child: batches.isEmpty
                ? Center(
                    child: Text(
                      'None',
                      style: GoogleFonts.outfit(
                          fontSize: 20, color: Colors.white24),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(12),
                    itemCount: batches.length,
                    itemBuilder: (_, i) =>
                        _buildBatchCard(batches[i], colColor, colors),
                  ),
          ),
        ],
      ),
    );
  }

  // ---- Batch card ----

  Widget _buildBatchCard(
      Map<String, dynamic> batch, Color colColor, ThemeConfig colors) {
    final batchId = batch['batch_id'] as String? ?? '';
    final recipe = batch['recipe_name'] as String? ?? '';
    final device = batch['device_id'] as String? ?? '';
    final operator = batch['operator'] as String? ?? '';
    final status = batch['status'] as String? ?? 'running';
    final startTime = batch['start_time'] as String? ?? '';
    final endTime = batch['end_time'] as String?;
    final notes = batch['notes'] as String?;

    final isExpanded = _expandedBatchId == batchId;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: isExpanded
              ? colColor.withValues(alpha: 0.6)
              : colors.surfaceBorder,
          width: isExpanded ? 2 : 1.5,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => _loadDetail(batchId),
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Batch ID + status
              Row(
                children: [
                  Icon(Icons.science_rounded, size: 24, color: colColor),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      batchId,
                      style: GoogleFonts.dmMono(
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                        color: Colors.white,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  _statusBadge(status, colColor),
                ],
              ),
              const SizedBox(height: 14),

              // Recipe
              _infoRow(Icons.receipt_long_rounded, recipe, colors),
              const SizedBox(height: 8),
              // Device
              _infoRow(Icons.memory_rounded, device, colors),
              const SizedBox(height: 8),
              // Operator
              _infoRow(Icons.person_outline_rounded, operator, colors),
              const SizedBox(height: 12),

              // Times
              Text(
                'Start  ${_fmtTime(startTime)}',
                style: GoogleFonts.dmMono(
                    fontSize: 17, color: Colors.white60),
              ),
              if (endTime != null) ...[
                const SizedBox(height: 4),
                Text(
                  'End    ${_fmtTime(endTime)}',
                  style: GoogleFonts.dmMono(
                      fontSize: 17, color: Colors.white60),
                ),
                const SizedBox(height: 4),
                Text(
                  'Duration  ${_duration(startTime, endTime)}',
                  style: GoogleFonts.dmMono(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: colColor),
                ),
              ],

              // Notes
              if (notes != null && notes.isNotEmpty) ...[
                const SizedBox(height: 10),
                Text(
                  notes,
                  style: GoogleFonts.outfit(
                      fontSize: 17, color: Colors.white54),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],

              // Expanded: steps timeline
              if (isExpanded && _expandedDetail != null) ...[
                const SizedBox(height: 16),
                Divider(color: colColor.withValues(alpha: 0.2), height: 1),
                const SizedBox(height: 14),
                _buildStepsTimeline(colColor, colors),
              ],

              // Expand indicator
              const SizedBox(height: 8),
              Center(
                child: Icon(
                  isExpanded
                      ? Icons.expand_less_rounded
                      : Icons.expand_more_rounded,
                  size: 26,
                  color: Colors.white38,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ---- Steps timeline ----

  Widget _buildStepsTimeline(Color colColor, ThemeConfig colors) {
    final steps = (_expandedDetail?['steps'] as List?) ?? [];
    if (steps.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Text('No steps recorded',
            style: GoogleFonts.outfit(
                fontSize: 19, color: Colors.white54)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('STEPS',
            style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w700,
                color: Colors.white,
                letterSpacing: 1)),
        const SizedBox(height: 12),
        ...List.generate(steps.length, (i) {
          final step = steps[i] as Map<String, dynamic>;
          final name = step['name'] as String? ?? '';
          final status = step['status'] as String? ?? '';
          final startTime = step['start_time'] as String? ?? '';
          final endTime = step['end_time'] as String?;
          final result = step['result'] as String?;
          final isLast = i == steps.length - 1;

          final stepColor = switch (status) {
            'completed' => Colors.green.shade300,
            'running' => Colors.blue.shade300,
            'failed' => Colors.red.shade300,
            _ => Colors.white38,
          };

          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Timeline dot + connector
                SizedBox(
                  width: 36,
                  child: Column(
                    children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: stepColor.withValues(alpha: 0.2),
                          border: Border.all(color: stepColor, width: 3),
                        ),
                      ),
                      if (!isLast)
                        Expanded(
                          child: Container(
                              width: 3, color: colors.surfaceBorder),
                        ),
                    ],
                  ),
                ),

                // Step content
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                '${step['step_number'] ?? i + 1}. $name',
                                style: GoogleFonts.outfit(
                                    fontSize: 18,
                                    fontWeight: FontWeight.w600,
                                    color: Colors.white),
                              ),
                            ),
                            Text(status.toUpperCase(),
                                style: GoogleFonts.dmMono(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                    color: stepColor)),
                          ],
                        ),
                        const SizedBox(height: 3),
                        Text(
                          '${_fmtTime(startTime)}${endTime != null ? ' → ${_fmtTime(endTime)}' : ' → …'}',
                          style: GoogleFonts.dmMono(
                              fontSize: 15, color: Colors.white54),
                        ),
                        if (result != null)
                          Text('Result: $result',
                              style: GoogleFonts.dmMono(
                                  fontSize: 15, color: stepColor)),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        }),
      ],
    );
  }

  // ---- Helpers ----

  Widget _infoRow(IconData icon, String text, ThemeConfig colors) {
    return Row(
      children: [
        Icon(icon, size: 20, color: Colors.white54),
        const SizedBox(width: 8),
        Expanded(
          child: Text(text,
              style: GoogleFonts.outfit(
                  fontSize: 19, color: Colors.white70),
              overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  Widget _statusBadge(String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Text(
        status.toUpperCase(),
        style: GoogleFonts.dmMono(
            fontSize: 17,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: 0.5),
      ),
    );
  }

  String _fmtTime(String ts) {
    try {
      return DateFormat('MMM d, HH:mm').format(DateTime.parse(ts).toLocal());
    } catch (_) {
      return ts;
    }
  }

  String _duration(String start, String end) {
    try {
      final d = DateTime.parse(end).difference(DateTime.parse(start));
      if (d.inHours > 0) return '${d.inHours}h ${d.inMinutes % 60}m';
      if (d.inMinutes > 0) return '${d.inMinutes}m ${d.inSeconds % 60}s';
      return '${d.inSeconds}s';
    } catch (_) {
      return '';
    }
  }
}

/// Column config for the Kanban board.
class _BoardColumn {
  final String title;
  final IconData icon;
  final List<String> statuses;
  final MaterialColor color;

  const _BoardColumn({
    required this.title,
    required this.icon,
    required this.statuses,
    required this.color,
  });
}
