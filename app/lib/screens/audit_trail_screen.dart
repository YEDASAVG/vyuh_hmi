import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../config/dashboard_config.dart';
import '../config/hmi_theme_engine.dart';
import '../services/auth_service.dart';

/// Audit trail screen — 21 CFR Part 11 compliance.
///
/// SCADA-style data table with day-group separators, sortable columns,
/// and color-coded action badges. Built for 2K factory displays.
class AuditTrailScreen extends StatefulWidget {
  final AuthService authService;

  const AuditTrailScreen({super.key, required this.authService});

  @override
  State<AuditTrailScreen> createState() => _AuditTrailScreenState();
}

enum _SortColumn { timestamp, action, user, device }

class _AuditTrailScreenState extends State<AuditTrailScreen> {
  List<AuditEntry> _entries = [];
  bool _isLoading = true;
  String? _filterAction;
  _SortColumn _sortBy = _SortColumn.timestamp;
  bool _sortAsc = false; // newest first by default

  static const _actionFilters = [
    null,
    'login',
    'write_register',
    'electronic_signature',
    'create_user',
    'add_device',
    'remove_device',
  ];

  @override
  void initState() {
    super.initState();
    _loadAudit();
  }

  Future<void> _loadAudit() async {
    setState(() => _isLoading = true);
    final entries = await widget.authService.getAuditTrail(
      action: _filterAction,
      limit: 200,
    );
    if (mounted) {
      setState(() {
        _entries = entries;
        _isLoading = false;
      });
    }
  }

  List<AuditEntry> get _sortedEntries {
    final sorted = List<AuditEntry>.from(_entries);
    sorted.sort((a, b) {
      int cmp;
      switch (_sortBy) {
        case _SortColumn.timestamp:
          cmp = a.timestamp.compareTo(b.timestamp);
        case _SortColumn.action:
          cmp = a.action.compareTo(b.action);
        case _SortColumn.user:
          cmp = a.username.compareTo(b.username);
        case _SortColumn.device:
          cmp = (a.deviceId ?? '').compareTo(b.deviceId ?? '');
      }
      return _sortAsc ? cmp : -cmp;
    });
    return sorted;
  }

  void _onSort(_SortColumn col) {
    setState(() {
      if (_sortBy == col) {
        _sortAsc = !_sortAsc;
      } else {
        _sortBy = col;
        _sortAsc = col != _SortColumn.timestamp; // default desc for time
      }
    });
  }

  /// Group sorted entries by day for date separator rows.
  List<dynamic> _buildGroupedRows() {
    final sorted = _sortedEntries;
    final List<dynamic> rows = []; // String = date header, AuditEntry = row
    String? lastDay;

    for (final entry in sorted) {
      String day;
      try {
        final dt = DateTime.parse(entry.timestamp).toLocal();
        day = DateFormat('EEEE, MMM dd yyyy').format(dt);
      } catch (_) {
        day = 'Unknown Date';
      }
      if (day != lastDay) {
        rows.add(day);
        lastDay = day;
      }
      rows.add(entry);
    }
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    final colors = ActiveTheme.of(context);
    final rows = _isLoading ? <dynamic>[] : _buildGroupedRows();

    return Column(
      children: [
        // ── Header Bar ──
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          decoration: BoxDecoration(
            color: colors.surface,
            border: Border(
              bottom: BorderSide(color: colors.surfaceBorder, width: 1),
            ),
          ),
          child: Row(
            children: [
              Icon(Icons.history_edu_rounded,
                  color: colors.accent, size: 32),
              const SizedBox(width: 14),
              Text(
                'AUDIT TRAIL',
                style: GoogleFonts.outfit(
                  fontSize: 28,
                  fontWeight: FontWeight.w700,
                  color: Colors.white,
                  letterSpacing: 2,
                ),
              ),
              const SizedBox(width: 16),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                decoration: BoxDecoration(
                  color: colors.accent.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '${_entries.length}',
                  style: GoogleFonts.dmMono(
                      fontSize: 20,
                      fontWeight: FontWeight.w700,
                      color: colors.accent),
                ),
              ),
              const Spacer(),
              // Action filter
              Container(
                height: 50,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: colors.background,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: colors.surfaceBorder),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String?>(
                    value: _filterAction,
                    dropdownColor: colors.surface,
                    icon: Icon(Icons.keyboard_arrow_down_rounded,
                        color: Colors.white70, size: 24),
                    style:
                        GoogleFonts.outfit(fontSize: 18, color: Colors.white),
                    items: _actionFilters.map((filter) {
                      final label = filter == null
                          ? 'All Actions'
                          : _formatActionLabel(filter);
                      return DropdownMenuItem(
                        value: filter,
                        child: Text(label,
                            style: GoogleFonts.outfit(
                                fontSize: 18, color: Colors.white)),
                      );
                    }).toList(),
                    onChanged: (v) {
                      setState(() => _filterAction = v);
                      _loadAudit();
                    },
                  ),
                ),
              ),
              const SizedBox(width: 14),
              IconButton(
                icon: Icon(Icons.refresh_rounded,
                    color: Colors.white70, size: 28),
                onPressed: _loadAudit,
                tooltip: 'Refresh',
              ),
            ],
          ),
        ),

        // ── Column Headers (sortable) ──
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
          decoration: BoxDecoration(
            color: colors.surface.withValues(alpha: 0.6),
            border: Border(
              bottom: BorderSide(color: colors.surfaceBorder, width: 1),
            ),
          ),
          child: Row(
            children: [
              _columnHeader('TIME', _SortColumn.timestamp, 180, colors),
              _columnHeader('ACTION', _SortColumn.action, 220, colors),
              _columnHeader('USER', _SortColumn.user, 200, colors),
              _columnHeader('DEVICE', _SortColumn.device, 180, colors),
              Expanded(
                child: Text(
                  'DETAILS',
                  style: GoogleFonts.dmMono(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white70,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
              SizedBox(
                width: 140,
                child: Text(
                  'IP',
                  style: GoogleFonts.dmMono(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: Colors.white70,
                    letterSpacing: 1.2,
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── Table Body ──
        Expanded(
          child: _isLoading
              ? Center(
                  child: CircularProgressIndicator(color: colors.accent))
              : _entries.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.history_edu_outlined,
                              size: 80, color: Colors.white38),
                          const SizedBox(height: 16),
                          Text(
                            'No audit entries',
                            style: GoogleFonts.outfit(
                                fontSize: 26, color: Colors.white70),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.only(bottom: 24),
                      itemCount: rows.length,
                      itemBuilder: (context, index) {
                        final item = rows[index];
                        if (item is String) {
                          return _buildDateSeparator(item, colors);
                        }
                        final entry = item as AuditEntry;
                        final isEven = index % 2 == 0;
                        return _buildTableRow(entry, isEven, colors);
                      },
                    ),
        ),
      ],
    );
  }

  // ── Sortable column header ──
  Widget _columnHeader(
      String label, _SortColumn col, double width, ThemeConfig colors) {
    final isActive = _sortBy == col;
    return InkWell(
      onTap: () => _onSort(col),
      child: SizedBox(
        width: width,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: GoogleFonts.dmMono(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: isActive ? colors.accent : Colors.white70,
                letterSpacing: 1.2,
              ),
            ),
            if (isActive) ...[
              const SizedBox(width: 6),
              Icon(
                _sortAsc
                    ? Icons.arrow_upward_rounded
                    : Icons.arrow_downward_rounded,
                size: 20,
                color: colors.accent,
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Date separator row ──
  Widget _buildDateSeparator(String dateLabel, ThemeConfig colors) {
    return Container(
      padding: const EdgeInsets.fromLTRB(32, 18, 32, 8),
      child: Row(
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(
              color: colors.accent,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 14),
          Text(
            dateLabel.toUpperCase(),
            style: GoogleFonts.outfit(
              fontSize: 20,
              fontWeight: FontWeight.w700,
              color: colors.accent,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Container(
              height: 1,
              color: colors.surfaceBorder,
            ),
          ),
        ],
      ),
    );
  }

  // ── Single table row ──
  Widget _buildTableRow(AuditEntry entry, bool isEven, ThemeConfig colors) {
    final actionColor = _actionColor(entry.action);

    String formattedTime;
    try {
      final dt = DateTime.parse(entry.timestamp).toLocal();
      formattedTime = DateFormat('HH:mm:ss').format(dt);
    } catch (_) {
      formattedTime = entry.timestamp;
    }

    String detailStr = '';
    try {
      if (entry.details.isNotEmpty && entry.details != '{}') {
        final parsed = const JsonDecoder().convert(entry.details);
        if (parsed is Map) {
          detailStr = parsed.entries
              .map((e) => '${e.key}: ${e.value}')
              .join('  ·  ');
        }
      }
    } catch (_) {}

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
      decoration: BoxDecoration(
        color: isEven
            ? Colors.white.withValues(alpha: 0.03)
            : Colors.transparent,
        border: Border(
          bottom: BorderSide(
              color: colors.surfaceBorder.withValues(alpha: 0.4), width: 0.5),
        ),
      ),
      child: Row(
        children: [
          // TIME
          SizedBox(
            width: 180,
            child: Text(
              formattedTime,
              style: GoogleFonts.dmMono(
                fontSize: 22,
                fontWeight: FontWeight.w600,
                color: Colors.white,
              ),
            ),
          ),

          // ACTION — color-coded badge
          SizedBox(
            width: 220,
            child: Row(
              children: [
                Icon(_actionIcon(entry.action),
                    size: 22, color: actionColor),
                const SizedBox(width: 10),
                Flexible(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 4),
                    decoration: BoxDecoration(
                      color: actionColor.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      _formatActionLabel(entry.action),
                      style: GoogleFonts.dmMono(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                        color: actionColor,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // USER
          SizedBox(
            width: 200,
            child: Text(
              entry.username,
              style: GoogleFonts.outfit(
                fontSize: 22,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // DEVICE
          SizedBox(
            width: 180,
            child: Text(
              entry.deviceId ?? '—',
              style: GoogleFonts.dmMono(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color:
                    entry.deviceId != null ? colors.accent : Colors.white38,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // DETAILS
          Expanded(
            child: Text(
              detailStr.isNotEmpty ? detailStr : '—',
              style: GoogleFonts.dmMono(
                fontSize: 19,
                color: detailStr.isNotEmpty ? Colors.white : Colors.white30,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),

          // IP
          SizedBox(
            width: 140,
            child: Text(
              entry.ipAddress ?? '—',
              style: GoogleFonts.dmMono(
                fontSize: 18,
                color: Colors.white54,
              ),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  String _formatActionLabel(String action) {
    return action
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isNotEmpty
            ? '${w[0].toUpperCase()}${w.substring(1)}'
            : w)
        .join(' ');
  }

  Color _actionColor(String action) {
    switch (action) {
      case 'login':
        return const Color(0xFF3B82F6);
      case 'write_register':
        return Colors.amber;
      case 'electronic_signature':
        return Colors.deepPurple;
      case 'create_user':
        return Colors.teal;
      case 'emergency_stop':
        return Colors.redAccent;
      case 'add_device':
        return const Color(0xFF22C55E);
      case 'remove_device':
        return const Color(0xFFF97316);
      default:
        return Colors.grey;
    }
  }

  IconData _actionIcon(String action) {
    switch (action) {
      case 'login':
        return Icons.login_rounded;
      case 'write_register':
        return Icons.edit_rounded;
      case 'electronic_signature':
        return Icons.verified_user_rounded;
      case 'create_user':
        return Icons.person_add_rounded;
      case 'emergency_stop':
        return Icons.dangerous_rounded;
      case 'add_device':
        return Icons.add_circle_rounded;
      case 'remove_device':
        return Icons.remove_circle_rounded;
      default:
        return Icons.event_note_rounded;
    }
  }
}
