import 'dart:async';
import 'dart:convert';

import 'package:web_socket_channel/web_socket_channel.dart';

import '../models/plc_data.dart';

/// WebSocket service that connects to the Rust server,
/// parses PlcData JSON, and auto-reconnects on disconnect.
class WebSocketService {
  final String url;
  final Duration reconnectDelay;

  WebSocketChannel? _channel;
  StreamSubscription? _subscription;
  Timer? _reconnectTimer;
  bool _disposed = false;

  final _controller = StreamController<PlcData>.broadcast();

  /// Stream of parsed PlcData from the server.
  Stream<PlcData> get stream => _controller.stream;

  /// Whether currently connected.
  bool get isConnected => _channel != null;

  /// Callback when connection state changes.
  void Function(bool connected)? onConnectionChanged;

  WebSocketService({
    this.url = 'ws://127.0.0.1:3000/ws',
    this.reconnectDelay = const Duration(seconds: 3),
  });

  /// Start the connection.
  void connect() {
    if (_disposed) return;
    _doConnect();
  }

  Future<void> _doConnect() async {
    try {
      final uri = Uri.parse(url);
      _channel = WebSocketChannel.connect(uri);

      // Wait for the actual WebSocket handshake to complete.
      await _channel!.ready;

      onConnectionChanged?.call(true);

      _subscription = _channel!.stream.listen(
        (raw) {
          try {
            final json = jsonDecode(raw as String) as Map<String, dynamic>;
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

  void _handleDisconnect() {
    _channel = null;
    _subscription?.cancel();
    _subscription = null;
    onConnectionChanged?.call(false);

    if (!_disposed) {
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
