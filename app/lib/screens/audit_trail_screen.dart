import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../config/dashboard_config.dart';
import '../config/hmi_theme_engine.dart';
import '../services/auth_service.dart';

/// Audit trail screen — 21 CFR Part 11 compliance.
///
/// Shows all user actions logged by the server:
/// login, write_register, emergency_stop, create_user, etc.
class AuditTrailScreen extends StatefulWidget {
  final AuthService authService;

  const AuditTrailScreen({super.key, required this.authService});

  @override
  State<AuditTrailScreen> createState() => _AuditTrailScreenState();
}

class _AuditTrailScreenState extends State<AuditTrailScreen> {
  List<AuditEntry> _entries = [];
  bool _isLoading = true;
  String? _filterAction;

  static const _actionFilters = [
    null, // "All"
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
              Icon(Icons.history_edu_rounded, color: colors.accent, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'Audit Trail',
                  style: GoogleFonts.outfit(
                    fontSize: 18,
                    fontWeight: FontWeight.w600,
                    color: colors.textPrimary,
                  ),
                ),
              ),
              // Refresh button
              IconButton(
                icon: Icon(Icons.refresh_rounded,
                    color: colors.textSecondary, size: 20),
                onPressed: _loadAudit,
                tooltip: 'Refresh',
              ),
            ],
          ),
        ),

        // ── Filter chips ──
        SizedBox(
          height: 40,
          child: ListView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            children: _actionFilters.map((filter) {
              final isSelected = _filterAction == filter;
              final label = filter ?? 'All';
              return Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  selected: isSelected,
                  label: Text(
                    _formatActionLabel(label),
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                      color: isSelected ? colors.background : colors.textSecondary,
                    ),
                  ),
                  selectedColor: colors.accent,
                  backgroundColor: colors.surface,
                  side: BorderSide(
                    color: isSelected ? colors.accent : colors.surfaceBorder,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  showCheckmark: false,
                  onSelected: (_) {
                    setState(() => _filterAction = filter);
                    _loadAudit();
                  },
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 8),

        // ── Entries ──
        Expanded(
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : _entries.isEmpty
                  ? Center(
                      child: Text(
                        'No audit entries',
                        style: GoogleFonts.outfit(color: colors.textMuted),
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _loadAudit,
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: _entries.length,
                        itemBuilder: (context, index) =>
                            _buildEntry(_entries[index], colors),
                      ),
                    ),
        ),
      ],
    );
  }

  Widget _buildEntry(AuditEntry entry, ThemeConfig colors) {
    final actionColor = _actionColor(entry.action);
    final icon = _actionIcon(entry.action);

    // Try to parse timestamp
    String formattedTime;
    try {
      final dt = DateTime.parse(entry.timestamp).toLocal();
      formattedTime = DateFormat('MMM dd, HH:mm:ss').format(dt);
    } catch (_) {
      formattedTime = entry.timestamp;
    }

    // Parse details JSON
    Map<String, dynamic> details = {};
    try {
      details = Map<String, dynamic>.from(
        (entry.details.isNotEmpty && entry.details != '{}')
            ? _tryParseJson(entry.details)
            : {},
      );
    } catch (_) {}

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colors.surfaceBorder),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Action icon
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: actionColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(icon, color: actionColor, size: 18),
            ),
            const SizedBox(width: 12),

            // Content
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Action + user
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: actionColor.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Text(
                          _formatActionLabel(entry.action),
                          style: GoogleFonts.dmMono(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: actionColor,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        entry.username,
                        style: GoogleFonts.outfit(
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          color: colors.textPrimary,
                        ),
                      ),
                      if (entry.deviceId != null) ...[
                        const SizedBox(width: 6),
                        Icon(Icons.arrow_forward,
                            size: 12, color: colors.textMuted),
                        const SizedBox(width: 4),
                        Text(
                          entry.deviceId!,
                          style: GoogleFonts.dmMono(
                            fontSize: 11,
                            color: colors.accent,
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),

                  // Details
                  if (details.isNotEmpty)
                    Text(
                      details.entries
                          .map((e) => '${e.key}: ${e.value}')
                          .join(', '),
                      style: GoogleFonts.dmMono(
                        fontSize: 11,
                        color: colors.textSecondary,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),

                  const SizedBox(height: 4),

                  // Timestamp
                  Text(
                    formattedTime,
                    style: GoogleFonts.dmMono(
                      fontSize: 10,
                      color: colors.textMuted,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  dynamic _tryParseJson(String s) {
    try {
      return _parseSimpleJson(s);
    } catch (_) {
      return {};
    }
  }

  dynamic _parseSimpleJson(String s) {
    // Use dart:convert
    return const JsonDecoder().convert(s);
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
