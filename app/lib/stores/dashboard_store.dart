import 'dart:async';

import 'package:mobx/mobx.dart';

import '../models/plc_data.dart';
import '../models/plc_device.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import '../widgets/alarm_banner_widget.dart';

part 'dashboard_store.g.dart';

class DashboardStore = _DashboardStore with _$DashboardStore;

/// Alarm threshold configuration for pharma batch reactor.
class _AlarmThresholds {
  static const double tempWarning = 85;
  static const double tempCritical = 100;
  static const double pressureWarning = 1200;
  static const double pressureCritical = 1400;
  static const double phLow = 5.5;
  static const double phHigh = 8.5;
}

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

  // ── Phase 4: Write Control State ──────────────────────────────────

  @observable
  bool isWriting = false;

  @observable
  bool agitatorOverrideActive = false;

  @observable
  String? lastWriteError;

  // ── Phase 4: Alarms ───────────────────────────────────────────────

  @observable
  ObservableList<Alarm> activeAlarms = ObservableList<Alarm>();

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

    // Phase 4: Check alarm thresholds.
    _checkAlarms();
  }

  // ── Phase 4: Write Actions ────────────────────────────────────────

  /// Write a value to a PLC register via the REST API.
  @action
  Future<bool> writeRegister({
    required int register,
    required int value,
    String deviceId = 'plc-01',
  }) async {
    isWriting = true;
    lastWriteError = null;

    try {
      final success = await _api.writeRegister(
        deviceId: deviceId,
        register: register,
        value: value,
      );

      if (!success) {
        lastWriteError = 'Server rejected write to register $register';
      }

      // Track agitator override state.
      if (register == 1034) {
        agitatorOverrideActive = value > 0;
      }

      return success;
    } catch (e) {
      lastWriteError = e.toString();
      return false;
    } finally {
      isWriting = false;
    }
  }

  /// Emergency stop — force batch to IDLE (register 1032 = 0).
  @action
  Future<bool> emergencyStop() async {
    return writeRegister(register: 1032, value: 0);
  }

  /// Set agitator RPM override (register 1034).
  @action
  Future<bool> setAgitatorRpm(int rpm) async {
    return writeRegister(register: 1034, value: rpm);
  }

  /// Clear agitator override — send 0 to register 1034.
  @action
  Future<bool> clearAgitatorOverride() async {
    agitatorOverrideActive = false;
    return writeRegister(register: 1034, value: 0);
  }

  // ── Phase 4: Alarm Logic ──────────────────────────────────────────

  @action
  void _checkAlarms() {
    final newAlarms = <Alarm>[];

    // Temperature alarms
    if (temperature >= _AlarmThresholds.tempCritical) {
      newAlarms.add(Alarm(
        id: 'temp-critical',
        message: 'CRITICAL: Temperature ${temperature.toInt()}°C exceeds ${_AlarmThresholds.tempCritical.toInt()}°C',
        severity: AlarmSeverity.critical,
        register: 1028,
      ));
    } else if (temperature >= _AlarmThresholds.tempWarning) {
      newAlarms.add(Alarm(
        id: 'temp-warning',
        message: 'WARNING: Temperature ${temperature.toInt()}°C approaching limit',
        severity: AlarmSeverity.warning,
        register: 1028,
      ));
    }

    // Pressure alarms
    if (pressure >= _AlarmThresholds.pressureCritical) {
      newAlarms.add(Alarm(
        id: 'pressure-critical',
        message: 'CRITICAL: Pressure ${pressure.toInt()} mbar exceeds ${_AlarmThresholds.pressureCritical.toInt()} mbar',
        severity: AlarmSeverity.critical,
        register: 1029,
      ));
    } else if (pressure >= _AlarmThresholds.pressureWarning) {
      newAlarms.add(Alarm(
        id: 'pressure-warning',
        message: 'WARNING: Pressure ${pressure.toInt()} mbar elevated',
        severity: AlarmSeverity.warning,
        register: 1029,
      ));
    }

    // pH alarms
    if (pH > 0 && (pH < _AlarmThresholds.phLow || pH > _AlarmThresholds.phHigh)) {
      newAlarms.add(Alarm(
        id: 'ph-warning',
        message: 'WARNING: pH ${pH.toStringAsFixed(1)} outside safe range (${_AlarmThresholds.phLow}–${_AlarmThresholds.phHigh})',
        severity: AlarmSeverity.warning,
        register: 1035,
      ));
    }

    // Connection alarm
    if (!isWsConnected && isServerConnected) {
      newAlarms.add(Alarm(
        id: 'ws-disconnected',
        message: 'WebSocket disconnected — live data paused',
        severity: AlarmSeverity.info,
      ));
    }

    activeAlarms = ObservableList.of(newAlarms);
  }

  @action
  void dismissAlarm(String alarmId) {
    activeAlarms.removeWhere((a) => a.id == alarmId);
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
