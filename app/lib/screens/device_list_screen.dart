import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/dashboard_config.dart';
import '../config/hmi_theme_engine.dart';
import '../models/plc_device.dart';
import '../services/api_service.dart';

// ── Unified list entry (registered device OR discovered scan result) ──────────
class _NetworkEntry {
  final String name;
  final String address;
  final String protocol;
  final bool isRegistered;
  final bool isConnected;
  final String? deviceId;
  final String? serverName;

  const _NetworkEntry({
    required this.name,
    required this.address,
    required this.protocol,
    required this.isRegistered,
    required this.isConnected,
    this.deviceId,
    this.serverName,
  });
}

// ── Screen ────────────────────────────────────────────────────────────────────

class DeviceListScreen extends StatefulWidget {
  final ApiService api;
  final void Function(PlcDevice device)? onDeviceTap;
  final bool canManage;

  const DeviceListScreen({
    super.key,
    required this.api,
    this.onDeviceTap,
    this.canManage = false,
  });

  @override
  State<DeviceListScreen> createState() => _DeviceListScreenState();
}

class _DeviceListScreenState extends State<DeviceListScreen>
    with SingleTickerProviderStateMixin {
  List<PlcDevice> _devices = [];
  List<Map<String, dynamic>> _discovered = [];
  bool _loading = true;
  bool _scanning = false;
  String? _connectingKey;

  late final AnimationController _radarCtrl;

  @override
  void initState() {
    super.initState();
    _radarCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _loadDevices(thenScan: true);
  }

  @override
  void dispose() {
    _radarCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadDevices({bool thenScan = false}) async {
    setState(() => _loading = true);
    try {
      final devices = await widget.api.getDevices();
      setState(() {
        _devices = devices;
        _loading = false;
      });
    } catch (_) {
      setState(() => _loading = false);
    }
    if (thenScan) _scanNetwork();
  }

  Future<void> _scanNetwork() async {
    if (_scanning) return;
    setState(() => _scanning = true);
    final found = await widget.api.discoverDevices();
    setState(() {
      _discovered = found;
      _scanning = false;
    });
  }

  List<_NetworkEntry> get _entries {
    final entries = <_NetworkEntry>[];
    final registeredAddrs = <String>{};

    for (final d in _devices) {
      registeredAddrs.add(d.address);
      entries.add(_NetworkEntry(
        name: d.name,
        address: d.address,
        protocol: d.protocol,
        isRegistered: true,
        isConnected: d.isConnected,
        deviceId: d.id,
      ));
    }

    for (final d in _discovered) {
      final proto = (d['protocol'] as String? ?? 'modbus').toLowerCase();
      final endpointUrl = d['endpoint_url'] as String?;
      final rawAddr = proto == 'opcua' && endpointUrl != null
          ? endpointUrl
          : '${d['address']}:${d['port']}';
      if (registeredAddrs.contains(rawAddr)) continue;
      entries.add(_NetworkEntry(
        name: d['server_name'] as String? ?? rawAddr,
        address: rawAddr,
        protocol: proto,
        isRegistered: false,
        isConnected: false,
        serverName: d['server_name'] as String?,
      ));
    }

    entries.sort((a, b) {
      if (a.isConnected != b.isConnected) return a.isConnected ? -1 : 1;
      return a.name.compareTo(b.name);
    });

    return entries;
  }

  Future<void> _connectEntry(_NetworkEntry entry) async {
    setState(() => _connectingKey = entry.address);

    if (entry.isRegistered && entry.deviceId != null) {
      await widget.api.connectDevice(entry.deviceId!);
      await _loadDevices();
    } else {
      await _showAddDeviceDialog(
        prefillAddress: entry.address,
        prefillName: entry.name,
        prefillProtocol: entry.protocol,
        autoConnect: true,
      );
    }

    if (mounted) setState(() => _connectingKey = null);
  }

  Future<void> _disconnectDevice(PlcDevice device) async {
    Navigator.pop(context);
    await widget.api.disconnectDevice(device.id);
    await _loadDevices();
  }

  Future<void> _removeDevice(PlcDevice device) async {
    final colors = ActiveTheme.of(context);
    Navigator.pop(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: colors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Forget ${device.name}?',
            style: GoogleFonts.outfit(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: colors.textPrimary)),
        content: Text(
            'Removes this device from the list. You can add it again anytime.',
            style: GoogleFonts.outfit(
                fontSize: 16, color: colors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.outfit(
                    fontSize: 16, color: colors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red[300]),
            child: Text('Forget',
                style: GoogleFonts.outfit(
                    fontSize: 16, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.api.removeDevice(device.id);
      await _loadDevices();
    }
  }

  void _showDeviceInfo(PlcDevice device) {
    final colors = ActiveTheme.of(context);
    final proto = device.protocol.toLowerCase();
    final protoColor = proto == 'opcua' ? Colors.teal : Colors.blue;

    showModalBottomSheet(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(28, 20, 28, 36),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 5,
                margin: const EdgeInsets.only(bottom: 24),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: protoColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: protoColor.withValues(alpha: 0.4), width: 1.5),
                  ),
                  child: Icon(Icons.memory_rounded,
                      color: protoColor, size: 28),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.name,
                        style: GoogleFonts.outfit(
                          fontSize: 22,
                          fontWeight: FontWeight.w700,
                          color: colors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(children: [
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors.healthy,
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text('CONNECTED',
                            style: GoogleFonts.jetBrainsMono(
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                                color: colors.healthy,
                                letterSpacing: 1.2)),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Divider(color: colors.surfaceBorder),
            const SizedBox(height: 20),
            _InfoRow(label: 'ID', value: device.id, colors: colors),
            const SizedBox(height: 12),
            _InfoRow(
                label: 'ADDRESS', value: device.address, colors: colors),
            const SizedBox(height: 12),
            _InfoRow(
                label: 'PROTOCOL',
                value: proto == 'opcua' ? 'OPC UA' : 'Modbus TCP',
                colors: colors),
            const SizedBox(height: 32),
            if (widget.canManage) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _disconnectDevice(device),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                        color: Colors.orange.withValues(alpha: 0.6),
                        width: 1.5),
                    foregroundColor: Colors.orange[300],
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    textStyle: GoogleFonts.outfit(fontSize: 16),
                  ),
                  icon: const Icon(Icons.link_off_rounded, size: 22),
                  label: Text('Disconnect',
                      style: GoogleFonts.outfit(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _removeDevice(device),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                        color: Colors.red.withValues(alpha: 0.5), width: 1.5),
                    foregroundColor: Colors.red[300],
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                    textStyle: GoogleFonts.outfit(fontSize: 16),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 22),
                  label: Text('Forget Device',
                      style: GoogleFonts.outfit(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
            if (widget.onDeviceTap != null) ...[
              const SizedBox(height: 12),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    widget.onDeviceTap?.call(device);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: colors.accent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.bar_chart_rounded, size: 22),
                  label: Text('View Live Data',
                      style: GoogleFonts.outfit(
                          fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _showAddDeviceDialog({
    String? prefillAddress,
    String? prefillName,
    String? prefillProtocol,
    bool autoConnect = false,
  }) async {
    final colors = ActiveTheme.of(context);
    final idCtrl = TextEditingController();
    final nameCtrl = TextEditingController(text: prefillName ?? '');
    final addrCtrl = TextEditingController(text: prefillAddress ?? '');
    String selectedProtocol = prefillProtocol ?? 'modbus';

    final inputDecoration = InputDecoration(
      filled: true,
      fillColor: colors.background,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colors.surfaceBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colors.surfaceBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(10),
        borderSide: BorderSide(color: colors.accent, width: 1.5),
      ),
      contentPadding:
          const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      labelStyle: GoogleFonts.outfit(fontSize: 15, color: colors.textMuted),
      hintStyle: GoogleFonts.outfit(fontSize: 14, color: colors.textMuted),
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: colors.surface,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14)),
          title: Row(
            children: [
              Icon(Icons.add_circle_outline_rounded,
                  size: 24, color: colors.accent),
              const SizedBox(width: 10),
              Text('Add PLC Device',
                  style: GoogleFonts.outfit(
                      fontSize: 20,
                      fontWeight: FontWeight.w600,
                      color: colors.textPrimary)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: idCtrl,
                  style: GoogleFonts.dmMono(
                      fontSize: 15, color: colors.textPrimary),
                  decoration: inputDecoration.copyWith(
                    labelText: 'Device ID',
                    hintText: 'e.g. plc-04',
                    prefixIcon: Icon(Icons.tag,
                        size: 20, color: colors.textMuted),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: nameCtrl,
                  style: GoogleFonts.outfit(
                      fontSize: 15, color: colors.textPrimary),
                  decoration: inputDecoration.copyWith(
                    labelText: 'Device Name',
                    hintText: 'e.g. Mixing Tank',
                    prefixIcon: Icon(Icons.label_outline_rounded,
                        size: 20, color: colors.textMuted),
                  ),
                ),
                const SizedBox(height: 14),
                TextField(
                  controller: addrCtrl,
                  style: GoogleFonts.dmMono(
                      fontSize: 15, color: colors.textPrimary),
                  decoration: inputDecoration.copyWith(
                    labelText: 'Address',
                    hintText: selectedProtocol == 'opcua'
                        ? 'opc.tcp://127.0.0.1:4840/'
                        : '127.0.0.1:5022',
                    prefixIcon: Icon(Icons.lan_rounded,
                        size: 20, color: colors.textMuted),
                  ),
                ),
                const SizedBox(height: 18),
                Text('Protocol',
                    style: GoogleFonts.outfit(
                        fontSize: 14, color: colors.textMuted)),
                const SizedBox(height: 10),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setDialogState(
                            () => selectedProtocol = 'modbus'),
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: selectedProtocol == 'modbus'
                                ? Colors.blue.withValues(alpha: 0.15)
                                : Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selectedProtocol == 'modbus'
                                  ? Colors.blue.withValues(alpha: 0.5)
                                  : colors.surfaceBorder,
                            ),
                          ),
                          child: Center(
                            child: Text('MODBUS',
                                style: GoogleFonts.dmMono(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: selectedProtocol == 'modbus'
                                      ? Colors.blue
                                      : colors.textMuted,
                                )),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GestureDetector(
                        onTap: () => setDialogState(
                            () => selectedProtocol = 'opcua'),
                        child: Container(
                          padding:
                              const EdgeInsets.symmetric(vertical: 12),
                          decoration: BoxDecoration(
                            color: selectedProtocol == 'opcua'
                                ? Colors.teal.withValues(alpha: 0.15)
                                : Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: selectedProtocol == 'opcua'
                                  ? Colors.teal.withValues(alpha: 0.5)
                                  : colors.surfaceBorder,
                            ),
                          ),
                          child: Center(
                            child: Text('OPC UA',
                                style: GoogleFonts.dmMono(
                                  fontSize: 15,
                                  fontWeight: FontWeight.w600,
                                  color: selectedProtocol == 'opcua'
                                      ? Colors.teal
                                      : colors.textMuted,
                                )),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text('Cancel',
                  style: GoogleFonts.outfit(
                      fontSize: 16, color: colors.textMuted)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: colors.accent),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Connect',
                  style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    if (result == true &&
        idCtrl.text.isNotEmpty &&
        nameCtrl.text.isNotEmpty &&
        addrCtrl.text.isNotEmpty) {
      final device = await widget.api.addDevice(
        id: idCtrl.text.trim(),
        name: nameCtrl.text.trim(),
        address: addrCtrl.text.trim(),
        protocol: selectedProtocol,
      );
      if (device != null) {
        if (autoConnect) await widget.api.connectDevice(device.id);
        await _loadDevices();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('"${device.name}" added!')),
          );
        }
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Failed to add device')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = ActiveTheme.of(context);
    final entries = _entries;
    final connected = entries.where((e) => e.isConnected).toList();
    final available = entries.where((e) => !e.isConnected).toList();

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(colors),
          if (_scanning) _ScanProgressBar(colors: colors),
          Expanded(
            child: _loading && entries.isEmpty
                ? Center(
                    child:
                        CircularProgressIndicator(color: colors.accent))
                : entries.isEmpty
                    ? _buildEmptyState(colors)
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 24),
                        children: [
                          if (connected.isNotEmpty) ...[
                            _SectionHeader(
                                label: 'CONNECTED',
                                count: connected.length,
                                color: colors.healthy),
                            ...connected.map(
                                (e) => _buildNetworkRow(e, colors)),
                          ],
                          if (available.isNotEmpty) ...[
                            _SectionHeader(
                                label: 'AVAILABLE',
                                count: available.length,
                                color: colors.textMuted),
                            ...available.map(
                                (e) => _buildNetworkRow(e, colors)),
                          ],
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(ThemeConfig colors) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
      decoration: BoxDecoration(
        color: colors.surface,
        border: Border(
          bottom: BorderSide(color: colors.surfaceBorder, width: 1),
        ),
      ),
      child: Row(
        children: [
          Icon(Icons.wifi_rounded, color: colors.accent, size: 28),
          const SizedBox(width: 12),
          Text('PLC NETWORKS',
              style: GoogleFonts.outfit(
                  fontSize: 24,
                  fontWeight: FontWeight.w700,
                  color: colors.textPrimary,
                  letterSpacing: 2)),
          const Spacer(),
          if (widget.canManage)
            _scanning
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: RotationTransition(
                      turns: _radarCtrl,
                      child: Icon(Icons.radar_rounded,
                          color: colors.accent, size: 26),
                    ),
                  )
                : IconButton(
                    icon: Icon(Icons.radar_rounded,
                        size: 26, color: colors.accent),
                    tooltip: 'Scan for PLCs',
                    onPressed: _scanNetwork,
                  ),
          IconButton(
            icon: Icon(Icons.refresh_rounded,
                size: 24, color: colors.textSecondary),
            tooltip: 'Refresh',
            onPressed: () => _loadDevices(),
          ),
          if (widget.canManage)
            IconButton(
              icon: Icon(Icons.add_rounded,
                  size: 24, color: colors.textSecondary),
              tooltip: 'Add manually',
              onPressed: () => _showAddDeviceDialog(),
            ),
        ],
      ),
    );
  }

  Widget _buildNetworkRow(_NetworkEntry entry, ThemeConfig colors) {
    final proto = entry.protocol.toLowerCase();
    final protoColor = proto == 'opcua' ? Colors.teal : Colors.blue;
    final isConnecting = _connectingKey == entry.address;
    final signalBars = entry.isConnected ? 4 : (entry.isRegistered ? 1 : 2);

    return InkWell(
      onTap: isConnecting
          ? null
          : entry.isConnected
              ? () {
                  final device =
                      _devices.firstWhere((d) => d.id == entry.deviceId);
                  _showDeviceInfo(device);
                }
              : null,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        child: Row(
          children: [
            // Signal bars
            SizedBox(
              width: 40,
              height: 40,
              child: Center(
                child: _SignalBars(
                  bars: signalBars,
                  color: entry.isConnected ? protoColor : Colors.white38,
                ),
              ),
            ),
            const SizedBox(width: 16),

            // Name + address + badges
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          entry.name,
                          style: GoogleFonts.outfit(
                            fontSize: 20,
                            fontWeight: entry.isConnected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: entry.isConnected
                                ? colors.textPrimary
                                : colors.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (entry.isConnected) ...[
                        const SizedBox(width: 8),
                        Container(
                          width: 9,
                          height: 9,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: colors.healthy,
                            boxShadow: [
                              BoxShadow(
                                color: colors.healthy.withValues(alpha: 0.6),
                                blurRadius: 6,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          entry.address,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 14,
                            color: colors.textMuted,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      _ProtocolBadge(
                          protocol: entry.protocol, colors: colors),
                      if (!entry.isRegistered) ...[
                        const SizedBox(width: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(
                                color:
                                    Colors.amber.withValues(alpha: 0.4)),
                          ),
                          child: Text('NEW',
                              style: GoogleFonts.dmMono(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  color: Colors.amber,
                                  letterSpacing: 0.5)),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),

            // Right-side action
            if (isConnecting)
              SizedBox(
                width: 100,
                child: Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: protoColor,
                    ),
                  ),
                ),
              )
            else if (entry.isConnected)
              Icon(Icons.info_outline_rounded,
                  size: 24, color: colors.textMuted)
            else
              SizedBox(
                height: 42,
                child: FilledButton(
                  onPressed: () => _connectEntry(entry),
                  style: FilledButton.styleFrom(
                    backgroundColor:
                        colors.accent.withValues(alpha: 0.15),
                    foregroundColor: colors.accent,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                    elevation: 0,
                  ),
                  child: Text(
                    'CONNECT',
                    style: GoogleFonts.dmMono(
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeConfig colors) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded,
              size: 80, color: colors.textMuted),
          const SizedBox(height: 20),
          Text('No PLCs found',
              style: GoogleFonts.outfit(
                  fontSize: 24,
                  fontWeight: FontWeight.w600,
                  color: colors.textMuted)),
          const SizedBox(height: 10),
          Text('Tap scan to search the network',
              style: GoogleFonts.outfit(
                  fontSize: 16, color: colors.textMuted)),
          const SizedBox(height: 28),
          if (widget.canManage)
            FilledButton.icon(
              onPressed: _scanNetwork,
              style: FilledButton.styleFrom(
                backgroundColor: colors.accent,
                padding: const EdgeInsets.symmetric(
                    horizontal: 28, vertical: 16),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.radar_rounded, size: 22),
              label: Text('Scan Network',
                  style: GoogleFonts.outfit(
                      fontSize: 18, fontWeight: FontWeight.w600)),
            ),
        ],
      ),
    );
  }
}

// ── Section header ─────────────────────────────────────────────────────────

class _SectionHeader extends StatelessWidget {
  final String label;
  final int count;
  final Color color;

  const _SectionHeader(
      {required this.label, required this.count, required this.color});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 6),
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.dmMono(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(width: 10),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$count',
                style: GoogleFonts.dmMono(
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                    color: color)),
          ),
          const SizedBox(width: 14),
          Expanded(
              child: Divider(
                  color: color.withValues(alpha: 0.2), thickness: 1)),
        ],
      ),
    );
  }
}

// ── Scanning progress bar ──────────────────────────────────────────────────

class _ScanProgressBar extends StatelessWidget {
  final ThemeConfig colors;
  const _ScanProgressBar({required this.colors});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          backgroundColor: Colors.transparent,
          valueColor: AlwaysStoppedAnimation<Color>(colors.accent),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 6),
          child: Text(
            'Scanning network for PLCs…',
            style: GoogleFonts.dmMono(
                fontSize: 13,
                color: colors.textMuted,
                letterSpacing: 0.5),
          ),
        ),
      ],
    );
  }
}

// ── Signal bars (like cell/WiFi strength indicator) ────────────────────────

class _SignalBars extends StatelessWidget {
  final int bars;
  final Color color;

  const _SignalBars({required this.bars, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: List.generate(4, (i) {
        final filled = i < bars;
        return Container(
          width: 5,
          height: 8.0 + i * 5.0,
          margin: const EdgeInsets.only(right: 3),
          decoration: BoxDecoration(
            color: filled ? color : color.withValues(alpha: 0.18),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(2)),
          ),
        );
      }),
    );
  }
}

// ── Info row for bottom sheet ──────────────────────────────────────────────

class _InfoRow extends StatelessWidget {
  final String label;
  final String value;
  final ThemeConfig colors;

  const _InfoRow(
      {required this.label, required this.value, required this.colors});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 100,
          child: Text(label,
              style: GoogleFonts.dmMono(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: colors.textMuted,
                  letterSpacing: 1)),
        ),
        Expanded(
          child: Text(value,
              style: GoogleFonts.dmMono(
                  fontSize: 16, color: colors.textPrimary)),
        ),
      ],
    );
  }
}

// ── Protocol badge ─────────────────────────────────────────────────────────

class _ProtocolBadge extends StatelessWidget {
  final String protocol;
  final ThemeConfig colors;

  const _ProtocolBadge({required this.protocol, required this.colors});

  @override
  Widget build(BuildContext context) {
    final isOpcua = protocol.toLowerCase() == 'opcua';
    final color = isOpcua ? Colors.teal : Colors.blue;
    final label = isOpcua ? 'OPC UA' : protocol.toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Text(
        label,
        style: GoogleFonts.dmMono(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    );
  }
}
