import 'package:json_annotation/json_annotation.dart';

part 'plc_data.g.dart';

/// Single register reading from a PLC device.
/// Matches server JSON: {"device_id":"plc-01","register":1028,"value":75.0,"timestamp":"..."}
@JsonSerializable()
class PlcData {
  @JsonKey(name: 'device_id')
  final String deviceId;
  final int register;
  final double value;
  final String timestamp;

  PlcData({
    required this.deviceId,
    required this.register,
    required this.value,
    required this.timestamp,
  });

  factory PlcData.fromJson(Map<String, dynamic> json) =>
      _$PlcDataFromJson(json);
  Map<String, dynamic> toJson() => _$PlcDataToJson(this);

  /// Human-readable register name.
  String get registerName => registerNames[register] ?? 'Unknown';

  /// Unit for the register value.
  String get unit => registerUnits[register] ?? '';

  /// Register address → readable name.
  static const registerNames = {
    1028: 'Temperature',
    1029: 'Pressure',
    1030: 'Humidity',
    1031: 'Flow Rate',
    1032: 'Batch State',
    1033: 'Progress',
    1034: 'Agitator',
    1035: 'pH',
  };

  /// Register address → unit.
  static const registerUnits = {
    1028: '°C',
    1029: 'mbar',
    1030: '%',
    1031: 'L/min',
    1032: '',
    1033: '%',
    1034: 'RPM',
    1035: '',
  };
}

/// Batch state enum matching Rust server values.
enum BatchState {
  idle(0, 'IDLE'),
  heating(1, 'HEATING'),
  holding(2, 'HOLDING'),
  cooling(3, 'COOLING'),
  complete(4, 'COMPLETE');

  const BatchState(this.code, this.label);
  final int code;
  final String label;

  static BatchState fromCode(int code) {
    return BatchState.values.firstWhere(
      (s) => s.code == code,
      orElse: () => BatchState.idle,
    );
  }
}
