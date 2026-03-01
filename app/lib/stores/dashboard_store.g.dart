// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'dashboard_store.dart';

// **************************************************************************
// StoreGenerator
// **************************************************************************

// ignore_for_file: non_constant_identifier_names, unnecessary_brace_in_string_interps, unnecessary_lambdas, prefer_expression_function_bodies, lines_longer_than_80_chars, avoid_as, avoid_annotating_with_dynamic, no_leading_underscores_for_local_identifiers

mixin _$DashboardStore on _DashboardStore, Store {
  late final _$isServerConnectedAtom = Atom(
    name: '_DashboardStore.isServerConnected',
    context: context,
  );

  @override
  bool get isServerConnected {
    _$isServerConnectedAtom.reportRead();
    return super.isServerConnected;
  }

  @override
  set isServerConnected(bool value) {
    _$isServerConnectedAtom.reportWrite(value, super.isServerConnected, () {
      super.isServerConnected = value;
    });
  }

  late final _$isWsConnectedAtom = Atom(
    name: '_DashboardStore.isWsConnected',
    context: context,
  );

  @override
  bool get isWsConnected {
    _$isWsConnectedAtom.reportRead();
    return super.isWsConnected;
  }

  @override
  set isWsConnected(bool value) {
    _$isWsConnectedAtom.reportWrite(value, super.isWsConnected, () {
      super.isWsConnected = value;
    });
  }

  late final _$devicesAtom = Atom(
    name: '_DashboardStore.devices',
    context: context,
  );

  @override
  ObservableList<PlcDevice> get devices {
    _$devicesAtom.reportRead();
    return super.devices;
  }

  @override
  set devices(ObservableList<PlcDevice> value) {
    _$devicesAtom.reportWrite(value, super.devices, () {
      super.devices = value;
    });
  }

  late final _$liveValuesAtom = Atom(
    name: '_DashboardStore.liveValues',
    context: context,
  );

  @override
  ObservableMap<int, double> get liveValues {
    _$liveValuesAtom.reportRead();
    return super.liveValues;
  }

  @override
  set liveValues(ObservableMap<int, double> value) {
    _$liveValuesAtom.reportWrite(value, super.liveValues, () {
      super.liveValues = value;
    });
  }

  late final _$registerHistoryAtom = Atom(
    name: '_DashboardStore.registerHistory',
    context: context,
  );

  @override
  ObservableMap<int, ObservableList<PlcData>> get registerHistory {
    _$registerHistoryAtom.reportRead();
    return super.registerHistory;
  }

  @override
  set registerHistory(ObservableMap<int, ObservableList<PlcData>> value) {
    _$registerHistoryAtom.reportWrite(value, super.registerHistory, () {
      super.registerHistory = value;
    });
  }

  late final _$batchStateAtom = Atom(
    name: '_DashboardStore.batchState',
    context: context,
  );

  @override
  BatchState get batchState {
    _$batchStateAtom.reportRead();
    return super.batchState;
  }

  @override
  set batchState(BatchState value) {
    _$batchStateAtom.reportWrite(value, super.batchState, () {
      super.batchState = value;
    });
  }

  late final _$batchProgressAtom = Atom(
    name: '_DashboardStore.batchProgress',
    context: context,
  );

  @override
  double get batchProgress {
    _$batchProgressAtom.reportRead();
    return super.batchProgress;
  }

  @override
  set batchProgress(double value) {
    _$batchProgressAtom.reportWrite(value, super.batchProgress, () {
      super.batchProgress = value;
    });
  }

  late final _$temperatureAtom = Atom(
    name: '_DashboardStore.temperature',
    context: context,
  );

  @override
  double get temperature {
    _$temperatureAtom.reportRead();
    return super.temperature;
  }

  @override
  set temperature(double value) {
    _$temperatureAtom.reportWrite(value, super.temperature, () {
      super.temperature = value;
    });
  }

  late final _$pressureAtom = Atom(
    name: '_DashboardStore.pressure',
    context: context,
  );

  @override
  double get pressure {
    _$pressureAtom.reportRead();
    return super.pressure;
  }

  @override
  set pressure(double value) {
    _$pressureAtom.reportWrite(value, super.pressure, () {
      super.pressure = value;
    });
  }

  late final _$humidityAtom = Atom(
    name: '_DashboardStore.humidity',
    context: context,
  );

  @override
  double get humidity {
    _$humidityAtom.reportRead();
    return super.humidity;
  }

  @override
  set humidity(double value) {
    _$humidityAtom.reportWrite(value, super.humidity, () {
      super.humidity = value;
    });
  }

  late final _$flowRateAtom = Atom(
    name: '_DashboardStore.flowRate',
    context: context,
  );

  @override
  double get flowRate {
    _$flowRateAtom.reportRead();
    return super.flowRate;
  }

  @override
  set flowRate(double value) {
    _$flowRateAtom.reportWrite(value, super.flowRate, () {
      super.flowRate = value;
    });
  }

  late final _$agitatorSpeedAtom = Atom(
    name: '_DashboardStore.agitatorSpeed',
    context: context,
  );

  @override
  double get agitatorSpeed {
    _$agitatorSpeedAtom.reportRead();
    return super.agitatorSpeed;
  }

  @override
  set agitatorSpeed(double value) {
    _$agitatorSpeedAtom.reportWrite(value, super.agitatorSpeed, () {
      super.agitatorSpeed = value;
    });
  }

  late final _$pHAtom = Atom(name: '_DashboardStore.pH', context: context);

  @override
  double get pH {
    _$pHAtom.reportRead();
    return super.pH;
  }

  @override
  set pH(double value) {
    _$pHAtom.reportWrite(value, super.pH, () {
      super.pH = value;
    });
  }

  late final _$isWritingAtom = Atom(
    name: '_DashboardStore.isWriting',
    context: context,
  );

  @override
  bool get isWriting {
    _$isWritingAtom.reportRead();
    return super.isWriting;
  }

  @override
  set isWriting(bool value) {
    _$isWritingAtom.reportWrite(value, super.isWriting, () {
      super.isWriting = value;
    });
  }

  late final _$agitatorOverrideActiveAtom = Atom(
    name: '_DashboardStore.agitatorOverrideActive',
    context: context,
  );

  @override
  bool get agitatorOverrideActive {
    _$agitatorOverrideActiveAtom.reportRead();
    return super.agitatorOverrideActive;
  }

  @override
  set agitatorOverrideActive(bool value) {
    _$agitatorOverrideActiveAtom.reportWrite(
      value,
      super.agitatorOverrideActive,
      () {
        super.agitatorOverrideActive = value;
      },
    );
  }

  late final _$lastWriteErrorAtom = Atom(
    name: '_DashboardStore.lastWriteError',
    context: context,
  );

  @override
  String? get lastWriteError {
    _$lastWriteErrorAtom.reportRead();
    return super.lastWriteError;
  }

  @override
  set lastWriteError(String? value) {
    _$lastWriteErrorAtom.reportWrite(value, super.lastWriteError, () {
      super.lastWriteError = value;
    });
  }

  late final _$activeAlarmsAtom = Atom(
    name: '_DashboardStore.activeAlarms',
    context: context,
  );

  @override
  ObservableList<Alarm> get activeAlarms {
    _$activeAlarmsAtom.reportRead();
    return super.activeAlarms;
  }

  @override
  set activeAlarms(ObservableList<Alarm> value) {
    _$activeAlarmsAtom.reportWrite(value, super.activeAlarms, () {
      super.activeAlarms = value;
    });
  }

  late final _$initAsyncAction = AsyncAction(
    '_DashboardStore.init',
    context: context,
  );

  @override
  Future<void> init() {
    return _$initAsyncAction.run(() => super.init());
  }

  late final _$writeRegisterAsyncAction = AsyncAction(
    '_DashboardStore.writeRegister',
    context: context,
  );

  @override
  Future<bool> writeRegister({required int register, required int value}) {
    return _$writeRegisterAsyncAction.run(
      () => super.writeRegister(register: register, value: value),
    );
  }

  late final _$emergencyStopAsyncAction = AsyncAction(
    '_DashboardStore.emergencyStop',
    context: context,
  );

  @override
  Future<bool> emergencyStop() {
    return _$emergencyStopAsyncAction.run(() => super.emergencyStop());
  }

  late final _$setAgitatorRpmAsyncAction = AsyncAction(
    '_DashboardStore.setAgitatorRpm',
    context: context,
  );

  @override
  Future<bool> setAgitatorRpm(int rpm) {
    return _$setAgitatorRpmAsyncAction.run(() => super.setAgitatorRpm(rpm));
  }

  late final _$clearAgitatorOverrideAsyncAction = AsyncAction(
    '_DashboardStore.clearAgitatorOverride',
    context: context,
  );

  @override
  Future<bool> clearAgitatorOverride() {
    return _$clearAgitatorOverrideAsyncAction.run(
      () => super.clearAgitatorOverride(),
    );
  }

  late final _$fetchHistoryAsyncAction = AsyncAction(
    '_DashboardStore.fetchHistory',
    context: context,
  );

  @override
  Future<List<PlcData>> fetchHistory({
    required String deviceId,
    int limit = 100,
  }) {
    return _$fetchHistoryAsyncAction.run(
      () => super.fetchHistory(deviceId: deviceId, limit: limit),
    );
  }

  late final _$_DashboardStoreActionController = ActionController(
    name: '_DashboardStore',
    context: context,
  );

  @override
  void _onWsConnectionChanged(bool connected) {
    final _$actionInfo = _$_DashboardStoreActionController.startAction(
      name: '_DashboardStore._onWsConnectionChanged',
    );
    try {
      return super._onWsConnectionChanged(connected);
    } finally {
      _$_DashboardStoreActionController.endAction(_$actionInfo);
    }
  }

  @override
  void _onData(PlcData data) {
    final _$actionInfo = _$_DashboardStoreActionController.startAction(
      name: '_DashboardStore._onData',
    );
    try {
      return super._onData(data);
    } finally {
      _$_DashboardStoreActionController.endAction(_$actionInfo);
    }
  }

  @override
  void _checkAlarms() {
    final _$actionInfo = _$_DashboardStoreActionController.startAction(
      name: '_DashboardStore._checkAlarms',
    );
    try {
      return super._checkAlarms();
    } finally {
      _$_DashboardStoreActionController.endAction(_$actionInfo);
    }
  }

  @override
  void dismissAlarm(String alarmId) {
    final _$actionInfo = _$_DashboardStoreActionController.startAction(
      name: '_DashboardStore.dismissAlarm',
    );
    try {
      return super.dismissAlarm(alarmId);
    } finally {
      _$_DashboardStoreActionController.endAction(_$actionInfo);
    }
  }

  @override
  String toString() {
    return '''
isServerConnected: ${isServerConnected},
isWsConnected: ${isWsConnected},
devices: ${devices},
liveValues: ${liveValues},
registerHistory: ${registerHistory},
batchState: ${batchState},
batchProgress: ${batchProgress},
temperature: ${temperature},
pressure: ${pressure},
humidity: ${humidity},
flowRate: ${flowRate},
agitatorSpeed: ${agitatorSpeed},
pH: ${pH},
isWriting: ${isWriting},
agitatorOverrideActive: ${agitatorOverrideActive},
lastWriteError: ${lastWriteError},
activeAlarms: ${activeAlarms}
    ''';
  }
}
