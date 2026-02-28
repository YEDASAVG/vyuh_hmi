// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'plc_data.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PlcData _$PlcDataFromJson(Map<String, dynamic> json) => PlcData(
  deviceId: json['device_id'] as String,
  register: (json['register'] as num).toInt(),
  value: (json['value'] as num).toDouble(),
  timestamp: json['timestamp'] as String,
);

Map<String, dynamic> _$PlcDataToJson(PlcData instance) => <String, dynamic>{
  'device_id': instance.deviceId,
  'register': instance.register,
  'value': instance.value,
  'timestamp': instance.timestamp,
};
