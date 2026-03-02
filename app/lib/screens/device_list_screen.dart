import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/plc_device.dart';
import '../services/api_service.dart';
import '../theme/hmi_colors.dart';

/// Phase 6: Device List & Management Screen
///
/// Shows all connected PLCs with real connection status.
/// Supports: discover, add, remove devices at runtime.
class DeviceListScreen extends StatefulWidget {
  final ApiService api;
  final void Function(PlcDevice device)? onDeviceTap;
  /// When false, hides add/remove/scan buttons (viewer role).
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

class _DeviceListScreenState extends State<DeviceListScreen> {
  List<PlcDevice> _devices = [];
  List<Map<String, dynamic>> _discovered = [];
  bool _loading = true;
  bool _scanning = false;

  @override
  void initState() {
    super.initState();
    _loadDevices();
  }

  Future<void> _loadDevices() async {
    setState(() => _loading = true);
    try {
      final devices = await widget.api.getDevices();
      setState(() {
        _devices = devices;
        _loading = false;
      });
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _scanNetwork() async {
    setState(() => _scanning = true);
    final found = await widget.api.discoverDevices();
    setState(() {
      _discovered = found;
      _scanning = false;
    });

    if (found.isEmpty && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No new devices found on network')),
      );
    }
  }

  Future<void> _removeDevice(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('Remove $id?'),
        content: const Text('This will stop polling and remove the device.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Remove'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      final ok = await widget.api.removeDevice(id);
      if (ok) {
        _loadDevices();
      }
    }
  }

  Future<void> _showAddDeviceDialog({String? prefillAddress}) async {
    final idCtrl = TextEditingController();
    final nameCtrl = TextEditingController();
    final addrCtrl = TextEditingController(text: prefillAddress ?? '');
    String selectedProtocol = 'modbus';

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
              style: FilledButton.styleFrom(
                backgroundColor: HmiColors.accent,
              ),
              onPressed: () => Navigator.pop(ctx, true),
              child: Text('Add Device',
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
        _loadDevices();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Device "${device.name}" added!')),
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
    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                const Icon(Icons.devices_other_rounded,
                    color: HmiColors.accent, size: 28),
                const SizedBox(width: 10),
                Text('PLC Devices',
                    style: GoogleFonts.outfit(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: HmiColors.textPrimary)),
                const Spacer(),
                // Scan button (operator/admin only)
                if (widget.canManage)
                  _scanning
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : IconButton(
                          icon: const Icon(Icons.radar_rounded),
                          tooltip: 'Scan Network',
                          onPressed: _scanNetwork,
                        ),
                // Refresh
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'Refresh',
                  onPressed: _loadDevices,
                ),
                // Add manually (operator/admin only)
                if (widget.canManage)
                  IconButton(
                    icon: const Icon(Icons.add_circle_outline_rounded),
                    tooltip: 'Add Device',
                    onPressed: () => _showAddDeviceDialog(),
                  ),
              ],
            ),
          ),

          const Divider(height: 1),

          // ── Discovered devices (from scan) ──
          if (_discovered.isNotEmpty) ...[
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 4),
              child: Text('Discovered on Network',
                  style: GoogleFonts.outfit(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: HmiColors.healthy)),
            ),
            SizedBox(
              height: 64,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: _discovered.length,
                itemBuilder: (ctx, i) {
                  final d = _discovered[i];
                  final addr = '${d['address']}:${d['port']}';
                  final alreadyAdded =
                      _devices.any((dev) => dev.address == addr);
                  return Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: ActionChip(
                      avatar: Icon(
                        alreadyAdded
                            ? Icons.check_circle
                            : Icons.add_circle_outline,
                        size: 18,
                        color: alreadyAdded ? Colors.green : null,
                      ),
                      label: Text(addr),
                      onPressed: alreadyAdded
                          ? null
                          : () =>
                              _showAddDeviceDialog(prefillAddress: addr),
                    ),
                  );
                },
              ),
            ),
            const Divider(height: 1),
          ],

          // ── Device list ──
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _devices.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.precision_manufacturing_outlined,
                                size: 64, color: HmiColors.textMuted),
                            const SizedBox(height: 12),
                            Text('No devices connected',
                                style: GoogleFonts.outfit(
                                    fontSize: 16,
                                    color: HmiColors.textSecondary)),
                            const SizedBox(height: 8),
                            FilledButton.tonal(
                              onPressed: _scanNetwork,
                              child: const Text('Scan Network'),
                            ),
                          ],
                        ),
                      )
                    : RefreshIndicator(
                        onRefresh: _loadDevices,
                        child: ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: _devices.length,
                          itemBuilder: (ctx, i) =>
                              _DeviceCard(
                                device: _devices[i],
                                onTap: () =>
                                    widget.onDeviceTap?.call(_devices[i]),
                                onRemove: widget.canManage
                                    ? () => _removeDevice(_devices[i].id)
                                    : null,
                              ),
                        ),
                      ),
          ),
        ],
      ),
    );
  }
}

// ── Device Card ─────────────────────────────────────────────────

class _DeviceCard extends StatelessWidget {
  final PlcDevice device;
  final VoidCallback? onTap;
  final VoidCallback? onRemove;

  const _DeviceCard({required this.device, this.onTap, this.onRemove});

  @override
  Widget build(BuildContext context) {
    final connected = device.isConnected;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: HmiColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: HmiColors.surfaceBorder),
      ),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              // Status indicator
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: (connected ? HmiColors.healthy : HmiColors.danger)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  connected
                      ? Icons.check_circle_rounded
                      : Icons.error_rounded,
                  color: connected ? HmiColors.healthy : HmiColors.danger,
                ),
              ),
              const SizedBox(width: 14),

              // Info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      device.name,
                      style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.w600,
                          color: HmiColors.textPrimary),
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 8,
                      runSpacing: 4,
                      children: [
                        _InfoChip(
                          icon: Icons.tag,
                          label: device.id,
                        ),
                        _InfoChip(
                          icon: Icons.lan_rounded,
                          label: device.address,
                        ),
                        _ProtocolBadge(protocol: device.protocol),
                      ],
                    ),
                  ],
                ),
              ),

              // Status text + remove
              Column(
                children: [
                  Text(
                    connected ? 'ONLINE' : 'OFFLINE',
                    style: GoogleFonts.dmMono(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: connected ? HmiColors.healthy : HmiColors.danger,
                    ),
                  ),
                  const SizedBox(height: 4),
                  if (onRemove != null)
                    IconButton(
                      icon: const Icon(Icons.delete_outline_rounded, size: 20),
                      onPressed: onRemove,
                      tooltip: 'Remove device',
                      style: IconButton.styleFrom(
                        foregroundColor: Colors.red[300],
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoChip extends StatelessWidget {
  final IconData icon;
  final String label;

  const _InfoChip({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 13, color: Colors.grey[500]),
        const SizedBox(width: 3),
        Text(label,
            style: TextStyle(fontSize: 12, color: Colors.grey[400])),
      ],
    );
  }
}

/// Color-coded protocol badge — Modbus (blue), OPC UA (green), unknown (grey).
class _ProtocolBadge extends StatelessWidget {
  final String protocol;

  const _ProtocolBadge({required this.protocol});

  @override
  Widget build(BuildContext context) {
    final isOpcua = protocol.toLowerCase() == 'opcua';
    final color = isOpcua ? Colors.teal : Colors.blue;
    final label = isOpcua ? 'OPC UA' : protocol.toUpperCase();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w700,
          color: color,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
