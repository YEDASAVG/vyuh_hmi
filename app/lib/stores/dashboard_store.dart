import 'dart:async';

import 'package:mobx/mobx.dart';

import '../models/plc_data.dart';
import '../models/plc_device.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';

part 'dashboard_store.g.dart';

class DashboardStore = _DashboardStore with _$DashboardStore;

abstract class _DashboardStore with Store {
  final WebSocketService _ws;
  final ApiService _api;
  StreamSubscription? _wsSub;

  _DashboardStore({
    WebSocketService? ws,
    ApiService? api,
  })  : _ws = ws ?? WebSocketService(),
        _api = api ?? ApiService();

  // ── Connection State ──────────────────────────────────────────────

  @observable
  bool isServerConnected = false;

  @observable
  bool isWsConnected = false;

  // ── Device List ───────────────────────────────────────────────────

  @observable
  ObservableList<PlcDevice> devices = ObservableList<PlcDevice>();

  // ── Live Register Values ──────────────────────────────────────────

  @observable
  ObservableMap<int, double> liveValues = ObservableMap<int, double>();

  // ── History per Register ──────────────────────────────────────────

  @observable
  ObservableMap<int, ObservableList<PlcData>> registerHistory =
      ObservableMap<int, ObservableList<PlcData>>();

  static const int maxHistoryPoints = 60;

  // ── Batch State ───────────────────────────────────────────────────

  @observable
  BatchState batchState = BatchState.idle;

  @observable
  double batchProgress = 0;

  // ── Live display values ───────────────────────────────────────────

  @observable
  double temperature = 0;

  @observable
  double pressure = 0;

  @observable
  double humidity = 0;

  @observable
  double flowRate = 0;

  @observable
  double agitatorSpeed = 0;

  @observable
  double pH = 0;

  // ── Lifecycle ─────────────────────────────────────────────────────

  @action
  Future<void> init() async {
    isServerConnected = await _api.checkHealth();

    if (isServerConnected) {
      try {
        final deviceList = await _api.getDevices();
        devices = ObservableList.of(deviceList);
      } catch (_) {}
    }

    _ws.onConnectionChanged = _onWsConnectionChanged;
    _ws.connect();
    _wsSub = _ws.stream.listen(_onData);
  }

  @action
  void _onWsConnectionChanged(bool connected) {
    isWsConnected = connected;
    if (connected) isServerConnected = true;
  }

  @action
  void _onData(PlcData data) {
    final reg = data.register;
    final val = data.value;

    liveValues[reg] = val;

    // Update named observables so UI reacts.
    switch (reg) {
      case 1028: temperature = val;
      case 1029: pressure = val;
      case 1030: humidity = val;
      case 1031: flowRate = val;
      case 1032: batchState = BatchState.fromCode(val.toInt());
      case 1033: batchProgress = val;
      case 1034: agitatorSpeed = val;
      case 1035: pH = val / 10.0;
    }

    // Append to history.
    if (!registerHistory.containsKey(reg)) {
      registerHistory[reg] = ObservableList<PlcData>();
    }
    final history = registerHistory[reg]!;
    history.add(data);
    if (history.length > maxHistoryPoints) {
      history.removeAt(0);
    }
  }

  @action
  Future<List<PlcData>> fetchHistory({
    required String deviceId,
    int limit = 100,
  }) async {
    return _api.getHistory(deviceId: deviceId, limit: limit);
  }

  void dispose() {
    _wsSub?.cancel();
    _ws.dispose();
  }
}
