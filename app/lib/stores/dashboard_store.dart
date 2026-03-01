import 'dart:async';

import 'package:mobx/mobx.dart';

import '../config/dashboard_config.dart';
import '../models/plc_data.dart';
import '../models/plc_device.dart';
import '../services/api_service.dart';
import '../services/websocket_service.dart';
import '../widgets/alarm_banner_widget.dart';

part 'dashboard_store.g.dart';

class DashboardStore = _DashboardStore with _$DashboardStore;

abstract class _DashboardStore with Store {
  final WebSocketService _ws;
  final ApiService _api;
  final DashboardConfig config;
  StreamSubscription? _wsSub;

  _DashboardStore({
    required this.config,
    WebSocketService? ws,
    ApiService? api,
  })  : _ws = ws ?? WebSocketService(url: config.server.wsUrl),
        _api = api ?? ApiService(baseUrl: config.server.httpUrl);

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

    // Update named observables from config register definitions.
    final regConfig = config.registerByAddress(reg);
    if (regConfig != null) {
      final applied = regConfig.applyDivisor(val);
      switch (regConfig.key) {
        case 'temperature': temperature = applied;
        case 'pressure': pressure = applied;
        case 'humidity': humidity = applied;
        case 'flowRate': flowRate = applied;
        case 'batchState': batchState = BatchState.fromCode(val.toInt());
        case 'batchProgress': batchProgress = applied;
        case 'agitatorSpeed': agitatorSpeed = applied;
        case 'pH': pH = applied;
      }
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

    // Check alarm thresholds from config.
    _checkAlarms();
  }

  // ── Phase 4: Write Actions ────────────────────────────────────────

  /// Write a value to a PLC register via the REST API.
  @action
  Future<bool> writeRegister({
    required int register,
    required int value,
  }) async {
    isWriting = true;
    lastWriteError = null;

    try {
      final success = await _api.writeRegister(
        deviceId: config.device.id,
        register: register,
        value: value,
      );

      if (!success) {
        lastWriteError = 'Server rejected write to register $register';
      }

      // Track agitator override state.
      final agitatorReg = config.dashboard.controls?.agitator?.register;
      if (agitatorReg != null && register == agitatorReg) {
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

  /// Emergency stop — force batch to IDLE.
  @action
  Future<bool> emergencyStop() async {
    final ctrl = config.dashboard.controls?.emergencyStop;
    if (ctrl == null) return false;
    return writeRegister(register: ctrl.register, value: ctrl.stopValue);
  }

  /// Restart batch — clear emergency stop and resume.
  @action
  Future<bool> restartBatch() async {
    final ctrl = config.dashboard.controls?.emergencyStop;
    if (ctrl == null) return false;
    return writeRegister(register: ctrl.register, value: ctrl.restartValue);
  }

  /// Set agitator RPM override.
  @action
  Future<bool> setAgitatorRpm(int rpm) async {
    final ctrl = config.dashboard.controls?.agitator;
    if (ctrl == null) return false;
    return writeRegister(register: ctrl.register, value: rpm);
  }

  /// Clear agitator override — send 0.
  @action
  Future<bool> clearAgitatorOverride() async {
    agitatorOverrideActive = false;
    final ctrl = config.dashboard.controls?.agitator;
    if (ctrl == null) return false;
    return writeRegister(register: ctrl.register, value: 0);
  }

  // ── Phase 4: Alarm Logic ──────────────────────────────────────────

  @action
  void _checkAlarms() {
    final newAlarms = <Alarm>[];

    // Config-driven alarm thresholds.
    for (final threshold in config.alarms) {
      final raw = liveValues[threshold.register];
      if (raw == null) continue;

      // Apply divisor if register has one.
      final regConfig = config.registerByAddress(threshold.register);
      final val = regConfig != null ? regConfig.applyDivisor(raw) : raw;

      // High thresholds
      if (threshold.critHigh != null && val >= threshold.critHigh!) {
        newAlarms.add(Alarm(
          id: '${threshold.label}-crit-high',
          message:
              'CRITICAL: ${threshold.label} ${val.toStringAsFixed(1)} exceeds ${threshold.critHigh!.toStringAsFixed(0)}',
          severity: AlarmSeverity.critical,
          register: threshold.register,
        ));
      } else if (threshold.warnHigh != null && val >= threshold.warnHigh!) {
        newAlarms.add(Alarm(
          id: '${threshold.label}-warn-high',
          message:
              'WARNING: ${threshold.label} ${val.toStringAsFixed(1)} approaching limit',
          severity: AlarmSeverity.warning,
          register: threshold.register,
        ));
      }

      // Low thresholds
      if (threshold.critLow != null && val > 0 && val <= threshold.critLow!) {
        newAlarms.add(Alarm(
          id: '${threshold.label}-crit-low',
          message:
              'CRITICAL: ${threshold.label} ${val.toStringAsFixed(1)} below ${threshold.critLow!.toStringAsFixed(0)}',
          severity: AlarmSeverity.critical,
          register: threshold.register,
        ));
      } else if (threshold.warnLow != null &&
          val > 0 &&
          val <= threshold.warnLow!) {
        newAlarms.add(Alarm(
          id: '${threshold.label}-warn-low',
          message:
              'WARNING: ${threshold.label} ${val.toStringAsFixed(1)} below safe range',
          severity: AlarmSeverity.warning,
          register: threshold.register,
        ));
      }
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
