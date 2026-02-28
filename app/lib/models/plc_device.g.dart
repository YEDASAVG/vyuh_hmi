// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'plc_device.dart';

// **************************************************************************
// JsonSerializableGenerator
// **************************************************************************

PlcDevice _$PlcDeviceFromJson(Map<String, dynamic> json) => PlcDevice(
  id: json['id'] as String,
  name: json['name'] as String,
  address: json['address'] as String,
  protocol: json['protocol'] as String,
  isConnected: json['is_connected'] as bool,
);

Map<String, dynamic> _$PlcDeviceToJson(PlcDevice instance) => <String, dynamic>{
  'id': instance.id,
  'name': instance.name,
  'address': instance.address,
  'protocol': instance.protocol,
  'is_connected': instance.isConnected,
};
