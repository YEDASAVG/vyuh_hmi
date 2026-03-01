import 'dart:convert';

import 'package:http/http.dart' as http;

import '../models/api_response.dart';
import '../models/plc_data.dart';
import '../models/plc_device.dart';

/// REST API service for the Rust HMI server.
class ApiService {
  final String baseUrl;

  ApiService({this.baseUrl = 'http://127.0.0.1:3000'});

  /// GET /api/devices — fetch all known PLC devices.
  Future<List<PlcDevice>> getDevices() async {
    final response = await http.get(Uri.parse('$baseUrl/api/devices'));

    if (response.statusCode == 200) {
      final apiResp = ApiResponse<List<PlcDevice>>.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
        (json) => (json as List)
            .map((e) => PlcDevice.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
      return apiResp.data ?? [];
    }
    throw Exception('Failed to fetch devices: ${response.statusCode}');
  }

  /// GET /api/history?device_id=...&limit=... — fetch historical readings.
  Future<List<PlcData>> getHistory({
    required String deviceId,
    int limit = 100,
  }) async {
    final uri = Uri.parse('$baseUrl/api/history').replace(
      queryParameters: {
        'device_id': deviceId,
        'limit': limit.toString(),
      },
    );
    final response = await http.get(uri);

    if (response.statusCode == 200) {
      final apiResp = ApiResponse<List<PlcData>>.fromJson(
        jsonDecode(response.body) as Map<String, dynamic>,
        (json) => (json as List)
            .map((e) => PlcData.fromJson(e as Map<String, dynamic>))
            .toList(),
      );
      return apiResp.data ?? [];
    }
    throw Exception('Failed to fetch history: ${response.statusCode}');
  }

  /// GET /health — check server health.
  Future<bool> checkHealth() async {
    try {
      final response = await http
          .get(Uri.parse('$baseUrl/health'))
          .timeout(const Duration(seconds: 3));
      return response.statusCode == 200;
    } catch (_) {
      return false;
    }
  }

  /// POST /api/write — write a value to a PLC register.
  ///
  /// Used for bidirectional control (Phase 4):
  ///   - Register 1032: Batch State (write 0 = emergency stop → IDLE)
  ///   - Register 1034: Agitator Speed (operator override RPM)
  ///
  /// Returns `true` if server confirms write success.
  Future<bool> writeRegister({
    required String deviceId,
    required int register,
    required int value,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/write'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'device_id': deviceId,
              'register': register,
              'value': value,
            }),
          )
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        return body['success'] == true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }
}
