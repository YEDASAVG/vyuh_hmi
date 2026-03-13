import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/plc_data.dart';

/// WebSocket service that connects to the Rust server,
/// parses PlcData JSON, and auto-reconnects on disconnect.
class WebSocketService {
  final String url;
  final Duration reconnectDelay;

  /// JWT token appended as ?token= query param for auth.
  String? authToken;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  bool _disposed = false;
  bool _authFailed = false;

  final _controller = StreamController<PlcData>.broadcast();

  /// Stream of parsed PlcData from the server.
  Stream<PlcData> get stream => _controller.stream;

  /// Whether currently connected.
  bool get isConnected => _channel != null;

  /// Callback when connection state changes.
  void Function(bool connected)? onConnectionChanged;

  /// Called when the server rejects auth (session_revoked / auth_failed).
  /// The app should respond by forcing re-login.
  void Function()? onAuthFailed;

  WebSocketService({
    this.url = 'ws://127.0.0.1:3000/ws',
    this.reconnectDelay = const Duration(seconds: 3),
    this.authToken,
  });

  /// Set auth token (called after login).
  void setAuthToken(String? token) {
    authToken = token;
    _authFailed = false; // new token — allow reconnect
  }

  /// Start the connection.
  void connect() {
    if (_disposed) return;
    _authFailed = false;
    _doConnect();
  }

  Future<void> _doConnect() async {
    if (_authFailed || _disposed) return;

    try {
      // Connect without token in URL — auth via first message
      final wsUri = Uri.parse(url);
      _channel = WebSocketChannel.connect(wsUri);

      // Wait for the actual WebSocket handshake to complete.
      await _channel!.ready;

      // Send JWT as first message for authentication
      if (authToken != null) {
        _channel!.sink.add(authToken!);
      }

      _subscription = _channel!.stream.listen(
        (raw) {
          try {
            final json = jsonDecode(raw as String) as Map<String, dynamic>;

            // Handle auth response from server
            if (json.containsKey('auth') && json['auth'] == 'ok') {
              onConnectionChanged?.call(true);
              return;
            }
            if (json.containsKey('error')) {
              // Auth rejected — stop reconnect loop, notify app
              _authFailed = true;
              _closeChannel();
              onConnectionChanged?.call(false);
              onAuthFailed?.call();
              return;
            }

            final data = PlcData.fromJson(json);
            _controller.add(data);
          } catch (_) {
            // Malformed message — skip.
          }
        },
        onError: (error) {
          _handleDisconnect();
        },
        onDone: () {
          _handleDisconnect();
        },
      );
    } catch (_) {
      _handleDisconnect();
    }
  }

  void _closeChannel() {
    _channel?.sink.close();
    _channel = null;
    _subscription?.cancel();
    _subscription = null;
  }

  void _handleDisconnect() {
    _closeChannel();
    onConnectionChanged?.call(false);

    if (!_disposed && !_authFailed) {
      _reconnectTimer?.cancel();
      _reconnectTimer = Timer(reconnectDelay, _doConnect);
    }
  }

  /// Close the connection permanently.
  void dispose() {
    _disposed = true;
    _reconnectTimer?.cancel();
    _subscription?.cancel();
    _channel?.sink.close();
    _controller.close();
  }
}
