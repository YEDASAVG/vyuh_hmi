import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

/// Authenticated user info.
class AuthUser {
  final String id;
  final String username;
  final String role;
  final String token;
  final DateTime expiresAt;

  const AuthUser({
    required this.id,
    required this.username,
    required this.role,
    required this.token,
    required this.expiresAt,
  });

  bool get isExpired => DateTime.now().isAfter(expiresAt);
  bool get isAdmin => role == 'admin';
  bool get isOperator => role == 'operator' || role == 'admin';
  bool get isViewer => true; // everyone can view

  factory AuthUser.fromLoginResponse(Map<String, dynamic> data) {
    return AuthUser(
      id: data['user']['id'] as String,
      username: data['user']['username'] as String,
      role: data['user']['role'] as String,
      token: data['token'] as String,
      expiresAt: DateTime.parse(data['expires_at'] as String),
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'username': username,
        'role': role,
        'token': token,
        'expires_at': expiresAt.toIso8601String(),
      };

  factory AuthUser.fromJson(Map<String, dynamic> json) => AuthUser(
        id: json['id'] as String,
        username: json['username'] as String,
        role: json['role'] as String,
        token: json['token'] as String,
        expiresAt: DateTime.parse(json['expires_at'] as String),
      );
}

/// Audit trail entry.
class AuditEntry {
  final int id;
  final String userId;
  final String username;
  final String action;
  final String? deviceId;
  final String details;
  final String timestamp;
  final String? ipAddress;

  const AuditEntry({
    required this.id,
    required this.userId,
    required this.username,
    required this.action,
    this.deviceId,
    required this.details,
    required this.timestamp,
    this.ipAddress,
  });

  factory AuditEntry.fromJson(Map<String, dynamic> json) => AuditEntry(
        id: json['id'] as int,
        userId: json['user_id'] as String,
        username: json['username'] as String,
        action: json['action'] as String,
        deviceId: json['device_id'] as String?,
        details: json['details'] as String,
        timestamp: json['timestamp'] as String,
        ipAddress: json['ip_address'] as String?,
      );
}

/// Authentication service — manages login, token storage, and auth headers.
class AuthService extends ChangeNotifier {
  final String baseUrl;
  AuthUser? _currentUser;
  bool _isLoading = false;
  String? _error;

  AuthService({required this.baseUrl});

  AuthUser? get currentUser => _currentUser;
  bool get isAuthenticated => _currentUser != null && !_currentUser!.isExpired;
  bool get isLoading => _isLoading;
  String? get error => _error;

  /// Auth headers to attach to every API request.
  Map<String, String> get authHeaders {
    if (_currentUser == null) return {};
    return {
      'Authorization': 'Bearer ${_currentUser!.token}',
      'Content-Type': 'application/json',
    };
  }

  /// Try to restore saved session on app start.
  Future<bool> tryRestoreSession() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('auth_user');
      if (json == null) return false;

      final user = AuthUser.fromJson(jsonDecode(json) as Map<String, dynamic>);
      if (user.isExpired) {
        await prefs.remove('auth_user');
        return false;
      }

      // Verify token is still valid with server
      final response = await http.post(
        Uri.parse('$baseUrl/api/auth/verify'),
        headers: {'Authorization': 'Bearer ${user.token}'},
      ).timeout(const Duration(seconds: 3));

      if (response.statusCode == 200) {
        _currentUser = user;
        notifyListeners();
        return true;
      }

      await prefs.remove('auth_user');
      return false;
    } catch (_) {
      return false;
    }
  }

  /// Login with username and password.
  Future<bool> login(String username, String password) async {
    _isLoading = true;
    _error = null;
    notifyListeners();

    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/auth/login'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'username': username,
              'password': password,
            }),
          )
          .timeout(const Duration(seconds: 10));

      final body = jsonDecode(response.body) as Map<String, dynamic>;

      if (response.statusCode == 200 && body['success'] == true) {
        _currentUser =
            AuthUser.fromLoginResponse(body['data'] as Map<String, dynamic>);
        _error = null;

        // Save to shared prefs
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('auth_user', jsonEncode(_currentUser!.toJson()));

        _isLoading = false;
        notifyListeners();
        return true;
      }

      _error = body['error'] as String? ?? 'Login failed';
      _isLoading = false;
      notifyListeners();
      return false;
    } catch (e) {
      _error = 'Connection error: $e';
      _isLoading = false;
      notifyListeners();
      return false;
    }
  }

  /// Logout — clear token.
  Future<void> logout() async {
    _currentUser = null;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove('auth_user');
    notifyListeners();
  }

  /// Electronic signature — re-authenticate for critical actions.
  Future<bool> verifyESignature({
    required String username,
    required String password,
    required String reason,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('$baseUrl/api/auth/esig'),
            headers: authHeaders,
            body: jsonEncode({
              'username': username,
              'password': password,
              'reason': reason,
            }),
          )
          .timeout(const Duration(seconds: 5));

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      return response.statusCode == 200 && body['success'] == true;
    } catch (_) {
      return false;
    }
  }

  /// Fetch audit trail from server.
  Future<List<AuditEntry>> getAuditTrail({
    String? userId,
    String? deviceId,
    String? action,
    int limit = 100,
  }) async {
    try {
      final params = <String, String>{
        'limit': limit.toString(),
      };
      if (userId != null) params['user_id'] = userId;
      if (deviceId != null) params['device_id'] = deviceId;
      if (action != null) params['action'] = action;

      final uri =
          Uri.parse('$baseUrl/api/audit').replace(queryParameters: params);
      final response = await http
          .get(uri, headers: authHeaders)
          .timeout(const Duration(seconds: 5));

      if (response.statusCode == 200) {
        final body = jsonDecode(response.body) as Map<String, dynamic>;
        if (body['success'] == true && body['data'] != null) {
          return (body['data'] as List)
              .map(
                  (e) => AuditEntry.fromJson(e as Map<String, dynamic>))
              .toList();
        }
      }
      return [];
    } catch (_) {
      return [];
    }
  }
}
