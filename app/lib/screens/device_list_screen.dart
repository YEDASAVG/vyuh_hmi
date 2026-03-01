import 'package:flutter/material.dart';

import '../models/plc_device.dart';
import '../services/api_service.dart';

/// Phase 6: Device List & Management Screen
///
/// Shows all connected PLCs with real connection status.
/// Supports: discover, add, remove devices at runtime.
class DeviceListScreen extends StatefulWidget {
  final ApiService api;
  final void Function(PlcDevice device)? onDeviceTap;

  const DeviceListScreen({super.key, required this.api, this.onDeviceTap});

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

    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Add PLC Device'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: idCtrl,
              decoration: const InputDecoration(
                labelText: 'Device ID',
                hintText: 'e.g. plc-03',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Device Name',
                hintText: 'e.g. Mixing Tank',
              ),
            ),
            const SizedBox(height: 8),
            TextField(
              controller: addrCtrl,
              decoration: const InputDecoration(
                labelText: 'Address',
                hintText: 'e.g. 127.0.0.1:5022',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Add'),
          ),
        ],
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SafeArea(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ──
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                Icon(Icons.devices_other_rounded,
                    color: colorScheme.primary, size: 28),
                const SizedBox(width: 10),
                Text('PLC Devices',
                    style: theme.textTheme.headlineSmall
                        ?.copyWith(fontWeight: FontWeight.bold)),
                const Spacer(),
                // Scan button
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
                // Add manually
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
                  style: theme.textTheme.titleSmall
                      ?.copyWith(color: Colors.green)),
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
                            Icon(Icons.precision_manufacturing_outlined,
                                size: 64, color: Colors.grey[600]),
                            const SizedBox(height: 12),
                            Text('No devices connected',
                                style: theme.textTheme.bodyLarge
                                    ?.copyWith(color: Colors.grey[500])),
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
                                onRemove: () =>
                                    _removeDevice(_devices[i].id),
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
    final theme = Theme.of(context);
    final connected = device.isConnected;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
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
                  color: (connected ? Colors.green : Colors.red)
                      .withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  connected
                      ? Icons.check_circle_rounded
                      : Icons.error_rounded,
                  color: connected ? Colors.green : Colors.red,
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
                      style: theme.textTheme.titleMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        _InfoChip(
                          icon: Icons.tag,
                          label: device.id,
                        ),
                        const SizedBox(width: 8),
                        _InfoChip(
                          icon: Icons.lan_rounded,
                          label: device.address,
                        ),
                        const SizedBox(width: 8),
                        _InfoChip(
                          icon: Icons.cable_rounded,
                          label: device.protocol.toUpperCase(),
                        ),
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
                    style: TextStyle(
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      color: connected ? Colors.green : Colors.red,
                    ),
                  ),
                  const SizedBox(height: 4),
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
