import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../config/dashboard_config.dart';
import '../config/hmi_theme_engine.dart';
import '../services/api_service.dart';

/// ISA-88 Batch Record screen.
///
/// Features:
/// - List of batch records with status, operator, recipe
/// - Tap to expand → shows batch steps timeline
/// - Filter by status (Running, Completed, Aborted, Held)
class BatchRecordScreen extends StatefulWidget {
  final ApiService api;

  const BatchRecordScreen({super.key, required this.api});

  @override
  State<BatchRecordScreen> createState() => _BatchRecordScreenState();
}

class _BatchRecordScreenState extends State<BatchRecordScreen> {
  List<Map<String, dynamic>> _batches = [];
  bool _isLoading = true;
  String? _statusFilter;
  String? _expandedBatchId;
  Map<String, dynamic>? _expandedDetail;

  static const _statusFilters = <String?>[null, 'running', 'completed', 'aborted', 'held'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _isLoading = true);
    final batches = await widget.api.getBatches(status: _statusFilter);
    if (mounted) {
      setState(() {
        _batches = batches;
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

  @override
  Widget build(BuildContext context) {
    final colors = ActiveTheme.of(context);

    return Column(
      children: [
        // ── Header ──
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
          child: Row(
            children: [
              Icon(Icons.assignment_rounded, color: colors.accent, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Batch Records',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              Text(
                '${_batches.length} records',
                style: GoogleFonts.dmMono(fontSize: 12, color: colors.textSecondary),
              ),
              const SizedBox(width: 8),
              IconButton(
                icon: Icon(Icons.refresh_rounded, color: colors.textSecondary, size: 20),
                onPressed: _load,
              ),
            ],
          ),
        ),

        // ── Status filter dropdown ──
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Container(
            height: 40,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: colors.surface,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: colors.surfaceBorder),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String?>(
                value: _statusFilter,
                isExpanded: true,
                dropdownColor: colors.surface,
                icon: Icon(Icons.keyboard_arrow_down_rounded, color: colors.textSecondary, size: 20),
                style: GoogleFonts.outfit(fontSize: 13, color: colors.textPrimary),
                items: _statusFilters.map((f) {
                  final label = f == null ? 'All Statuses' : f[0].toUpperCase() + f.substring(1);
                  return DropdownMenuItem(
                    value: f,
                    child: Row(
                      children: [
                        Container(
                          width: 8,
                          height: 8,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: _statusColor(f ?? 'all'),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(label, style: GoogleFonts.outfit(fontSize: 13, color: colors.textPrimary)),
                      ],
                    ),
                  );
                }).toList(),
                onChanged: (v) {
                  setState(() => _statusFilter = v);
                  _load();
                },
              ),
            ),
          ),
        ),

        const SizedBox(height: 8),

        // ── Batch list (responsive grid on wide) ──
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _batches.isEmpty
                  ? Center(
                      child: Text('No batch records',
                          style: GoogleFonts.outfit(
                              color: colors.textSecondary, fontSize: 14)),
                    )
                  : LayoutBuilder(
                      builder: (ctx, constraints) {
                        final cols = constraints.maxWidth >= 1200 ? 3
                            : constraints.maxWidth >= 800 ? 2
                            : 1;
                        if (cols == 1) {
                          return RefreshIndicator(
                            onRefresh: _load,
                            child: ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                              itemCount: _batches.length,
                              itemBuilder: (c, i) => _buildBatchTile(_batches[i], colors),
                            ),
                          );
                        }
                        return RefreshIndicator(
                          onRefresh: _load,
                          child: GridView.builder(
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                              crossAxisCount: cols,
                              crossAxisSpacing: 10,
                              mainAxisSpacing: 0,
                              mainAxisExtent: 220,
                            ),
                            itemCount: _batches.length,
                            itemBuilder: (c, i) => _buildBatchTile(_batches[i], colors),
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildBatchTile(Map<String, dynamic> batch, ThemeConfig colors) {
    final batchId = batch['batch_id'] as String? ?? '';
    final recipe = batch['recipe_name'] as String? ?? '';
    final device = batch['device_id'] as String? ?? '';
    final operator = batch['operator'] as String? ?? '';
    final status = batch['status'] as String? ?? 'running';
    final startTime = batch['start_time'] as String? ?? '';
    final endTime = batch['end_time'] as String?;
    final notes = batch['notes'] as String?;

    final isExpanded = _expandedBatchId == batchId;
    final statusColor = _statusColor(status);

    return Card(
      color: colors.surface,
      margin: const EdgeInsets.only(bottom: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(10),
        side: BorderSide(
          color: isExpanded ? colors.accent.withValues(alpha: 0.5) : colors.surfaceBorder,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _loadDetail(batchId),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Row 1: batch ID + status
              Row(
                children: [
                  Icon(Icons.science_rounded, size: 16, color: colors.accent),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      batchId,
                      style: GoogleFonts.dmMono(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: colors.textPrimary,
                      ),
                    ),
                  ),
                  _statusBadge(status, statusColor),
                ],
              ),
              const SizedBox(height: 6),

              // Row 2: recipe + device + operator
              Row(
                children: [
                  _infoChip(Icons.receipt_long_rounded, recipe, colors),
                  const SizedBox(width: 8),
                  _infoChip(Icons.memory_rounded, device, colors),
                  const SizedBox(width: 8),
                  _infoChip(Icons.person_outline_rounded, operator, colors),
                ],
              ),
              const SizedBox(height: 4),

              // Row 3: times
              Row(
                children: [
                  Text('Start: ${_fmtTime(startTime)}',
                      style: GoogleFonts.dmMono(fontSize: 10, color: colors.textSecondary)),
                  if (endTime != null) ...[
                    const SizedBox(width: 12),
                    Text('End: ${_fmtTime(endTime)}',
                        style: GoogleFonts.dmMono(fontSize: 10, color: colors.textSecondary)),
                    const SizedBox(width: 12),
                    Text(_duration(startTime, endTime),
                        style: GoogleFonts.dmMono(fontSize: 10, color: statusColor)),
                  ],
                ],
              ),

              // Notes
              if (notes != null && notes.isNotEmpty) ...[
                const SizedBox(height: 4),
                Text('Notes: $notes',
                    style: GoogleFonts.outfit(fontSize: 11, color: colors.textSecondary)),
              ],

              // Expanded: steps timeline
              if (isExpanded && _expandedDetail != null) ...[
                const SizedBox(height: 12),
                _buildStepsTimeline(colors),
              ],

              // Expand indicator
              Center(
                child: Icon(
                  isExpanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                  size: 18,
                  color: colors.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStepsTimeline(ThemeConfig colors) {
    final steps = (_expandedDetail?['steps'] as List?) ?? [];
    if (steps.isEmpty) {
      return Container(
        padding: const EdgeInsets.symmetric(vertical: 12),
        child: Text('No steps recorded',
            style: GoogleFonts.outfit(fontSize: 12, color: colors.textSecondary)),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Batch Steps',
            style: GoogleFonts.outfit(
                fontSize: 13, fontWeight: FontWeight.w600, color: colors.textPrimary)),
        const SizedBox(height: 8),
        ...List.generate(steps.length, (i) {
          final step = steps[i] as Map<String, dynamic>;
          final name = step['name'] as String? ?? '';
          final status = step['status'] as String? ?? '';
          final startTime = step['start_time'] as String? ?? '';
          final endTime = step['end_time'] as String?;
          final params = step['parameters'] as String?;
          final result = step['result'] as String?;
          final isLast = i == steps.length - 1;

          final stepColor = switch (status) {
            'completed' => Colors.green.shade300,
            'running' => colors.accent,
            'failed' => Colors.red.shade300,
            _ => colors.textSecondary,
          };

          return IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Timeline connector
                SizedBox(
                  width: 28,
                  child: Column(
                    children: [
                      Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: stepColor.withValues(alpha: 0.2),
                          border: Border.all(color: stepColor, width: 2),
                        ),
                      ),
                      if (!isLast)
                        Expanded(
                          child: Container(
                            width: 2,
                            color: colors.surfaceBorder,
                          ),
                        ),
                    ],
                  ),
                ),

                // Step content
                Expanded(
                  child: Padding(
                    padding: EdgeInsets.only(bottom: isLast ? 0 : 12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Text('Step ${step['step_number'] ?? i + 1}: $name',
                                style: GoogleFonts.outfit(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w500,
                                    color: colors.textPrimary)),
                            const Spacer(),
                            Text(status.toUpperCase(),
                                style: GoogleFonts.dmMono(
                                    fontSize: 9,
                                    fontWeight: FontWeight.w600,
                                    color: stepColor)),
                          ],
                        ),
                        const SizedBox(height: 2),
                        Text(
                          '${_fmtTime(startTime)}${endTime != null ? ' → ${_fmtTime(endTime)}' : ' → ...'}',
                          style: GoogleFonts.dmMono(fontSize: 10, color: colors.textSecondary),
                        ),
                        if (params != null)
                          Text('Params: $params',
                              style: GoogleFonts.dmMono(fontSize: 10, color: colors.textSecondary)),
                        if (result != null)
                          Text('Result: $result',
                              style: GoogleFonts.dmMono(fontSize: 10, color: stepColor)),
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

  Widget _infoChip(IconData icon, String text, ThemeConfig colors) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 12, color: colors.textSecondary),
        const SizedBox(width: 3),
        Text(text, style: GoogleFonts.outfit(fontSize: 11, color: colors.textSecondary)),
      ],
    );
  }

  Widget _statusBadge(String status, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        status.toUpperCase(),
        style: GoogleFonts.dmMono(fontSize: 9, fontWeight: FontWeight.w600, color: color),
      ),
    );
  }

  Color _statusColor(String status) {
    return switch (status) {
      'running' => Colors.blue.shade300,
      'completed' => Colors.green.shade300,
      'aborted' => Colors.red.shade300,
      'held' => Colors.orange.shade300,
      _ => Colors.cyan.shade300,
    };
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
