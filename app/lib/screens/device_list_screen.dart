import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/plc_device.dart';
import '../services/api_service.dart';
import '../theme/hmi_colors.dart';

// ── Unified list entry (registered device OR discovered scan result) ──────────
class _NetworkEntry {
  final String name;
  final String address;
  final String protocol;
  final bool isRegistered; // exists in server registry
  final bool isConnected;
  final String? deviceId; // null for unregistered discovered devices
  final String? serverName; // OPC UA friendly name

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
  String? _connectingKey; // address being connected right now

  late final AnimationController _radarCtrl;

  @override
  void initState() {
    super.initState();
    _radarCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
    _loadDevices(thenScan: true); // auto-scan on open, just like WiFi
  }

  @override
  void dispose() {
    _radarCtrl.dispose();
    super.dispose();
  }

  // ── Data loading ─────────────────────────────────────────────────

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

  // ── Build a merged, sorted entry list ────────────────────────────

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

  // ── Actions ──────────────────────────────────────────────────────

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
    Navigator.pop(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: HmiColors.surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
        title: Text('Forget ${device.name}?',
            style: GoogleFonts.outfit(
                fontWeight: FontWeight.w600, color: HmiColors.textPrimary)),
        content: Text(
            'Removes this device from the list. You can add it again anytime.',
            style: GoogleFonts.outfit(
                fontSize: 13, color: HmiColors.textSecondary)),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel',
                style: GoogleFonts.outfit(color: HmiColors.textMuted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red[300]),
            child: Text('Forget',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await widget.api.removeDevice(device.id);
      await _loadDevices();
    }
  }

  // ── Bottom sheet for connected device info ─────────────────────

  void _showDeviceInfo(PlcDevice device) {
    final proto = device.protocol.toLowerCase();
    final protoColor = proto == 'opcua' ? Colors.teal : Colors.blue;

    showModalBottomSheet(
      context: context,
      backgroundColor: HmiColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.fromLTRB(24, 16, 24, 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            Row(
              children: [
                Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: protoColor.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: protoColor.withValues(alpha: 0.4), width: 1.5),
                  ),
                  child: Icon(Icons.memory_rounded, color: protoColor, size: 24),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        device.name,
                        style: GoogleFonts.outfit(
                          fontSize: 17,
                          fontWeight: FontWeight.w700,
                          color: HmiColors.textPrimary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Row(children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: HmiColors.healthy,
                          ),
                        ),
                        const SizedBox(width: 5),
                        Text('CONNECTED',
                            style: GoogleFonts.jetBrainsMono(
                                fontSize: 10,
                                fontWeight: FontWeight.w700,
                                color: HmiColors.healthy,
                                letterSpacing: 1.2)),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 20),
            const Divider(color: HmiColors.surfaceBorder),
            const SizedBox(height: 16),
            _InfoRow(label: 'ID', value: device.id),
            const SizedBox(height: 8),
            _InfoRow(label: 'ADDRESS', value: device.address),
            const SizedBox(height: 8),
            _InfoRow(
                label: 'PROTOCOL',
                value: proto == 'opcua' ? 'OPC UA' : 'Modbus TCP'),
            const SizedBox(height: 28),
            if (widget.canManage) ...[
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _disconnectDevice(device),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                        color: Colors.orange.withValues(alpha: 0.6), width: 1.5),
                    foregroundColor: Colors.orange[300],
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.link_off_rounded, size: 18),
                  label: Text('Disconnect',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => _removeDevice(device),
                  style: OutlinedButton.styleFrom(
                    side: BorderSide(
                        color: Colors.red.withValues(alpha: 0.5), width: 1.5),
                    foregroundColor: Colors.red[300],
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.delete_outline_rounded, size: 18),
                  label: Text('Forget Device',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
            if (widget.onDeviceTap != null) ...[
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () {
                    Navigator.pop(ctx);
                    widget.onDeviceTap?.call(device);
                  },
                  style: FilledButton.styleFrom(
                    backgroundColor: HmiColors.accent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.bar_chart_rounded, size: 18),
                  label: Text('View Live Data',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ── Add device dialog ────────────────────────────────────────────

  Future<void> _showAddDeviceDialog({
    String? prefillAddress,
    String? prefillName,
    String? prefillProtocol,
    bool autoConnect = false,
  }) async {
    final idCtrl = TextEditingController();
    final nameCtrl = TextEditingController(text: prefillName ?? '');
    final addrCtrl = TextEditingController(text: prefillAddress ?? '');
    String selectedProtocol = prefillProtocol ?? 'modbus';

    final inputDecoration = InputDecoration(
      filled: true,
      fillColor: HmiColors.void_,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: HmiColors.surfaceBorder),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: BorderSide(color: HmiColors.surfaceBorder),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(8),
        borderSide: const BorderSide(color: HmiColors.accent, width: 1.5),
      ),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      labelStyle: GoogleFonts.outfit(fontSize: 13, color: HmiColors.textMuted),
      hintStyle: GoogleFonts.outfit(fontSize: 12, color: HmiColors.textMuted),
    );

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          backgroundColor: HmiColors.surface,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          title: Row(
            children: [
              const Icon(Icons.add_circle_outline_rounded,
                  size: 20, color: HmiColors.accent),
              const SizedBox(width: 8),
              Text('Add PLC Device',
                  style: GoogleFonts.outfit(
                      fontSize: 17,
                      fontWeight: FontWeight.w600,
                      color: HmiColors.textPrimary)),
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
                      fontSize: 13, color: HmiColors.textPrimary),
                  decoration: inputDecoration.copyWith(
                    labelText: 'Device ID',
                    hintText: 'e.g. plc-04',
                    prefixIcon: const Icon(Icons.tag,
                        size: 18, color: HmiColors.textMuted),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: nameCtrl,
                  style: GoogleFonts.outfit(
                      fontSize: 13, color: HmiColors.textPrimary),
                  decoration: inputDecoration.copyWith(
                    labelText: 'Device Name',
                    hintText: 'e.g. Mixing Tank',
                    prefixIcon: const Icon(Icons.label_outline_rounded,
                        size: 18, color: HmiColors.textMuted),
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: addrCtrl,
                  style: GoogleFonts.dmMono(
                      fontSize: 13, color: HmiColors.textPrimary),
                  decoration: inputDecoration.copyWith(
                    labelText: 'Address',
                    hintText: selectedProtocol == 'opcua'
                        ? 'opc.tcp://127.0.0.1:4840/'
                        : '127.0.0.1:5022',
                    prefixIcon: const Icon(Icons.lan_rounded,
                        size: 18, color: HmiColors.textMuted),
                  ),
                ),
                const SizedBox(height: 16),
                Text('Protocol',
                    style: GoogleFonts.outfit(
                        fontSize: 12, color: HmiColors.textMuted)),
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: GestureDetector(
                        onTap: () =>
                            setDialogState(() => selectedProtocol = 'modbus'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: selectedProtocol == 'modbus'
                                ? Colors.blue.withValues(alpha: 0.15)
                                : Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: selectedProtocol == 'modbus'
                                  ? Colors.blue.withValues(alpha: 0.5)
                                  : HmiColors.surfaceBorder,
                            ),
                          ),
                          child: Center(
                            child: Text('MODBUS',
                                style: GoogleFonts.dmMono(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: selectedProtocol == 'modbus'
                                      ? Colors.blue
                                      : HmiColors.textMuted,
                                )),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: GestureDetector(
                        onTap: () =>
                            setDialogState(() => selectedProtocol = 'opcua'),
                        child: Container(
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          decoration: BoxDecoration(
                            color: selectedProtocol == 'opcua'
                                ? Colors.teal.withValues(alpha: 0.15)
                                : Colors.white.withValues(alpha: 0.05),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: selectedProtocol == 'opcua'
                                  ? Colors.teal.withValues(alpha: 0.5)
                                  : HmiColors.surfaceBorder,
                            ),
                          ),
                          child: Center(
                            child: Text('OPC UA',
                                style: GoogleFonts.dmMono(
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                  color: selectedProtocol == 'opcua'
                                      ? Colors.teal
                                      : HmiColors.textMuted,
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
                  style: GoogleFonts.outfit(color: HmiColors.textMuted)),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: HmiColors.accent),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Connect',
                  style: GoogleFonts.outfit(
                      fontWeight: FontWeight.w600, color: Colors.white)),
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

  // ── Build ────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final entries = _entries;
    final connected = entries.where((e) => e.isConnected).toList();
    final available = entries.where((e) => !e.isConnected).toList();

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          if (_scanning) _ScanProgressBar(),
          Expanded(
            child: _loading && entries.isEmpty
                ? const Center(child: CircularProgressIndicator())
                : entries.isEmpty
                    ? _buildEmptyState()
                    : ListView(
                        padding: const EdgeInsets.only(bottom: 24),
                        children: [
                          if (connected.isNotEmpty) ...[
                            _SectionHeader(
                                label: 'CONNECTED',
                                count: connected.length,
                                color: HmiColors.healthy),
                            ...connected.map((e) => _buildNetworkRow(e)),
                          ],
                          if (available.isNotEmpty) ...[
                            _SectionHeader(
                                label: 'AVAILABLE',
                                count: available.length,
                                color: HmiColors.textMuted),
                            ...available.map((e) => _buildNetworkRow(e)),
                          ],
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 8),
      child: Row(
        children: [
          const Icon(Icons.wifi_rounded, color: HmiColors.accent, size: 28),
          const SizedBox(width: 10),
          Text('PLC Networks',
              style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: HmiColors.textPrimary)),
          const Spacer(),
          if (widget.canManage)
            _scanning
                ? Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: RotationTransition(
                      turns: _radarCtrl,
                      child: const Icon(Icons.radar_rounded,
                          color: HmiColors.accent, size: 22),
                    ),
                  )
                : IconButton(
                    icon: const Icon(Icons.radar_rounded),
                    color: HmiColors.accent,
                    tooltip: 'Scan for PLCs',
                    onPressed: _scanNetwork,
                  ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            color: HmiColors.textMuted,
            tooltip: 'Refresh',
            onPressed: () => _loadDevices(),
          ),
          if (widget.canManage)
            IconButton(
              icon: const Icon(Icons.add_rounded),
              color: HmiColors.textMuted,
              tooltip: 'Add manually',
              onPressed: () => _showAddDeviceDialog(),
            ),
        ],
      ),
    );
  }

  Widget _buildNetworkRow(_NetworkEntry entry) {
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
              : null, // CONNECT button handles this
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 13),
        child: Row(
          children: [
            // Signal bars
            SizedBox(
              width: 32,
              height: 32,
              child: Center(
                child: _SignalBars(
                  bars: signalBars,
                  color: entry.isConnected ? protoColor : Colors.white38,
                ),
              ),
            ),
            const SizedBox(width: 14),

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
                            fontSize: 15,
                            fontWeight: entry.isConnected
                                ? FontWeight.w600
                                : FontWeight.w400,
                            color: entry.isConnected
                                ? HmiColors.textPrimary
                                : HmiColors.textSecondary,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if (entry.isConnected) ...[
                        const SizedBox(width: 6),
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: HmiColors.healthy,
                            boxShadow: [
                              BoxShadow(
                                color: HmiColors.healthy.withValues(alpha: 0.6),
                                blurRadius: 5,
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          entry.address,
                          style: GoogleFonts.jetBrainsMono(
                            fontSize: 11,
                            color: HmiColors.textMuted,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      _ProtocolBadge(protocol: entry.protocol),
                      if (!entry.isRegistered) ...[
                        const SizedBox(width: 5),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 5, vertical: 1),
                          decoration: BoxDecoration(
                            color: Colors.amber.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(
                                color: Colors.amber.withValues(alpha: 0.4)),
                          ),
                          child: Text('NEW',
                              style: GoogleFonts.dmMono(
                                  fontSize: 9,
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
            const SizedBox(width: 8),

            // Right-side action
            if (isConnecting)
              SizedBox(
                width: 80,
                child: Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: protoColor,
                    ),
                  ),
                ),
              )
            else if (entry.isConnected)
              const Icon(Icons.info_outline_rounded,
                  size: 20, color: HmiColors.textMuted)
            else
              SizedBox(
                height: 34,
                child: FilledButton(
                  onPressed: () => _connectEntry(entry),
                  style: FilledButton.styleFrom(
                    backgroundColor: HmiColors.accent.withValues(alpha: 0.15),
                    foregroundColor: HmiColors.accent,
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8)),
                    elevation: 0,
                  ),
                  child: Text(
                    'CONNECT',
                    style: GoogleFonts.dmMono(
                      fontSize: 11,
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

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.wifi_off_rounded, size: 72, color: Colors.white12),
          const SizedBox(height: 16),
          Text('No PLCs found',
              style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: HmiColors.textMuted)),
          const SizedBox(height: 8),
          Text('Tap scan to search the network',
              style: GoogleFonts.outfit(
                  fontSize: 13, color: HmiColors.textMuted)),
          const SizedBox(height: 24),
          if (widget.canManage)
            FilledButton.icon(
              onPressed: _scanNetwork,
              style: FilledButton.styleFrom(
                backgroundColor: HmiColors.accent,
                padding: const EdgeInsets.symmetric(
                    horizontal: 24, vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
              icon: const Icon(Icons.radar_rounded, size: 18),
              label: Text('Scan Network',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w600)),
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
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 4),
      child: Row(
        children: [
          Text(
            label,
            style: GoogleFonts.dmMono(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: color,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(width: 8),
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Text('$count',
                style: GoogleFonts.dmMono(
                    fontSize: 10,
                    fontWeight: FontWeight.w700,
                    color: color)),
          ),
          const SizedBox(width: 12),
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
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const LinearProgressIndicator(
          backgroundColor: Colors.transparent,
          valueColor: AlwaysStoppedAnimation<Color>(HmiColors.accent),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
          child: Text(
            'Scanning network for PLCs…',
            style: GoogleFonts.dmMono(
                fontSize: 10,
                color: HmiColors.textMuted,
                letterSpacing: 0.5),
          ),
        ),
      ],
    );
  }
}

// ── Signal bars (like cell/WiFi strength indicator) ────────────────────────

class _SignalBars extends StatelessWidget {
  final int bars; // 1 – 4
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
          width: 4,
          height: 6.0 + i * 3.5,
          margin: const EdgeInsets.only(right: 2),
          decoration: BoxDecoration(
            color: filled ? color : color.withValues(alpha: 0.18),
            borderRadius:
                const BorderRadius.vertical(top: Radius.circular(1.5)),
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

  const _InfoRow({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 90,
          child: Text(label,
              style: GoogleFonts.dmMono(
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  color: HmiColors.textMuted,
                  letterSpacing: 1)),
        ),
        Expanded(
          child: Text(value,
              style: GoogleFonts.dmMono(
                  fontSize: 12, color: HmiColors.textPrimary)),
        ),
      ],
    );
  }
}

// ── Protocol badge ─────────────────────────────────────────────────────────

class _ProtocolBadge extends StatelessWidget {
  final String protocol;

  const _ProtocolBadge({required this.protocol});

  @override
  Widget build(BuildContext context) {
    final isOpcua = protocol.toLowerCase() == 'opcua';
    final color = isOpcua ? Colors.teal : Colors.blue;
    final label = isOpcua ? 'OPC UA' : protocol.toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(4),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(label,
          style: TextStyle(
            fontSize: 9,
            fontWeight: FontWeight.w700,
            color: color,
            letterSpacing: 0.5,
            fontFamily: 'DM Mono',
          )),
    );
  }
}
