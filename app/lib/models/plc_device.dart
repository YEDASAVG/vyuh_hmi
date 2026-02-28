import 'package:json_annotation/json_annotation.dart';

part 'plc_device.g.dart';

/// A PLC device on the network.
/// Matches server JSON from GET /api/devices.
@JsonSerializable()
class PlcDevice {
  final String id;
  final String name;
  final String address;
  final String protocol;
  @JsonKey(name: 'is_connected')
  final bool isConnected;

  PlcDevice({
    required this.id,
    required this.name,
    required this.address,
    required this.protocol,
    required this.isConnected,
  });

  factory PlcDevice.fromJson(Map<String, dynamic> json) =>
      _$PlcDeviceFromJson(json);
  Map<String, dynamic> toJson() => _$PlcDeviceToJson(this);
}
